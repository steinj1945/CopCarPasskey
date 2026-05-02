using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using QRCoder;

namespace CopCarPasseyApi.Controllers;

[ApiController]
[Route("api/qr")]
[Authorize]
public class QrController : ControllerBase
{
    [HttpPost]
    public IActionResult Generate([FromBody] QrRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Text))
            return BadRequest(new { error = "Text is required" });

        using var generator = new QRCodeGenerator();
        using var data = generator.CreateQrCode(request.Text, QRCodeGenerator.ECCLevel.Default);
        var svg = new SvgQRCode(data).GetGraphic(8);

        return Content(svg, "image/svg+xml");
    }

    public record QrRequest(string Text);
}
