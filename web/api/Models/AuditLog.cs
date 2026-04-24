namespace CopCarPasseyApi.Models;

public class AuditLog
{
    public int Id { get; set; }
    public int? PassKeyId { get; set; }
    public PassKey? PassKey { get; set; }
    public string Event { get; set; } = string.Empty;   // "UNLOCK", "DENY", "REVOKE"
    public string? DeviceLabel { get; set; }
    public DateTime OccurredAt { get; set; } = DateTime.UtcNow;
}
