using System.Security.Cryptography;
using CopCarPasseyApi.Data;
using CopCarPasseyApi.Models;

namespace CopCarPasseyApi.Services;

public class PassKeyService(AppDbContext db)
{
    // Generate a new 256-bit secret, return it as hex (only time it's ever in plaintext).
    public async Task<(PassKey key, string plainSecret)> CreateAsync(string label)
    {
        var secret = RandomNumberGenerator.GetBytes(32);
        var hex    = Convert.ToHexString(secret).ToLower();

        var key = new PassKey
        {
            Label      = label,
            SecretHash = BCrypt.Net.BCrypt.HashPassword(hex),
            SecretHint = hex[^4..]
        };

        db.PassKeys.Add(key);
        await db.SaveChangesAsync();
        return (key, hex);
    }

    public async Task<bool> RevokeAsync(int id)
    {
        var key = await db.PassKeys.FindAsync(id);
        if (key is null) return false;
        key.IsActive  = false;
        key.RevokedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return true;
    }

    // Called by the Arduino (or a proxy) to validate a submitted secret.
    public async Task<bool> ValidateAsync(string plainSecret, string? deviceLabel)
    {
        var active = db.PassKeys.Where(k => k.IsActive);
        foreach (var key in active)
        {
            if (BCrypt.Net.BCrypt.Verify(plainSecret, key.SecretHash))
            {
                db.AuditLogs.Add(new AuditLog
                {
                    PassKeyId   = key.Id,
                    Event       = "UNLOCK",
                    DeviceLabel = deviceLabel
                });
                await db.SaveChangesAsync();
                return true;
            }
        }
        db.AuditLogs.Add(new AuditLog { Event = "DENY", DeviceLabel = deviceLabel });
        await db.SaveChangesAsync();
        return false;
    }
}
