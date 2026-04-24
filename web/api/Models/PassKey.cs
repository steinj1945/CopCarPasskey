namespace CopCarPasseyApi.Models;

public class PassKey
{
    public int Id { get; set; }
    public string Label { get; set; } = string.Empty;       // e.g. "John's iPhone"
    public string SecretHash { get; set; } = string.Empty;  // BCrypt hash of the 256-bit secret
    public string SecretHint { get; set; } = string.Empty;  // last 4 hex chars for identification
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? RevokedAt { get; set; }
    public ICollection<AuditLog> AuditLogs { get; set; } = [];
}
