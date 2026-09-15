using System.Net;
using System.Net.Http.Headers;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using ConcertTicketing.API.Controllers;
using ConcertTicketing.Application.Interfaces;
using ConcertTicketing.Infrastructure.Data;
using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using ConcertTicketing.Application.Validators;
using FluentValidation;
using FluentValidation.AspNetCore;
using FluentAssertions;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;

namespace ConcertTicketing.IntegrationTests;

public sealed class AdminCatalogHttpTests(DbFixture fx) : IClassFixture<DbFixture>
{
    [Fact]
    public async Task GetCatalogs_ValidateQueries_EnforceHttpRoles_AndScopeDatabaseRows()
    {
        var seed = new TestDataSeeder(fx);
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(seed);
        var stranger = await seed.CreateUserAsync("Organizer", instance: 9);
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes("catalog-http-test-key-not-used-in-production-2026"));
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.ConfigureKestrel(options => options.Listen(IPAddress.Loopback, 0));
        builder.Services.AddControllers().AddApplicationPart(typeof(AdminController).Assembly);
        builder.Services.AddFluentValidationAutoValidation();
        builder.Services.AddValidatorsFromAssemblyContaining<CreateBookingValidator>();
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddScoped<IDbConnectionFactory>(services => new SqlConnectionFactory(
            fx.ApiConnectionString, services.GetRequiredService<Microsoft.AspNetCore.Http.IHttpContextAccessor>()));
        builder.Services.AddScoped<IAdminRepository, AdminRepository>();
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = false, ValidateAudience = false, ValidateLifetime = true,
                ValidateIssuerSigningKey = true, IssuerSigningKey = key
            });
        builder.Services.AddAuthorization();
        await using var app = builder.Build();
        app.UseAuthentication();
        app.UseAuthorization();
        app.MapControllers();
        await app.StartAsync();
        var address = app.Services.GetRequiredService<IServer>().Features
            .Get<IServerAddressesFeature>()!.Addresses.Single();
        using var client = new HttpClient { BaseAddress = new Uri(address) };

        void SignIn(int userId, string role)
        {
            var token = new JwtSecurityToken(claims: [
                new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
                new Claim(ClaimTypes.Role, role)
            ], expires: DateTime.UtcNow.AddMinutes(5),
                signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
                "Bearer", new JwtSecurityTokenHandler().WriteToken(token));
        }

        foreach (var route in new[] { "concerts", "zones", "seats", "categories", "promotions", "discount-codes", "refunds" })
        {
            client.DefaultRequestHeaders.Authorization = null;
            (await client.GetAsync("/api/admin/" + route)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
            SignIn(baseline.CustomerUserId, "Customer");
            (await client.GetAsync("/api/admin/" + route)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
            SignIn(baseline.OrganizerUserId, "Organizer");
            var response = await client.GetAsync("/api/admin/" + route);
            response.StatusCode.Should().Be(HttpStatusCode.OK, await response.Content.ReadAsStringAsync());
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            json.RootElement.ValueKind.Should().Be(JsonValueKind.Array);
        }
        foreach (var query in new[] { "limit=0", "limit=201", "afterId=-1", "concertId=0", "venueId=-1", "zoneId=0", "promotionId=0" })
            (await client.GetAsync("/api/admin/categories?" + query)).StatusCode.Should().Be(HttpStatusCode.BadRequest);

        var categoryPath = "/api/admin/categories?concertId=" + baseline.ConcertId;
        var ownerJson = await client.GetStringAsync(categoryPath);
        using (var json = JsonDocument.Parse(ownerJson))
        {
            json.RootElement.GetArrayLength().Should().Be(1);
            json.RootElement[0].GetProperty("ticketCategoryID").GetInt32().Should().Be(baseline.CategoryId);
        }
        SignIn(baseline.OrganizerUserId, "Organizer");
        var artistPath = "/api/admin/concerts/" + baseline.ConcertId + "/artists";
        using (var json = JsonDocument.Parse(await client.GetStringAsync(artistPath)))
        {
            json.RootElement.GetArrayLength().Should().Be(1);
            json.RootElement[0].GetProperty("artistID").GetInt32().Should().Be(baseline.ArtistId);
            json.RootElement[0].GetProperty("artistOrder").GetInt32().Should().Be(1);
        }
        SignIn(stranger, "Organizer");
        (await client.GetStringAsync(categoryPath + "&organizerId=" + baseline.OrganizerUserId)).Should().Be("[]");
        (await client.GetStringAsync(artistPath)).Should().Be("[]");
        SignIn(baseline.AdminUserId, "Admin");
        (await client.GetStringAsync(categoryPath)).Should().Be(ownerJson);
        await app.StopAsync();
    }
}
