using Microsoft.EntityFrameworkCore;
using CopCarPasseyApi.Models;

namespace CopCarPasseyApi.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<PassKey>   PassKeys   => Set<PassKey>();
    public DbSet<AuditLog>  AuditLogs  => Set<AuditLog>();
    public DbSet<AdminUser> AdminUsers => Set<AdminUser>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<AuditLog>()
         .HasOne(a => a.PassKey)
         .WithMany(k => k.AuditLogs)
         .HasForeignKey(a => a.PassKeyId)
         .OnDelete(DeleteBehavior.SetNull);
    }
}
