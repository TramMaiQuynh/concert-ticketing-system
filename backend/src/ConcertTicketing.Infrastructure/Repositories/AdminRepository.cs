using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

public class AdminRepository : IAdminRepository
{
    private readonly string _connectionString;

    public AdminRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<int> CreateConcertAsync(int actorUserId, CreateConcertRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@OrganizerUserID", actorUserId, DbType.Int32);
        p.Add("@ArtistID", r.ArtistId, DbType.Int32);
        p.Add("@VenueID", r.VenueId, DbType.Int32);
        p.Add("@ConcertName", r.ConcertName, DbType.String, size: 255);
        p.Add("@StartDatetime", r.StartDatetime, DbType.DateTime2);
        p.Add("@EndDatetime", r.EndDatetime, DbType.DateTime2);
        p.Add("@ConcertStatus", r.ConcertStatus, DbType.String, size: 32);
        p.Add("@PurchaseLimit", r.PurchaseLimit, DbType.Int32);
        p.Add("@SaleStartDatetime", r.SaleStartDatetime, DbType.DateTime2);
        p.Add("@SaleEndDatetime", r.SaleEndDatetime, DbType.DateTime2);
        p.Add("@TemporaryHoldDuration", r.TemporaryHoldDuration, DbType.Int32);
        p.Add("@FairAccessEnabled", r.FairAccessEnabled, DbType.Boolean);
        p.Add("@WaitlistEnabled", r.WaitlistEnabled, DbType.Boolean);
        p.Add("@SalesPaused", r.SalesPaused, DbType.Boolean);
        p.Add("@CancellationPolicy", r.CancellationPolicy, DbType.String, size: 500);
        p.Add("@RefundPolicy", r.RefundPolicy, DbType.String, size: 500);
        p.Add("@NewConcertID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateConcert", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewConcertID");
    }

    public async Task UpdateConcertAsync(int concertId, int actorUserId, UpdateConcertRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertName", r.ConcertName, DbType.String, size: 255);
        p.Add("@ArtistID", r.ArtistId, DbType.Int32);
        p.Add("@VenueID", r.VenueId, DbType.Int32);
        p.Add("@StartDatetime", r.StartDatetime, DbType.DateTime2);
        p.Add("@EndDatetime", r.EndDatetime, DbType.DateTime2);
        p.Add("@SaleStartDatetime", r.SaleStartDatetime, DbType.DateTime2);
        p.Add("@SaleEndDatetime", r.SaleEndDatetime, DbType.DateTime2);
        p.Add("@PurchaseLimit", r.PurchaseLimit, DbType.Int32);
        p.Add("@TemporaryHoldDuration", r.TemporaryHoldDuration, DbType.Int32);
        p.Add("@FairAccessEnabled", r.FairAccessEnabled, DbType.Boolean);
        p.Add("@WaitlistEnabled", r.WaitlistEnabled, DbType.Boolean);
        p.Add("@SalesPaused", r.SalesPaused, DbType.Boolean);
        p.Add("@CancellationPolicy", r.CancellationPolicy, DbType.String, size: 500);
        p.Add("@RefundPolicy", r.RefundPolicy, DbType.String, size: 500);
        await conn.ExecuteAsync("sp_UpdateConcert", p, commandType: CommandType.StoredProcedure);
    }

    public async Task UpdateConcertStatusAsync(int concertId, int actorUserId, string status)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@NewStatus", status, DbType.String, size: 32);
        await conn.ExecuteAsync("sp_UpdateConcertStatus", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<int> CreateVenueAsync(int actorUserId, CreateVenueRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueName", r.VenueName, DbType.String, size: 255);
        p.Add("@Address", r.Address, DbType.String, size: 500);
        p.Add("@NewVenueID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateVenue", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewVenueID");
    }

    public async Task<int> CreateZoneAsync(int actorUserId, int venueId, CreateZoneRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueID", venueId, DbType.Int32);
        p.Add("@ZoneCode", r.ZoneCode, DbType.String, size: 64);
        p.Add("@ZoneName", r.ZoneName, DbType.String, size: 255);
        p.Add("@NewZoneID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateZone", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewZoneID");
    }

    public async Task<int> CreateSeatAsync(int actorUserId, int zoneId, CreateSeatRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ZoneID", zoneId, DbType.Int32);
        p.Add("@SeatCode", r.SeatCode, DbType.String, size: 64);
        p.Add("@SeatLabel", r.SeatLabel, DbType.String, size: 255);
        p.Add("@NewSeatID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateSeat", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewSeatID");
    }

    public async Task<int> ConfigureTicketCategoryAsync(int actorUserId, int concertId, ConfigureTicketCategoryRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@CategoryName", r.CategoryName, DbType.String, size: 255);
        p.Add("@CategoryDescription", r.CategoryDescription, DbType.String, size: 500);
        p.Add("@NewTicketCategoryID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_ConfigureTicketCategory", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewTicketCategoryID");
    }

    public async Task AddEventSeatsAsync(int actorUserId, int concertId, AddEventSeatsRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@TicketCategoryID", r.TicketCategoryId, DbType.Int32);
        p.Add("@SalePrice", r.SalePrice, DbType.Decimal);
        p.Add("@SeatIDs", string.Join(",", r.SeatIds), DbType.String, size: -1);
        await conn.ExecuteAsync("sp_AddEventSeats", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<int> CreatePromotionAsync(int actorUserId, int concertId, CreatePromotionRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@PromotionName", r.PromotionName, DbType.String, size: 255);
        p.Add("@PromotionDescription", r.PromotionDescription, DbType.String, size: 500);
        p.Add("@DiscountType", r.DiscountType, DbType.String, size: 32);
        p.Add("@DiscountValue", r.DiscountValue, DbType.Decimal);
        p.Add("@StartDatetime", r.StartDatetime, DbType.DateTime2);
        p.Add("@EndDatetime", r.EndDatetime, DbType.DateTime2);
        p.Add("@UsageLimit", r.UsageLimit, DbType.Int32);
        p.Add("@CodeRequiredFlag", r.CodeRequiredFlag, DbType.Boolean);
        p.Add("@NewPromotionID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreatePromotion", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewPromotionID");
    }

    public async Task AssignRoleAsync(int actorUserId, AssignRoleRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TargetUserID", r.TargetUserId, DbType.Int32);
        p.Add("@RoleName", r.RoleName, DbType.String, size: 255);
        p.Add("@GrantOrRevoke", r.GrantOrRevoke, DbType.String, size: 10);
        await conn.ExecuteAsync("sp_AssignRole", p, commandType: CommandType.StoredProcedure);
    }

    // ── Admin/Organizer extended management (BP3/BP9/BP12/BP13) ───────────────

    public async Task<int> CreateDiscountCodeAsync(int actorUserId, int promotionId, CreateDiscountCodeRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@PromotionID", promotionId, DbType.Int32);
        p.Add("@CodeValue", r.CodeValue, DbType.String, size: 64);
        p.Add("@ValidFromDatetime", r.ValidFromDatetime, DbType.DateTime2);
        p.Add("@ValidToDatetime", r.ValidToDatetime, DbType.DateTime2);
        p.Add("@NewDiscountCodeID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateDiscountCode", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewDiscountCodeID");
    }

    public async Task SetEventSeatUnavailableAsync(int actorUserId, int eventSeatId, SetEventSeatUnavailableRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@EventSeatID", eventSeatId, DbType.Int32);
        p.Add("@Unavailable", r.Unavailable, DbType.Boolean);
        p.Add("@Reason", r.Reason, DbType.String, size: 500);
        await conn.ExecuteAsync("sp_SetEventSeatUnavailable", p, commandType: CommandType.StoredProcedure);
    }

    public async Task UpdateUserStatusAsync(int actorUserId, int targetUserId, UpdateUserStatusRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TargetUserID", targetUserId, DbType.Int32);
        p.Add("@NewStatus", r.Status, DbType.String, size: 32);
        await conn.ExecuteAsync("sp_AdminUpdateUserStatus", p, commandType: CommandType.StoredProcedure);
    }

    public async Task AddCheckinStaffAssignmentAsync(int actorUserId, AddCheckinStaffAssignmentRequest r)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@StaffUserID", r.StaffUserId, DbType.Int32);
        p.Add("@ConcertIDs", string.Join(",", r.ConcertIds), DbType.String, size: -1);
        await conn.ExecuteAsync("sp_AddCheckinStaffAssignment", p, commandType: CommandType.StoredProcedure);
    }
}