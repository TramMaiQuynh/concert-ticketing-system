using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Domain.Models;

namespace ConcertTicketing.Application.Interfaces;

// ── Repository Interfaces (định nghĩa trong Application, implement trong Infrastructure) ──

public interface IUserRepository
{
    Task<UserAccount?> GetByUsernameAsync(string username);
    Task<IEnumerable<string>> GetRolesAsync(int userId);
    Task<int> CreateAsync(UserAccount user, string passwordHash);
}

public interface IBookingRepository
{
    Task<CreateBookingResponse> CreateAsync(int customerUserId, CreateBookingRequest request);
    Task<BookingDetail?> GetByIdAsync(int bookingId, int customerUserId);
    Task CancelAsync(int bookingId, int customerUserId);
    Task ApplyPromotionAsync(int bookingId, int customerUserId, string discountCode);
}

public interface IConcertRepository
{
    Task<IEnumerable<ConcertListItem>> GetListAsync(int page, int pageSize, string? status);
    Task<ConcertDetail?> GetByIdAsync(int concertId);
    Task<IEnumerable<SeatDto>> GetSeatsAsync(int concertId);
}

public interface ICheckInRepository
{
    Task<CheckInResponse> CheckInAsync(int staffUserId, CheckInRequest request);
}
