using Dapper;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.IntegrationTests.Infrastructure;

public sealed partial class DbFixture
{
    /// <summary>
    /// Xoá toàn bộ dữ liệu integration test (theo PATTERN đặt tên của TestDataSeeder,
    /// không chỉ theo suffix của fixture) — vừa dọn dữ liệu của lần chạy này, vừa
    /// self-healing: tự dọn luôn dữ liệu sót từ các lần chạy thất bại trước.
    /// An toàn vì toàn bộ test collections đã bị tuần tự hoá
    /// (DisableTestParallelization — xem Properties/AssemblyInfo.cs).
    /// Xoá theo thứ tự FK. Dùng connection admin vì api_service không có DELETE.
    /// </summary>
    public async Task CleanupSuffixAsync()
    {
        const string cleanup = @"
            -- Ghi chú: KHÔNG khai báo DECLARE @suffix. Dapper truyền @Suffix qua
            -- sp_executesql; nếu DECLARE trùng tên (không phân biệt hoa thường) sẽ gây
            -- lỗi ''The variable name ''@suffix'' has already been declared.''.
            DECLARE @TestUsers TABLE (UserID INT NOT NULL PRIMARY KEY);
            INSERT INTO @TestUsers (UserID)
            SELECT UserID FROM UserAccount
            WHERE Username LIKE 'it[_]%' OR Email LIKE '%@it.test';

            -- 0. AuditRecord (actor của các SP nghiệp vụ ghi audit — phải xóa trước UserAccount).
            --    Lưu ý: TRG_AuditLog cấm mọi UPDATE/DELETE (BR50). Test cleanup phải tạm thời
            --    disable trigger, xóa audit của dữ liệu test, rồi enable lại (kể cả khi lỗi).
            BEGIN TRY
                DISABLE TRIGGER TRG_AuditLog ON AuditRecord;
                DELETE ar FROM AuditRecord ar
                WHERE ar.ActorUserID IN (SELECT UserID FROM @TestUsers);
                ENABLE TRIGGER TRG_AuditLog ON AuditRecord;
            END TRY
            BEGIN CATCH
                ENABLE TRIGGER TRG_AuditLog ON AuditRecord;
                THROW;
            END CATCH;

            DECLARE @TestBookings TABLE (BookingID INT NOT NULL PRIMARY KEY);
            INSERT INTO @TestBookings (BookingID)
            SELECT b.BookingID FROM Booking b
            WHERE b.CustomerUserID IN (SELECT UserID FROM @TestUsers);

            -- 1. Refund -> Payment -> Ticket/CheckIn -> Allocation/BPA -> Booking
            DELETE r FROM Refund r
            JOIN Payment p ON p.PaymentID = r.PaymentID
            WHERE p.BookingID IN (SELECT BookingID FROM @TestBookings);

            DELETE p FROM Payment p
            WHERE p.BookingID IN (SELECT BookingID FROM @TestBookings);

            DELETE ci FROM CheckIn ci
            WHERE ci.TicketID IN (
                SELECT t.TicketID FROM Ticket t
                WHERE t.BookingID IN (SELECT BookingID FROM @TestBookings));

            DELETE t FROM Ticket t
            WHERE t.BookingID IN (SELECT BookingID FROM @TestBookings);

            DELETE besa FROM BookingEventSeatAllocation besa
            WHERE besa.BookingID IN (SELECT BookingID FROM @TestBookings);

            DELETE bpa FROM BookingPromotionApplication bpa
            WHERE bpa.BookingID IN (SELECT BookingID FROM @TestBookings);

            DELETE b FROM Booking b
            WHERE b.BookingID IN (SELECT BookingID FROM @TestBookings);

            -- 2. Waitlist / Queue (entry trước, master sau)
            DELETE we FROM WaitlistEntry we
            WHERE we.CustomerUserID IN (SELECT UserID FROM @TestUsers);
            DELETE qe FROM QueueEntry qe
            WHERE qe.CustomerUserID IN (SELECT UserID FROM @TestUsers);
            DELETE w FROM Waitlist w
            WHERE NOT EXISTS (SELECT 1 FROM WaitlistEntry we2 WHERE we2.WaitlistID = w.WaitlistID);
            DELETE q FROM Queue q
            WHERE NOT EXISTS (SELECT 1 FROM QueueEntry qe2 WHERE qe2.QueueID = q.QueueID);

            -- 3. EventSeat + TicketCategory + Promotion/DC + CheckinStaffAssignment + Concert
            DECLARE @TestConcerts TABLE (ConcertID INT NOT NULL PRIMARY KEY);
            INSERT INTO @TestConcerts (ConcertID)
            SELECT ConcertID FROM Concert WHERE ConcertName LIKE 'IT-Concert-%';

            DELETE es FROM EventSeat es
            WHERE es.ConcertID IN (SELECT ConcertID FROM @TestConcerts);
            DELETE tc FROM TicketCategory tc
            WHERE tc.ConcertID IN (SELECT ConcertID FROM @TestConcerts);
            DELETE dc FROM DiscountCode dc
            WHERE dc.PromotionID IN (
                SELECT pm.PromotionID FROM Promotion pm
                WHERE pm.ConcertID IN (SELECT ConcertID FROM @TestConcerts));
            DELETE pm FROM Promotion pm
            WHERE pm.ConcertID IN (SELECT ConcertID FROM @TestConcerts);
            DELETE csa FROM CheckinStaffAssignment csa
            WHERE csa.ConcertID IN (SELECT ConcertID FROM @TestConcerts);
            DELETE c FROM Concert c
            WHERE c.ConcertID IN (SELECT ConcertID FROM @TestConcerts);

            -- 4. Seat/Zone theo Venue test; Venue; Artist
            DECLARE @TestVenues TABLE (VenueID INT NOT NULL PRIMARY KEY);
            INSERT INTO @TestVenues (VenueID)
            SELECT VenueID FROM Venue WHERE VenueName LIKE 'IT-Venue-%';

            DELETE s FROM Seat s
            WHERE s.VenueID IN (SELECT VenueID FROM @TestVenues);
            DELETE z FROM Zone z
            WHERE z.VenueID IN (SELECT VenueID FROM @TestVenues);
            DELETE v FROM Venue v
            WHERE v.VenueID IN (SELECT VenueID FROM @TestVenues);
            DELETE a FROM Artist a WHERE a.ArtistName LIKE 'IT-Artist-%';

            -- 5. RefreshToken + UserRoleAssignment + UserAccount
            DELETE rt FROM RefreshToken rt
            WHERE rt.UserID IN (SELECT UserID FROM @TestUsers);
            DELETE ura FROM UserRoleAssignment ura
            WHERE ura.UserID IN (SELECT UserID FROM @TestUsers);
            DELETE ua FROM UserAccount ua
            WHERE ua.UserID IN (SELECT UserID FROM @TestUsers);
        ";

        await ExecAdminAsync(cleanup);
    }
}