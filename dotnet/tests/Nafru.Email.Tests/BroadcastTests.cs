using System.Text.Json;

namespace Nafru.Email.Tests;

public class BroadcastTests
{
    [Fact]
    public async Task DecodesRecurrenceAndUrlDataSource_UnknownTypeDoesNotCrash()
    {
        // jsonb anahtarları yeniden sıralar: `type` ilk alan olmayabilir.
        const string body = """
            {"object":"broadcast","id":"b1","status":"draft","trigger_state":"active","next_run_at":"2026-11-09T09:00:00Z","parent_id":null,
             "recurrence":{"days":[1,3],"time":"09:00","type":"weekly"},
             "data":{"plan":"pro"},
             "data_source":{"url":"https://x.test/d","type":"url","header_name":"X-Key","has_header_value":true}}
            """;
        var (nafru, _) = Fake.Setup(0, () => new HttpResponseMessage { Content = new StringContent(body) });
        var broadcast = await nafru.Broadcasts.GetAsync("b1");
        var weekly = Assert.IsType<WeeklyRecurrence>(broadcast.Recurrence);
        Assert.Equal(("weekly", "09:00"), (weekly.Type, weekly.Time));
        Assert.Equal([1, 3], weekly.Days);
        var source = Assert.IsType<UrlDataSource>(broadcast.DataSource);
        Assert.Equal(("https://x.test/d", "X-Key", true), (source.Url, source.HeaderName, source.HasHeaderValue));
        Assert.Equal("pro", broadcast.Data!.Value.GetProperty("plan").GetString());
        Assert.Equal(("active", "2026-11-09T09:00:00Z"), (broadcast.TriggerState, broadcast.NextRunAt));
        Assert.Null(broadcast.ParentId);

        var (unknown, _) = Fake.Setup(0, () => new HttpResponseMessage
        {
            Content = new StringContent("""{"id":"b2","recurrence":{"type":"yearly","month":5},"data_source":null}""")
        });
        var future = await unknown.Broadcasts.GetAsync("b2");
        Assert.Equal(typeof(BroadcastRecurrence), future.Recurrence!.GetType());
        Assert.Equal("yearly", future.Recurrence.Type);
        Assert.Null(future.DataSource);
    }

    [Fact]
    public async Task EncodesCreateWithRecurrence_AndUpdateClearsWithNull()
    {
        var (nafru, handler) = Fake.Setup(0, () => Fake.Json(new { @object = "broadcast", id = "b1" }));
        await nafru.Broadcasts.CreateAsync(new CreateBroadcastInput
        {
            SegmentId = "s1",
            From = "a@x.test",
            Recurrence = new MonthlyRecurrence { Day = 1, Time = "08:30" },
            DataSource = new UrlDataSourceInput { Url = "https://x.test/d", HeaderName = "X-Key" },
            Data = new Dictionary<string, object> { ["plan"] = "pro" }
        });
        Assert.Equal(
            """{"segment_id":"s1","from":"a@x.test","data":{"plan":"pro"},"data_source":{"type":"url","url":"https://x.test/d","header_name":"X-Key"},"recurrence":{"type":"monthly","day":1,"time":"08:30"}}""",
            handler.Calls[0].Body);

        await nafru.Broadcasts.UpdateAsync("b1", new UpdateBroadcastInput { Recurrence = null, DataSource = new WebhookDataSourceInput { RegenerateSecret = true } });
        Assert.Equal("""{"data_source":{"type":"webhook","regenerate_secret":true},"recurrence":null}""", handler.Calls[1].Body);

        await nafru.Broadcasts.SendAsync("b1", new SendBroadcastInput { Data = new { week = 45 } });
        Assert.Equal("""{"data":{"week":45}}""", handler.Calls[2].Body);
    }
}
