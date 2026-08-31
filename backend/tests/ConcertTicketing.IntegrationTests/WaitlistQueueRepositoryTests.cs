using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using FluentAssertions;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.IntegrationTests;

/// <summary>
/// Integration tests cho WaitlistRepository + QueueRepository (connection API thật):
/// - Waitlist: join thành công, QueuePosition ≥ 1, join lại → 58503, getMyEntry
/// - Concert không bật waitlist → 58502
/// - Queue: join thành công, join lại → 58703, getMyEntry
/// - Concert không bật fair access → 58702
/// </summary>
public sealed class WaitlistQueueRepositoryTests : IClassFixture<DbFixture>
{
    private readonly DbFixture _fx;

    public WaitlistQueueRepositoryTests(DbFixture fx) => _fx = fx;

    private TestDataSeeder NewSeeder() => new(_fx);
    private WaitlistRepository WaitlistRepo() => new(_fx.ApiConnectionString);
    private QueueRepository QueueRepo() => new(_fx.ApiConnectionString);

    private async Task<(int concertId, int customerId)> CreateConcertAsync(bool waitlist, bool fairAccess)
    {
        var s = NewSeeder();
        var organizer = await s.CreateUserAsync("Organizer");
        var customer = await s.CreateUserAsync("Customer");
        var artist = await s.CreateArtistAsync();
        var venue = await s.CreateVenueAsync();
        var concertId = await s.CreateConcertDraftAsync(organizer, artist, venue,
            waitlistEnabled: waitlist, fairAccess: fairAccess);
        return (concertId, customer);
    }

    [Fact(DisplayName = "Waitlist: join → position ≥1; join lặp → 58503; getMyEntry trả đúng")]
    public async Task Waitlist_Join_ThenDuplicateRejected()
    {
        var (concertId, customer) = await CreateConcertAsync(waitlist: true, fairAccess: false);
        var repo = WaitlistRepo();

        var join = await repo.JoinAsync(customer, concertId);
        join.WaitlistEntryId.Should().BeGreaterThan(0);
        join.QueuePosition.Should().BeGreaterThan(0);

        var entry = await repo.GetMyEntryAsync(customer, concertId);
        entry.Should().NotBeNull();
        entry!.WaitlistEntryId.Should().Be(join.WaitlistEntryId);
        entry.EntryStatus.Should().Be("Active");

        var act = () => repo.JoinAsync(customer, concertId);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 58503);
    }

    [Fact(DisplayName = "Waitlist: concert không bật Waitlist → SqlException 58502")]
    public async Task Waitlist_ConcertDisabled_Throws58502()
    {
        var (concertId, customer) = await CreateConcertAsync(waitlist: false, fairAccess: false);

        var act = () => WaitlistRepo().JoinAsync(customer, concertId);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 58502);
    }

    [Fact(DisplayName = "Queue: join → QueueEntryId + Waiting; join lặp → 58703; getMyEntry")]
    public async Task Queue_Join_ThenDuplicateRejected()
    {
        var (concertId, customer) = await CreateConcertAsync(waitlist: false, fairAccess: true);
        var repo = QueueRepo();

        var join = await repo.JoinAsync(customer, concertId);
        join.QueueEntryId.Should().BeGreaterThan(0);
        join.QueueStatus.Should().Be("Waiting");

        var entry = await repo.GetMyEntryAsync(customer, concertId);
        entry.Should().NotBeNull();
        entry!.QueueEntryId.Should().Be(join.QueueEntryId);

        var act = () => repo.JoinAsync(customer, concertId);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 58703);
    }

    [Fact(DisplayName = "Queue: concert không bật Fair Access → SqlException 58702")]
    public async Task Queue_ConcertDisabled_Throws58702()
    {
        var (concertId, customer) = await CreateConcertAsync(waitlist: false, fairAccess: false);

        var act = () => QueueRepo().JoinAsync(customer, concertId);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 58702);
    }
}