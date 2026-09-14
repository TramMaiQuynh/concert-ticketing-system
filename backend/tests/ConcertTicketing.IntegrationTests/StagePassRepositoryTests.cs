using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using FluentAssertions;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.IntegrationTests;

/// <summary>
/// Integration test cho tầng repository StagePass (VenueTemplate studio +
/// ConcertMap, docs/stagepass-architecture.md D.2/D.4/D.5) — vừa mới nối dây
/// C# -> SP hôm nay, CHƯA có bài kiểm nào chạm tới tầng này từ .NET trước đó.
///
/// Cùng lý do UpdateArtist_RetireWorks đã nêu: sai lệch TÊN/KIỂU tham số giữa
/// Dapper DynamicParameters và chữ ký SP chỉ lộ ra khi gọi thật vào DB — với
/// ~20 phương thức repository mới thêm trong một lượt, đây chính xác là rủi
/// ro cao nhất cần test này bắt được. Một test đi CẢ CHUỖI (Template ->
/// Version -> Floor -> Object -> Section -> Seat -> Publish -> Concert ->
/// Map -> Revision -> Lock) chạm mọi tham số của cả 16 SP mới trong một lần.
/// </summary>
public sealed class StagePassRepositoryTests : IClassFixture<DbFixture>
{
    private readonly DbFixture _fx;

    public StagePassRepositoryTests(DbFixture fx) => _fx = fx;

    private TestDataSeeder NewSeeder() => new(_fx);
    private AdminRepository Repo() => new(_fx.ApiFactory);

    [Fact(DisplayName = "StagePass full chain: Template -> Version -> Floor/Object/Section/Seat -> Publish -> ConcertMap -> Revision -> Lock")]
    public async Task FullChain_Works()
    {
        var s = NewSeeder();
        var admin = await s.CreateUserAsync("Admin");
        var organizer = await s.CreateUserAsync("Organizer");
        var venueId = await s.CreateVenueAsync();
        var zoneId = await s.CreateZoneAsync(venueId);
        var seatId = await s.CreateSeatAsync(venueId, zoneId);
        var artistId = await s.CreateArtistAsync();
        var repo = Repo();

        // ── VenueTemplate + VenueTemplateVersion ────────────────────────────
        var templateId = await repo.CreateVenueTemplateAsync(admin, venueId,
            new CreateVenueTemplateRequest($"IT-Template-{s.VenueName}"));

        await repo.UpdateVenueTemplateAsync(admin, templateId,
            new UpdateVenueTemplateRequest(TemplateName: null, TemplateStatus: "Active"));

        var templates = await repo.ListVenueTemplatesAsync(venueId, includeArchived: true);
        templates.Should().ContainSingle(t => t.VenueTemplateID == templateId);

        var versionId = await repo.CreateVenueTemplateVersionAsync(admin, templateId,
            new CreateVenueTemplateVersionRequest(CopyFromVersionID: null));

        var versions = await repo.ListVenueTemplateVersionsAsync(templateId);
        versions.Should().ContainSingle(v => v.VenueTemplateVersionID == versionId && v.VersionStatus == "Draft");

        // ── Floor / Object / Section / Seat ─────────────────────────────────
        var floorId = await repo.ConfigureTemplateFloorAsync(admin, versionId,
            new ConfigureTemplateFloorRequest(null, "ground", "Tầng trệt", 1, 1000, 800));

        var objectId = await repo.ConfigureTemplateObjectAsync(admin, floorId,
            new ConfigureTemplateObjectRequest(null, "Stage", "Sân khấu chính",
                """{"version":1,"shape":"rect","x":300,"y":20,"width":400,"height":60,"rotation":0}"""));

        var sectionId = await repo.ConfigureTemplateSectionAsync(admin, floorId,
            new ConfigureTemplateSectionRequest(null, "VIP", "Khu VIP",
                """{"version":1,"shape":"rect","x":100,"y":150,"width":300,"height":200,"rotation":0}"""));

        var templateSeatId = await repo.ConfigureTemplateSeatAsync(admin, sectionId,
            new ConfigureTemplateSeatRequest(null, seatId, "S1", "A", 1, GeometryJson: null,
                IsAccessible: true, IsCompanion: false));

        // ── Cập nhật lại từng cấp (đi qua đúng route nested để xác nhận tham
        //    số bắt buộc @VenueTemplateVersionID/@TemplateFloorID/@TemplateSectionID
        //    ở nhánh SỬA thật sự hoạt động — đây chính là lỗi đã bắt được lúc
        //    thiết kế controller, trước khi kịp chạy test) ───────────────────
        await repo.ConfigureTemplateFloorAsync(admin, versionId,
            new ConfigureTemplateFloorRequest(floorId, "ground", "Tầng trệt (sửa)", 1, 1200, 900));
        await repo.ConfigureTemplateObjectAsync(admin, floorId,
            new ConfigureTemplateObjectRequest(objectId, "Stage", "Sân khấu (sửa)",
                """{"version":1,"shape":"rect","x":300,"y":20,"width":400,"height":60,"rotation":0}"""));
        await repo.ConfigureTemplateSectionAsync(admin, floorId,
            new ConfigureTemplateSectionRequest(sectionId, "VIP", "Khu VIP (sửa)",
                """{"version":1,"shape":"rect","x":100,"y":150,"width":300,"height":200,"rotation":0}"""));
        await repo.ConfigureTemplateSeatAsync(admin, sectionId,
            new ConfigureTemplateSeatRequest(templateSeatId, seatId, "S1", "A", 1, GeometryJson: null,
                IsAccessible: true, IsCompanion: true));

        var detail = await repo.GetVenueTemplateVersionDetailAsync(versionId);
        detail.Should().NotBeNull();
        detail!.Floors.Should().ContainSingle();
        var floorDetail = detail.Floors.Single();
        floorDetail.FloorName.Should().Be("Tầng trệt (sửa)");
        floorDetail.Objects.Should().ContainSingle();
        floorDetail.Sections.Should().ContainSingle();
        var sectionDetail = floorDetail.Sections.Single();
        sectionDetail.Seats.Should().ContainSingle();
        sectionDetail.Seats.Single().IsCompanion.Should().BeTrue();

        // ── Publish ──────────────────────────────────────────────────────────
        await repo.PublishVenueTemplateVersionAsync(admin, versionId);
        var publishedVersion = (await repo.ListVenueTemplateVersionsAsync(templateId)).Single();
        publishedVersion.VersionStatus.Should().Be("Published");
        publishedVersion.PublishedTimestamp.Should().NotBeNull();

        // ── ConcertMap / ConcertMapRevision ─────────────────────────────────
        var concertId = await s.CreateConcertDraftAsync(organizer, artistId, venueId);

        (await repo.GetConcertMapAsync(concertId)).Should().BeNull();

        var mapId = await repo.CreateConcertMapAsync(organizer, concertId);
        var map = await repo.GetConcertMapAsync(concertId);
        map.Should().NotBeNull();
        map!.ConcertMapID.Should().Be(mapId);

        var revisionId = await repo.CreateConcertMapRevisionAsync(organizer, mapId,
            new CreateConcertMapRevisionRequest(versionId));

        var revisions = await repo.ListConcertMapRevisionsAsync(mapId);
        revisions.Should().ContainSingle(r => r.ConcertMapRevisionID == revisionId && r.RevisionStatus == "Draft");

        // Sao chép sâu phải đúng số lượng: xác nhận qua truy vấn trực tiếp,
        // đúng nguyên tắc đã dùng ở test SQL CreateConcertMapRevision_OK.
        (await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM ConcertMapRevisionSeat sv " +
            "JOIN ConcertMapRevisionSection sc ON sc.ConcertMapRevisionSectionID = sv.ConcertMapRevisionSectionID " +
            "JOIN ConcertMapRevisionFloor f ON f.ConcertMapRevisionFloorID = sc.ConcertMapRevisionFloorID " +
            "WHERE f.ConcertMapRevisionID = @id", new { id = revisionId }))
            .Should().Be(1);

        await repo.LockConcertMapRevisionAsync(organizer, revisionId);
        var lockedRevision = (await repo.ListConcertMapRevisionsAsync(mapId)).Single();
        lockedRevision.RevisionStatus.Should().Be("Locked");
        lockedRevision.LockedTimestamp.Should().NotBeNull();

        // ── Xoá từng phần tử (không phải huỷ nguyên Draft) — phần vừa bổ sung
        //    sau khi soát lại tính thực tế của tầng SP ─────────────────────
        var draftVersionId = await repo.CreateVenueTemplateVersionAsync(admin, templateId,
            new CreateVenueTemplateVersionRequest(CopyFromVersionID: versionId));
        var copiedDetail = await repo.GetVenueTemplateVersionDetailAsync(draftVersionId);
        copiedDetail!.Floors.Should().ContainSingle();
        var copiedFloorId = copiedDetail.Floors.Single().TemplateFloorID;
        var copiedSectionId = copiedDetail.Floors.Single().Sections.Single().TemplateSectionID;
        var copiedSeatId = copiedDetail.Floors.Single().Sections.Single().Seats.Single().TemplateSeatID;

        await repo.DeleteTemplateSeatAsync(admin, copiedSeatId);
        await repo.DeleteTemplateSectionAsync(admin, copiedSectionId);
        await repo.DeleteTemplateFloorAsync(admin, copiedFloorId);
        await repo.DeleteVenueTemplateVersionDraftAsync(admin, draftVersionId);

        (await _fx.QueryAdminAsync<int?>(
            "SELECT VenueTemplateVersionID FROM VenueTemplateVersion WHERE VenueTemplateVersionID = @id",
            new { id = draftVersionId }))
            .Should().BeNull();
    }

    [Fact(DisplayName = "CreateVenueTemplate: Customer (không phải Admin) → 60001")]
    public async Task CreateVenueTemplate_NonAdmin_Throws60001()
    {
        var s = NewSeeder();
        var customer = await s.CreateUserAsync("Customer");
        var venueId = await s.CreateVenueAsync();

        var act = () => Repo().CreateVenueTemplateAsync(customer, venueId, new CreateVenueTemplateRequest("x"));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 60001);
    }

    [Fact(DisplayName = "ConfigureTemplateSection: đa giác lõm → 60086")]
    public async Task ConfigureTemplateSection_ConcavePolygon_Throws60086()
    {
        var s = NewSeeder();
        var admin = await s.CreateUserAsync("Admin");
        var venueId = await s.CreateVenueAsync();
        var repo = Repo();

        var templateId = await repo.CreateVenueTemplateAsync(admin, venueId, new CreateVenueTemplateRequest(s.VenueName));
        var versionId = await repo.CreateVenueTemplateVersionAsync(admin, templateId, new CreateVenueTemplateVersionRequest(null));
        var floorId = await repo.ConfigureTemplateFloorAsync(admin, versionId,
            new ConfigureTemplateFloorRequest(null, "ground", null, 1, 1000, 800));

        var act = () => repo.ConfigureTemplateSectionAsync(admin, floorId,
            new ConfigureTemplateSectionRequest(null, "LShape", null,
                """{"version":1,"shape":"polygon","points":[[0,0],[200,0],[200,100],[100,100],[100,200],[0,200]]}"""));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 60086);
    }
}
