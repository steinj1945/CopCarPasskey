using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CopCarPasseyApi.Data;
using CopCarPasseyApi.Services;

namespace CopCarPasseyApi.Controllers;

[ApiController]
[Route("api/keys")]
[Authorize]
public class KeysController(AppDbContext db, PassKeyService svc) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List() =>
        Ok(await db.PassKeys
            .OrderByDescending(k => k.CreatedAt)
            .Select(k => new {
                k.Id, k.Label, k.IsActive, k.CreatedAt, k.RevokedAt, k.SecretHint
            })
            .ToListAsync());

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateKeyRequest req)
    {
        var (key, secret) = await svc.CreateAsync(req.Label);
        // Return the plain secret once — it is never stored in plaintext
        return CreatedAtAction(nameof(List), new {
            key.Id, key.Label, key.SecretHint,
            secret   // caller must store this / show as QR
        });
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Revoke(int id)
    {
        if (!await svc.RevokeAsync(id)) return NotFound();
        db.AuditLogs.Add(new() { PassKeyId = id, Event = "REVOKE" });
        await db.SaveChangesAsync();
        return NoContent();
    }

    public record CreateKeyRequest(string Label);
}
