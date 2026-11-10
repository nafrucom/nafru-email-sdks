package com.nafru.email;

import static org.junit.jupiter.api.Assertions.*;

import com.nafru.email.model.Broadcast;
import com.nafru.email.model.BroadcastDataSource;
import com.nafru.email.model.BroadcastDataSourceInput;
import com.nafru.email.model.BroadcastRecurrence;
import com.nafru.email.model.CreateBroadcastInput;
import com.nafru.email.model.UpdateBroadcastInput;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class BroadcastTypesTest {
    @Test
    void decodesRecurrenceAndUrlDataSource() {
        MockTransport mock = MockTransport.sequence(MockTransport.ok(
                "{\"object\":\"broadcast\",\"id\":\"b1\",\"status\":\"draft\","
                        + "\"recurrence\":{\"type\":\"weekly\",\"days\":[1,3],\"time\":\"09:00\"},"
                        + "\"trigger_state\":\"active\",\"next_run_at\":\"2026-11-09T06:00:00Z\",\"parent_id\":null,"
                        + "\"data\":{\"plan\":\"pro\"},"
                        + "\"data_source\":{\"type\":\"url\",\"url\":\"https://x.test/d.json\",\"header_name\":\"X-Key\",\"has_header_value\":true}}"));
        Broadcast broadcast = mock.client(0).broadcasts().get("b1");
        assertEquals(new BroadcastRecurrence.Weekly(List.of(1, 3), "09:00"), broadcast.recurrence());
        assertEquals("active", broadcast.triggerState());
        assertEquals("2026-11-09T06:00:00Z", broadcast.nextRunAt());
        assertNull(broadcast.parentId());
        assertEquals(Map.of("plan", "pro"), broadcast.data());
        assertEquals(new BroadcastDataSource.Url("https://x.test/d.json", "X-Key", true), broadcast.dataSource());
    }

    @Test
    void unknownTypesDoNotBreakDecoding() {
        MockTransport mock = MockTransport.sequence(MockTransport.ok(
                "{\"id\":\"b1\",\"recurrence\":{\"type\":\"yearly\",\"month\":3},\"data_source\":{\"type\":\"s3\"}}"));
        Broadcast broadcast = mock.client(0).broadcasts().get("b1");
        assertInstanceOf(BroadcastRecurrence.Unknown.class, broadcast.recurrence());
        assertInstanceOf(BroadcastDataSource.Unknown.class, broadcast.dataSource());
    }

    @Test
    void encodesCreateWithRecurrenceAndClearsInUpdate() {
        MockTransport mock = MockTransport.sequence(MockTransport.ok("{\"object\":\"broadcast\",\"id\":\"b1\"}"));
        NafruEmail nafru = mock.client(0);
        nafru.broadcasts().create(new CreateBroadcastInput("s1", "a@x.test")
                .recurrence(new BroadcastRecurrence.Interval(7, "08:30"))
                .dataSource(BroadcastDataSourceInput.url("https://x.test/d.json").headerName("X-Key").headerValue(null)));
        assertEquals("{\"segment_id\":\"s1\",\"from\":\"a@x.test\",\"recurrence\":{\"type\":\"interval\",\"every_days\":7,"
                        + "\"time\":\"08:30\"},\"data_source\":{\"type\":\"url\",\"url\":\"https://x.test/d.json\","
                        + "\"header_name\":\"X-Key\",\"header_value\":null}}",
                mock.calls.get(0).body());
        nafru.broadcasts().update("b1", new UpdateBroadcastInput().recurrence(null).data(null));
        assertEquals("{\"recurrence\":null,\"data\":null}", mock.calls.get(1).body());
    }
}
