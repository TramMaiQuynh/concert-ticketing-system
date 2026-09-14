using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ConcertTicketing.Application.DTOs;

namespace ConcertTicketing.API.Controllers;

/// <summary>
/// StagePass (docs/stagepass-architecture.md D.2/D.4/D.5): VenueTemplate studio
/// (mặt bằng nhiều tầng, khu dạng đa giác, snapshot bất biến theo Concert).
/// Tách file theo đúng khuôn AdminRepository.Catalog.cs — cùng lớp AdminController,
/// cùng chính sách quyền lớp cha (Admin,Organizer), Floor/Object/Section/Seat thu
/// hẹp lại Admin-only vì đây là hạ tầng địa điểm (cùng lý do Zone/Seat hiện có).
/// </summary>
public partial class AdminController
{
    // ── VenueTemplate ────────────────────────────────────────────────────────

    [HttpGet("venues/{venueId:int}/templates")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(typeof(IEnumerable<VenueTemplateListItem>), StatusCodes.Status200OK)]
    public async Task<IActionResult> ListVenueTemplates(int venueId, [FromQuery] bool includeArchived = false)
        => Ok(await _admin.ListVenueTemplatesAsync(venueId, includeArchived));

    [HttpPost("venues/{venueId:int}/templates")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> CreateVenueTemplate(int venueId, [FromBody] CreateVenueTemplateRequest request)
    {
        var id = await _admin.CreateVenueTemplateAsync(GetActorUserId(), venueId, request);
        return Created($"/api/admin/templates/{id}", new IdResponse(id));
    }

    [HttpPut("templates/{templateId:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> UpdateVenueTemplate(int templateId, [FromBody] UpdateVenueTemplateRequest request)
    {
        await _admin.UpdateVenueTemplateAsync(GetActorUserId(), templateId, request);
        return NoContent();
    }

    // ── VenueTemplateVersion ─────────────────────────────────────────────────

    [HttpGet("templates/{templateId:int}/versions")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(typeof(IEnumerable<VenueTemplateVersionListItem>), StatusCodes.Status200OK)]
    public async Task<IActionResult> ListVenueTemplateVersions(int templateId)
        => Ok(await _admin.ListVenueTemplateVersionsAsync(templateId));

    /// <summary>Published versions for the selected concert's venue, scoped to its owner or an Admin.</summary>
    [HttpGet("concerts/{concertId:int}/published-template-versions")]
    [ProducesResponseType(typeof(IEnumerable<ConcertPublishedTemplateVersionItem>), StatusCodes.Status200OK)]
    public async Task<IActionResult> ListPublishedTemplateVersionsForConcert(int concertId)
        => Ok(await _admin.ListPublishedTemplateVersionsForConcertAsync(GetActorUserId(), concertId));

    [HttpPost("templates/{templateId:int}/versions")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> CreateVenueTemplateVersion(int templateId, [FromBody] CreateVenueTemplateVersionRequest request)
    {
        var id = await _admin.CreateVenueTemplateVersionAsync(GetActorUserId(), templateId, request);
        return Created($"/api/admin/template-versions/{id}", new IdResponse(id));
    }

    /// <summary>Cây hình học đầy đủ (Floor → Object/Section → Seat) của một version — nền cho Studio editor.</summary>
    [HttpGet("template-versions/{versionId:int}")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(typeof(VenueTemplateVersionDetail), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetVenueTemplateVersion(int versionId)
    {
        var detail = await _admin.GetVenueTemplateVersionDetailAsync(versionId);
        return detail is null ? NotFound() : Ok(detail);
    }

    [HttpPost("template-versions/{versionId:int}/publish")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> PublishVenueTemplateVersion(int versionId)
    {
        await _admin.PublishVenueTemplateVersionAsync(GetActorUserId(), versionId);
        return NoContent();
    }

    [HttpDelete("template-versions/{versionId:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> DeleteVenueTemplateVersionDraft(int versionId)
    {
        await _admin.DeleteVenueTemplateVersionDraftAsync(GetActorUserId(), versionId);
        return NoContent();
    }

    // ── TemplateFloor ────────────────────────────────────────────────────────

    [HttpPost("template-versions/{versionId:int}/floors")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> CreateTemplateFloor(int versionId, [FromBody] ConfigureTemplateFloorRequest request)
    {
        var id = await _admin.ConfigureTemplateFloorAsync(GetActorUserId(), versionId, request with { TemplateFloorID = null });
        return Created($"/api/admin/template-floors/{id}", new IdResponse(id));
    }

    // Long ngay duoi version (khong tach rieng "template-floors/{id}") vi
    // sp_ConfigureTemplateFloor BAT BUOC @VenueTemplateVersionID lam tham so o
    // CA HAI nhanh tao/sua (dung de khoa dong Version chong Publish chen ngang,
    // xem sp_ConfigureTemplateFloor.sql) — truyen mot ID gia (vd 0) o day se
    // khien nhanh SUA that bai voi 60049 "khong thuoc version nay". Phat hien
    // luc viet, sua truoc khi test thay vi de test tu bat.
    [HttpPut("template-versions/{versionId:int}/floors/{floorId:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> UpdateTemplateFloor(int versionId, int floorId, [FromBody] ConfigureTemplateFloorRequest request)
    {
        await _admin.ConfigureTemplateFloorAsync(GetActorUserId(), versionId, request with { TemplateFloorID = floorId });
        return NoContent();
    }

    [HttpDelete("template-floors/{floorId:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> DeleteTemplateFloor(int floorId)
    {
        await _admin.DeleteTemplateFloorAsync(GetActorUserId(), floorId);
        return NoContent();
    }

    // ── TemplateObject ───────────────────────────────────────────────────────

    [HttpPost("template-floors/{floorId:int}/objects")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> CreateTemplateObject(int floorId, [FromBody] ConfigureTemplateObjectRequest request)
    {
        var id = await _admin.ConfigureTemplateObjectAsync(GetActorUserId(), floorId, request with { TemplateObjectID = null });
        return Created($"/api/admin/template-objects/{id}", new IdResponse(id));
    }

    // Cung ly do voi UpdateTemplateFloor: sp_ConfigureTemplateObject bat buoc
    // @TemplateFloorID o ca hai nhanh (khoa VenueTemplateVersion qua Floor).
    [HttpPut("template-floors/{floorId:int}/objects/{objectId:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> UpdateTemplateObject(int floorId, int objectId, [FromBody] ConfigureTemplateObjectRequest request)
    {
        await _admin.ConfigureTemplateObjectAsync(GetActorUserId(), floorId, request with { TemplateObjectID = objectId });
        return NoContent();
    }

    [HttpDelete("template-objects/{objectId:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> DeleteTemplateObject(int objectId)
    {
        await _admin.DeleteTemplateObjectAsync(GetActorUserId(), objectId);
        return NoContent();
    }

    // ── TemplateSection ──────────────────────────────────────────────────────

    [HttpPost("template-floors/{floorId:int}/sections")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> CreateTemplateSection(int floorId, [FromBody] ConfigureTemplateSectionRequest request)
    {
        var id = await _admin.ConfigureTemplateSectionAsync(GetActorUserId(), floorId, request with { TemplateSectionID = null });
        return Created($"/api/admin/template-sections/{id}", new IdResponse(id));
    }

    // Cung ly do voi UpdateTemplateFloor: sp_ConfigureTemplateSection bat buoc
    // @TemplateFloorID o ca hai nhanh (khoa VenueTemplateVersion qua Floor,
    // kiem tra va cham Section-vs-Section/Stage cung Floor).
    [HttpPut("template-floors/{floorId:int}/sections/{sectionId:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> UpdateTemplateSection(int floorId, int sectionId, [FromBody] ConfigureTemplateSectionRequest request)
    {
        await _admin.ConfigureTemplateSectionAsync(GetActorUserId(), floorId, request with { TemplateSectionID = sectionId });
        return NoContent();
    }

    [HttpDelete("template-sections/{sectionId:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> DeleteTemplateSection(int sectionId)
    {
        await _admin.DeleteTemplateSectionAsync(GetActorUserId(), sectionId);
        return NoContent();
    }

    // ── TemplateSeat ─────────────────────────────────────────────────────────

    [HttpPost("template-sections/{sectionId:int}/seats")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> CreateTemplateSeat(int sectionId, [FromBody] ConfigureTemplateSeatRequest request)
    {
        var id = await _admin.ConfigureTemplateSeatAsync(GetActorUserId(), sectionId, request with { TemplateSeatID = null });
        return Created($"/api/admin/template-seats/{id}", new IdResponse(id));
    }

    // Cung ly do voi UpdateTemplateFloor: sp_ConfigureTemplateSeat bat buoc
    // @TemplateSectionID o ca hai nhanh (khoa VenueTemplateVersion qua
    // Section -> Floor, kiem tra bat bien SeatID duy nhat trong version).
    [HttpPut("template-sections/{sectionId:int}/seats/{seatId:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> UpdateTemplateSeat(int sectionId, int seatId, [FromBody] ConfigureTemplateSeatRequest request)
    {
        await _admin.ConfigureTemplateSeatAsync(GetActorUserId(), sectionId, request with { TemplateSeatID = seatId });
        return NoContent();
    }

    [HttpDelete("template-seats/{seatId:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> DeleteTemplateSeat(int seatId)
    {
        await _admin.DeleteTemplateSeatAsync(GetActorUserId(), seatId);
        return NoContent();
    }

    // ── ConcertMap / ConcertMapRevision (Admin hoặc Organizer sở hữu Concert — SP tự kiểm tra) ──

    [HttpGet("concerts/{concertId:int}/map")]
    [ProducesResponseType(typeof(ConcertMapDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetConcertMap(int concertId)
    {
        var map = await _admin.GetConcertMapAsync(GetActorUserId(), concertId);
        return map is null ? NotFound() : Ok(map);
    }

    [HttpPost("concerts/{concertId:int}/map")]
    public async Task<IActionResult> CreateConcertMap(int concertId)
    {
        var id = await _admin.CreateConcertMapAsync(GetActorUserId(), concertId);
        return Created($"/api/admin/concert-maps/{id}", new IdResponse(id));
    }

    [HttpGet("concert-maps/{mapId:int}/revisions")]
    [ProducesResponseType(typeof(IEnumerable<ConcertMapRevisionListItem>), StatusCodes.Status200OK)]
    public async Task<IActionResult> ListConcertMapRevisions(int mapId)
        => Ok(await _admin.ListConcertMapRevisionsAsync(GetActorUserId(), mapId));

    [HttpPost("concert-maps/{mapId:int}/revisions")]
    public async Task<IActionResult> CreateConcertMapRevision(int mapId, [FromBody] CreateConcertMapRevisionRequest request)
    {
        var id = await _admin.CreateConcertMapRevisionAsync(GetActorUserId(), mapId, request);
        return Created($"/api/admin/concert-map-revisions/{id}", new IdResponse(id));
    }

    [HttpPost("concert-map-revisions/{revisionId:int}/lock")]
    public async Task<IActionResult> LockConcertMapRevision(int revisionId)
    {
        await _admin.LockConcertMapRevisionAsync(GetActorUserId(), revisionId);
        return NoContent();
    }

    /// <summary>
    /// Huỷ một Draft revision để mở lại Draft khác. Xoá hẳn (không đánh dấu trạng
    /// thái): Draft chưa từng công bố cho ai, và chỉ Revision Locked mới được gắn
    /// EventSeat — nên một Draft luôn sạch, không ai tham chiếu. Xem
    /// sp_CancelConcertMapRevisionDraft.sql.
    /// </summary>
    [HttpDelete("concert-map-revisions/{revisionId:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> CancelConcertMapRevisionDraft(int revisionId)
    {
        await _admin.CancelConcertMapRevisionDraftAsync(GetActorUserId(), revisionId);
        return NoContent();
    }

    /// <summary>Cây Floor→Section→Seat đầy đủ của một revision (kể cả ghế chưa vào kho vé) — nền cho bước "đưa ghế vào kho vé".</summary>
    [HttpGet("concert-map-revisions/{revisionId:int}")]
    [ProducesResponseType(typeof(ConcertMapRevisionDetail), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetConcertMapRevision(int revisionId)
    {
        var detail = await _admin.GetConcertMapRevisionDetailAsync(GetActorUserId(), revisionId);
        return detail is null ? NotFound() : Ok(detail);
    }

    /// <summary>Cầu nối ConcertMapRevisionSeat ↔ EventSeat: đưa ghế đã chọn của một revision Locked vào kho vé bán.</summary>
    [HttpPost("concert-map-revisions/{revisionId:int}/event-seats")]
    public async Task<IActionResult> AddEventSeatsFromMapRevision(int revisionId, [FromBody] AddEventSeatsFromMapRevisionRequest request)
    {
        var count = await _admin.AddEventSeatsFromMapRevisionAsync(GetActorUserId(), revisionId, request);
        return Ok(new { count });
    }
}
