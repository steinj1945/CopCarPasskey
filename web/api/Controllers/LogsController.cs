using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CopCarPasseyApi.Data;

namespace CopCarPasseyApi.Controllers;

[ApiController]
[Route("api/logs")]
[Authorize]
public class LogsController(AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var total = await db.AuditLogs.CountAsync();
        var items = await db.AuditLogs
            .Include(a => a.PassKey)
            .OrderByDescending(a => a.OccurredAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(a => new {
                a.Id, a.Event, a.OccurredAt, a.DeviceLabel,
                KeyLabel = a.PassKey != null ? a.PassKey.Label : null
            })
            .ToListAsync();

        return Ok(new { total, page, pageSize, items });
    }

    // Arduino posts an event after relay triggers (optional, best-effort)
    [HttpPost]
    [AllowAnonymous]
    public async Task<IActionResult> Post([FromBody] LogEventRequest req)
    {
        db.AuditLogs.Add(new() { Event = req.Event, DeviceLabel = req.DeviceLabel });
        await db.SaveChangesAsync();
        return NoContent();
    }

    public record LogEventRequest(string Event, string? DeviceLabel);
}
