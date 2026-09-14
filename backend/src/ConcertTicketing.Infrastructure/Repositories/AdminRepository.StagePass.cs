using System.Data;
using Dapper;
using ConcertTicketing.Application.DTOs;

namespace ConcertTicketing.Infrastructure.Repositories;

// StagePass (docs/stagepass-architecture.md D.2/D.4/D.5): VenueTemplate studio
// (VenueTemplate -> VenueTemplateVersion -> Floor -> Object/Section -> Seat) va
// ConcertMap/ConcertMapRevision (snapshot bat bien + khoa ban). Tang ghi goi
// thang cac SP moi (cung khuon CreateZoneAsync/UpdateZoneAsync o AdminRepository.cs);
// tang doc dung QueryMultipleAsync mot lan roi ghep cay o C#, cung nguyen tac
// "ca nhieu tang trong mot round-trip" da dung cho GetSeatMapAsync.
public partial class AdminRepository
{
    public async Task<IEnumerable<VenueTemplateListItem>> ListVenueTemplatesAsync(int venueId, bool includeArchived)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<VenueTemplateListItem>(@"
            SELECT VenueTemplateID, VenueID, TemplateName, TemplateStatus, CreatedTimestamp, UpdatedTimestamp
            FROM dbo.VenueTemplate
            WHERE VenueID = @VenueID AND (@IncludeArchived = 1 OR TemplateStatus = 'Active')
            ORDER BY TemplateName;",
            new { VenueID = venueId, IncludeArchived = includeArchived });
    }

    public async Task<int> CreateVenueTemplateAsync(int actorUserId, int venueId, CreateVenueTemplateRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueID", venueId, DbType.Int32);
        p.Add("@TemplateName", r.TemplateName, DbType.String, size: 255);
        p.Add("@NewVenueTemplateID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateVenueTemplate", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewVenueTemplateID");
    }

    public async Task UpdateVenueTemplateAsync(int actorUserId, int venueTemplateId, UpdateVenueTemplateRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueTemplateID", venueTemplateId, DbType.Int32);
        p.Add("@TemplateName", r.TemplateName, DbType.String, size: 255);
        p.Add("@TemplateStatus", r.TemplateStatus, DbType.AnsiString, size: 32);
        await conn.ExecuteAsync("sp_UpdateVenueTemplate", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<IEnumerable<VenueTemplateVersionListItem>> ListVenueTemplateVersionsAsync(int venueTemplateId)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<VenueTemplateVersionListItem>(@"
            SELECT VenueTemplateVersionID, VenueTemplateID, VersionNumber, VersionStatus,
                   AuthorUserID, CreatedTimestamp, PublishedTimestamp
            FROM dbo.VenueTemplateVersion
            WHERE VenueTemplateID = @VenueTemplateID
            ORDER BY VersionNumber DESC;",
            new { VenueTemplateID = venueTemplateId });
    }

    public async Task<IEnumerable<ConcertPublishedTemplateVersionItem>> ListPublishedTemplateVersionsForConcertAsync(int actorUserId, int concertId)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<ConcertPublishedTemplateVersionItem>(@"
            SELECT vtv.VenueTemplateVersionID, vt.VenueTemplateID, vt.TemplateName, vtv.VersionNumber
            FROM dbo.Concert c
            JOIN dbo.VenueTemplate vt ON vt.VenueID = c.VenueID AND vt.TemplateStatus = 'Active'
            JOIN dbo.VenueTemplateVersion vtv ON vtv.VenueTemplateID = vt.VenueTemplateID
                                                 AND vtv.VersionStatus = 'Published'
            WHERE c.ConcertID = @ConcertID
              AND (c.OrganizerUserID = @ActorUserID OR EXISTS (
                    SELECT 1 FROM dbo.UserRoleAssignment ura
                    JOIN dbo.Role r ON r.RoleID = ura.RoleID
                    JOIN dbo.UserAccount ua ON ua.UserID = ura.UserID
                    WHERE ura.UserID = @ActorUserID AND ura.AssignmentStatus = 'Active'
                      AND r.RoleName = 'Admin' AND ua.AccountStatus = 'Active'))
            ORDER BY vt.TemplateName, vtv.VersionNumber DESC;",
            new { ActorUserID = actorUserId, ConcertID = concertId });
    }

    public async Task<int> CreateVenueTemplateVersionAsync(int actorUserId, int venueTemplateId, CreateVenueTemplateVersionRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueTemplateID", venueTemplateId, DbType.Int32);
        p.Add("@CopyFromVersionID", r.CopyFromVersionID, DbType.Int32);
        p.Add("@NewVenueTemplateVersionID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateVenueTemplateVersion", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewVenueTemplateVersionID");
    }

    public async Task<VenueTemplateVersionDetail?> GetVenueTemplateVersionDetailAsync(int venueTemplateVersionId)
    {
        using var conn = await _factory.OpenAsync();
        const string sql = @"
            SELECT VenueTemplateVersionID, VenueTemplateID, VersionNumber, VersionStatus,
                   AuthorUserID, CreatedTimestamp, PublishedTimestamp
            FROM dbo.VenueTemplateVersion
            WHERE VenueTemplateVersionID = @VersionID;

            SELECT TemplateFloorID, VenueTemplateVersionID, FloorKey, FloorName, FloorOrder, CanvasWidth, CanvasHeight
            FROM dbo.TemplateFloor
            WHERE VenueTemplateVersionID = @VersionID
            ORDER BY FloorOrder;

            SELECT o.TemplateObjectID, o.TemplateFloorID, o.ObjectType, o.Label, o.GeometryJson, o.ZIndex
            FROM dbo.TemplateObject o
            JOIN dbo.TemplateFloor f ON f.TemplateFloorID = o.TemplateFloorID
            WHERE f.VenueTemplateVersionID = @VersionID;

            SELECT s.TemplateSectionID, s.TemplateFloorID, s.ZoneID, s.SectionKey, s.SectionName, s.GeometryJson
            FROM dbo.TemplateSection s
            JOIN dbo.TemplateFloor f ON f.TemplateFloorID = s.TemplateFloorID
            WHERE f.VenueTemplateVersionID = @VersionID;

            SELECT sv.TemplateSeatID, sv.TemplateSectionID, sv.SeatID, sv.SeatKey, sv.RowLabel, sv.SeatNumber,
                   sv.GeometryJson, sv.IsAccessible, sv.IsCompanion
            FROM dbo.TemplateSeat sv
            JOIN dbo.TemplateSection s ON s.TemplateSectionID = sv.TemplateSectionID
            JOIN dbo.TemplateFloor f ON f.TemplateFloorID = s.TemplateFloorID
            WHERE f.VenueTemplateVersionID = @VersionID;";

        using var grid = await conn.QueryMultipleAsync(sql, new { VersionID = venueTemplateVersionId });

        var version = await grid.ReadSingleOrDefaultAsync<VenueTemplateVersionListItem>();
        if (version is null) return null;

        var floors = (await grid.ReadAsync<TemplateFloorItem>()).ToList();
        var objects = (await grid.ReadAsync<TemplateObjectItem>()).ToList();
        var sections = (await grid.ReadAsync<TemplateSectionItem>()).ToList();
        var seats = (await grid.ReadAsync<TemplateSeatItem>()).ToList();

        var seatsBySection = seats.ToLookup(x => x.TemplateSectionID);
        var sectionsByFloor = sections.ToLookup(x => x.TemplateFloorID);
        var objectsByFloor = objects.ToLookup(x => x.TemplateFloorID);

        var floorDetails = floors.Select(f => new TemplateFloorDetail(
            f.TemplateFloorID, f.FloorKey, f.FloorName, f.FloorOrder, f.CanvasWidth, f.CanvasHeight,
            objectsByFloor[f.TemplateFloorID].ToList(),
            sectionsByFloor[f.TemplateFloorID]
                .Select(s => new TemplateSectionDetail(
                    s.TemplateSectionID, s.ZoneID, s.SectionKey, s.SectionName, s.GeometryJson,
                    seatsBySection[s.TemplateSectionID].ToList()))
                .ToList()))
            .ToList();

        return new VenueTemplateVersionDetail(
            version.VenueTemplateVersionID, version.VenueTemplateID, version.VersionNumber, version.VersionStatus,
            version.CreatedTimestamp, version.PublishedTimestamp, floorDetails);
    }

    public async Task PublishVenueTemplateVersionAsync(int actorUserId, int venueTemplateVersionId)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueTemplateVersionID", venueTemplateVersionId, DbType.Int32);
        await conn.ExecuteAsync("sp_PublishVenueTemplateVersion", p, commandType: CommandType.StoredProcedure);
    }

    public async Task DeleteVenueTemplateVersionDraftAsync(int actorUserId, int venueTemplateVersionId)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueTemplateVersionID", venueTemplateVersionId, DbType.Int32);
        await conn.ExecuteAsync("sp_DeleteVenueTemplateVersionDraft", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<int> ConfigureTemplateFloorAsync(int actorUserId, int venueTemplateVersionId, ConfigureTemplateFloorRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueTemplateVersionID", venueTemplateVersionId, DbType.Int32);
        p.Add("@FloorKey", r.FloorKey, DbType.AnsiString, size: 64);
        p.Add("@FloorName", r.FloorName, DbType.String, size: 255);
        p.Add("@FloorOrder", r.FloorOrder, DbType.Int32);
        p.Add("@CanvasWidth", r.CanvasWidth, DbType.Int32);
        p.Add("@CanvasHeight", r.CanvasHeight, DbType.Int32);
        p.Add("@TemplateFloorID", r.TemplateFloorID, DbType.Int32, direction: ParameterDirection.InputOutput);
        await conn.ExecuteAsync("sp_ConfigureTemplateFloor", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@TemplateFloorID");
    }

    public async Task DeleteTemplateFloorAsync(int actorUserId, int templateFloorId)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TemplateFloorID", templateFloorId, DbType.Int32);
        await conn.ExecuteAsync("sp_DeleteTemplateFloor", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<int> ConfigureTemplateObjectAsync(int actorUserId, int templateFloorId, ConfigureTemplateObjectRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TemplateFloorID", templateFloorId, DbType.Int32);
        p.Add("@ObjectType", r.ObjectType, DbType.AnsiString, size: 32);
        p.Add("@Label", r.Label, DbType.String, size: 255);
        p.Add("@GeometryJson", r.GeometryJson, DbType.String, size: -1);
        p.Add("@ZIndex", r.ZIndex, DbType.Int32);
        p.Add("@TemplateObjectID", r.TemplateObjectID, DbType.Int32, direction: ParameterDirection.InputOutput);
        await conn.ExecuteAsync("sp_ConfigureTemplateObject", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@TemplateObjectID");
    }

    public async Task DeleteTemplateObjectAsync(int actorUserId, int templateObjectId)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TemplateObjectID", templateObjectId, DbType.Int32);
        await conn.ExecuteAsync("sp_DeleteTemplateObject", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<int> ConfigureTemplateSectionAsync(int actorUserId, int templateFloorId, ConfigureTemplateSectionRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TemplateFloorID", templateFloorId, DbType.Int32);
        p.Add("@ZoneID", r.ZoneID, DbType.Int32);
        p.Add("@SectionKey", r.SectionKey, DbType.AnsiString, size: 64);
        p.Add("@SectionName", r.SectionName, DbType.String, size: 255);
        p.Add("@GeometryJson", r.GeometryJson, DbType.String, size: -1);
        p.Add("@TemplateSectionID", r.TemplateSectionID, DbType.Int32, direction: ParameterDirection.InputOutput);
        await conn.ExecuteAsync("sp_ConfigureTemplateSection", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@TemplateSectionID");
    }

    public async Task DeleteTemplateSectionAsync(int actorUserId, int templateSectionId)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TemplateSectionID", templateSectionId, DbType.Int32);
        await conn.ExecuteAsync("sp_DeleteTemplateSection", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<int> ConfigureTemplateSeatAsync(int actorUserId, int templateSectionId, ConfigureTemplateSeatRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TemplateSectionID", templateSectionId, DbType.Int32);
        p.Add("@SeatID", r.SeatID, DbType.Int32);
        p.Add("@SeatKey", r.SeatKey, DbType.AnsiString, size: 64);
        p.Add("@RowLabel", r.RowLabel, DbType.String, size: 16);
        p.Add("@SeatNumber", r.SeatNumber, DbType.Int32);
        p.Add("@GeometryJson", r.GeometryJson, DbType.String, size: -1);
        p.Add("@IsAccessible", r.IsAccessible, DbType.Boolean);
        p.Add("@IsCompanion", r.IsCompanion, DbType.Boolean);
        p.Add("@TemplateSeatID", r.TemplateSeatID, DbType.Int32, direction: ParameterDirection.InputOutput);
        await conn.ExecuteAsync("sp_ConfigureTemplateSeat", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@TemplateSeatID");
    }

    public async Task DeleteTemplateSeatAsync(int actorUserId, int templateSeatId)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TemplateSeatID", templateSeatId, DbType.Int32);
        await conn.ExecuteAsync("sp_DeleteTemplateSeat", p, commandType: CommandType.StoredProcedure);
    }

    // ── ConcertMap / ConcertMapRevision (D.5) ───────────────────────────────

    public async Task<ConcertMapDto?> GetConcertMapAsync(int actorUserId, int concertId)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryFirstOrDefaultAsync<ConcertMapDto>(@"
            SELECT cm.ConcertMapID, cm.ConcertID
            FROM dbo.ConcertMap cm
            JOIN dbo.Concert c ON c.ConcertID = cm.ConcertID
            WHERE cm.ConcertID = @ConcertID
              AND (c.OrganizerUserID = @ActorUserID OR EXISTS (
                    SELECT 1
                    FROM dbo.UserRoleAssignment ura
                    JOIN dbo.Role r ON r.RoleID = ura.RoleID
                    JOIN dbo.UserAccount ua ON ua.UserID = ura.UserID
                    WHERE ura.UserID = @ActorUserID AND ura.AssignmentStatus = 'Active'
                      AND r.RoleName = 'Admin' AND ua.AccountStatus = 'Active'));
            ", new { ActorUserID = actorUserId, ConcertID = concertId });
    }

    public async Task<int> CreateConcertMapAsync(int actorUserId, int concertId)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@NewConcertMapID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateConcertMap", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewConcertMapID");
    }

    public async Task<IEnumerable<ConcertMapRevisionListItem>> ListConcertMapRevisionsAsync(int actorUserId, int concertMapId)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<ConcertMapRevisionListItem>(@"
            SELECT rev.ConcertMapRevisionID, rev.ConcertMapID, rev.SourceVenueTemplateVersionID, rev.RevisionNumber,
                   rev.RevisionStatus, rev.SnapshotTimestamp, rev.LockedTimestamp
            FROM dbo.ConcertMapRevision rev
            JOIN dbo.ConcertMap cm ON cm.ConcertMapID = rev.ConcertMapID
            JOIN dbo.Concert c ON c.ConcertID = cm.ConcertID
            WHERE rev.ConcertMapID = @ConcertMapID
              AND (c.OrganizerUserID = @ActorUserID OR EXISTS (
                    SELECT 1
                    FROM dbo.UserRoleAssignment ura
                    JOIN dbo.Role r ON r.RoleID = ura.RoleID
                    JOIN dbo.UserAccount ua ON ua.UserID = ura.UserID
                    WHERE ura.UserID = @ActorUserID AND ura.AssignmentStatus = 'Active'
                      AND r.RoleName = 'Admin' AND ua.AccountStatus = 'Active'))
            ORDER BY RevisionNumber DESC;",
            new { ActorUserID = actorUserId, ConcertMapID = concertMapId });
    }

    public async Task<int> CreateConcertMapRevisionAsync(int actorUserId, int concertMapId, CreateConcertMapRevisionRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertMapID", concertMapId, DbType.Int32);
        p.Add("@SourceVenueTemplateVersionID", r.SourceVenueTemplateVersionID, DbType.Int32);
        p.Add("@NewConcertMapRevisionID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateConcertMapRevision", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewConcertMapRevisionID");
    }

    public async Task LockConcertMapRevisionAsync(int actorUserId, int concertMapRevisionId)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertMapRevisionID", concertMapRevisionId, DbType.Int32);
        await conn.ExecuteAsync("sp_LockConcertMapRevision", p, commandType: CommandType.StoredProcedure);
    }

    public async Task CancelConcertMapRevisionDraftAsync(int actorUserId, int concertMapRevisionId)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertMapRevisionID", concertMapRevisionId, DbType.Int32);
        await conn.ExecuteAsync("sp_CancelConcertMapRevisionDraft", p, commandType: CommandType.StoredProcedure);
    }

    /// <summary>
    /// Cay Floor -> Section -> Seat cua mot revision, LEFT JOIN EventSeat: ghe
    /// chua dua vao kho ve van xuat hien (EventSeatID/InventoryStatus/Price la
    /// NULL) de Admin thay va chon dua vao kho ve — khac han
    /// GetStagePassSeatMapAsync (khach hang) chi INNER JOIN, chi thay ghe da ban.
    /// </summary>
    public async Task<ConcertMapRevisionDetail?> GetConcertMapRevisionDetailAsync(int actorUserId, int concertMapRevisionId)
    {
        using var conn = await _factory.OpenAsync();
        var canRead = await conn.QueryFirstOrDefaultAsync<int?>(@"
            SELECT TOP (1) 1
            FROM dbo.ConcertMapRevision rev
            JOIN dbo.ConcertMap cm ON cm.ConcertMapID = rev.ConcertMapID
            JOIN dbo.Concert c ON c.ConcertID = cm.ConcertID
            WHERE rev.ConcertMapRevisionID = @RevisionID
              AND (c.OrganizerUserID = @ActorUserID OR EXISTS (
                    SELECT 1
                    FROM dbo.UserRoleAssignment ura
                    JOIN dbo.Role r ON r.RoleID = ura.RoleID
                    JOIN dbo.UserAccount ua ON ua.UserID = ura.UserID
                    WHERE ura.UserID = @ActorUserID AND ura.AssignmentStatus = 'Active'
                      AND r.RoleName = 'Admin' AND ua.AccountStatus = 'Active'));",
            new { ActorUserID = actorUserId, RevisionID = concertMapRevisionId });
        if (canRead is null) return null;

        const string sql = @"
            SELECT ConcertMapRevisionID, ConcertMapID, RevisionNumber, RevisionStatus
            FROM dbo.ConcertMapRevision
            WHERE ConcertMapRevisionID = @RevisionID;

            SELECT ConcertMapRevisionFloorID, FloorKey, FloorName, FloorOrder, CanvasWidth, CanvasHeight
            FROM dbo.ConcertMapRevisionFloor
            WHERE ConcertMapRevisionID = @RevisionID
            ORDER BY FloorOrder;

            SELECT o.ConcertMapRevisionObjectID, o.ConcertMapRevisionFloorID, o.ObjectType, o.Label, o.GeometryJson, o.ZIndex
            FROM dbo.ConcertMapRevisionObject o
            JOIN dbo.ConcertMapRevisionFloor f ON f.ConcertMapRevisionFloorID = o.ConcertMapRevisionFloorID
            WHERE f.ConcertMapRevisionID = @RevisionID;

            SELECT sec.ConcertMapRevisionSectionID, sec.ConcertMapRevisionFloorID, sec.ZoneID, sec.SectionKey, sec.SectionName, sec.GeometryJson
            FROM dbo.ConcertMapRevisionSection sec
            JOIN dbo.ConcertMapRevisionFloor f ON f.ConcertMapRevisionFloorID = sec.ConcertMapRevisionFloorID
            WHERE f.ConcertMapRevisionID = @RevisionID;

            SELECT cs.ConcertMapRevisionSeatID, cs.ConcertMapRevisionSectionID, cs.SeatID, cs.SeatKey, cs.RowLabel, cs.SeatNumber,
                   cs.GeometryJson, cs.IsAccessible, cs.IsCompanion,
                   cs.EventSeatID, es.InventoryStatus, tc.CategoryName, es.SalePrice AS Price
            FROM dbo.ConcertMapRevisionSeat cs
            JOIN dbo.ConcertMapRevisionSection sec ON sec.ConcertMapRevisionSectionID = cs.ConcertMapRevisionSectionID
            JOIN dbo.ConcertMapRevisionFloor f ON f.ConcertMapRevisionFloorID = sec.ConcertMapRevisionFloorID
            LEFT JOIN dbo.EventSeat es ON es.EventSeatID = cs.EventSeatID
            LEFT JOIN dbo.TicketCategory tc ON tc.ConcertID = es.ConcertID AND tc.TicketCategoryID = es.TicketCategoryID
            WHERE f.ConcertMapRevisionID = @RevisionID;";

        using var grid = await conn.QueryMultipleAsync(sql, new { RevisionID = concertMapRevisionId });

        var revision = await grid.ReadSingleOrDefaultAsync<ConcertMapRevisionListItemHead>();
        if (revision is null) return null;

        var floors = (await grid.ReadAsync<CmrFloorRow>()).ToList();
        var objects = (await grid.ReadAsync<ConcertMapRevisionObjectItem>()).ToList();
        var sections = (await grid.ReadAsync<CmrSectionRow>()).ToList();
        var seats = (await grid.ReadAsync<ConcertMapRevisionSeatItem>()).ToList();

        var seatsBySection = seats.ToLookup(x => x.ConcertMapRevisionSectionID);
        var sectionsByFloor = sections.ToLookup(x => x.ConcertMapRevisionFloorID);
        var objectsByFloor = objects.ToLookup(x => x.ConcertMapRevisionFloorID);

        var floorDetails = floors.Select(f => new ConcertMapRevisionFloorDetail(
            f.ConcertMapRevisionFloorID, f.FloorKey, f.FloorName, f.FloorOrder, f.CanvasWidth, f.CanvasHeight,
            objectsByFloor[f.ConcertMapRevisionFloorID].ToList(),
            sectionsByFloor[f.ConcertMapRevisionFloorID]
                .Select(s => new ConcertMapRevisionSectionDetail(
                    s.ConcertMapRevisionSectionID, s.ZoneID, s.SectionKey, s.SectionName, s.GeometryJson,
                    seatsBySection[s.ConcertMapRevisionSectionID].ToList()))
                .ToList()))
            .ToList();

        return new ConcertMapRevisionDetail(
            revision.ConcertMapRevisionID, revision.ConcertMapID, revision.RevisionNumber, revision.RevisionStatus,
            floorDetails);
    }

    public async Task<int> AddEventSeatsFromMapRevisionAsync(int actorUserId, int concertMapRevisionId, AddEventSeatsFromMapRevisionRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertMapRevisionID", concertMapRevisionId, DbType.Int32);
        p.Add("@TicketCategoryID", r.TicketCategoryId, DbType.Int32);
        p.Add("@ConcertMapRevisionSeatIDs", string.Join(",", r.ConcertMapRevisionSeatIds), DbType.String, size: -1);
        await conn.ExecuteAsync("sp_AddEventSeatsFromMapRevision", p, commandType: CommandType.StoredProcedure);
        return r.ConcertMapRevisionSeatIds.Count;
    }

    // Kieu trung gian chi dung cho viec doc cac tap ket qua o GetConcertMapRevisionDetailAsync.
    private sealed class ConcertMapRevisionListItemHead
    {
        public int ConcertMapRevisionID { get; set; }
        public int ConcertMapID { get; set; }
        public int RevisionNumber { get; set; }
        public string RevisionStatus { get; set; } = "";
    }

    private sealed class CmrFloorRow
    {
        public int ConcertMapRevisionFloorID { get; set; }
        public string FloorKey { get; set; } = "";
        public string? FloorName { get; set; }
        public int FloorOrder { get; set; }
        public int CanvasWidth { get; set; }
        public int CanvasHeight { get; set; }
    }

    private sealed class CmrSectionRow
    {
        public int ConcertMapRevisionSectionID { get; set; }
        public int ConcertMapRevisionFloorID { get; set; }
        public int ZoneID { get; set; }
        public string SectionKey { get; set; } = "";
        public string? SectionName { get; set; }
        public string GeometryJson { get; set; } = "";
    }
}
