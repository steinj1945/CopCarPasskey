using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using CopCarPasseyApi.Data;

namespace CopCarPasseyApi.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(AppDbContext db, IConfiguration config) : ControllerBase
{
    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequest req)
    {
        var user = await db.AdminUsers.FirstOrDefaultAsync(u => u.Username == req.Username);
        if (user is null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
            return Unauthorized(new { error = "Invalid credentials" });

        var key   = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config["Jwt:Secret"]!));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(
            claims:  [new Claim(ClaimTypes.Name, user.Username)],
            expires: DateTime.UtcNow.AddHours(8),
            signingCredentials: creds);

        return Ok(new { token = new JwtSecurityTokenHandler().WriteToken(token) });
    }

    public record LoginRequest(string Username, string Password);
}
