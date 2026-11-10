package nafruemail

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

// Her kaynak çağrısının yöntem + yol + gövde eşlemesi (sözleşme testi gerçek uygulamaya karşı apps/api'de).
func TestResourceMappings(t *testing.T) {
	cases := []struct {
		name   string
		run    func(c *Client) error
		method string
		url    string
		body   string
	}{
		{"emails.batch", func(c *Client) error {
			_, err := c.Emails.Batch(ctx, []BatchEmailItem{{From: "a@x.test", To: []string{"b@x.test"}, Subject: "s", Text: "t"}})
			return err
		}, "POST", "/emails/batch", `[{"from":"a@x.test","to":["b@x.test"],"subject":"s","text":"t"}]`},
		{"emails.get", func(c *Client) error { _, err := c.Emails.Get(ctx, "e 1"); return err }, "GET", "/emails/e%201", ""},
		{"emails.list", func(c *Client) error {
			_, err := c.Emails.List(ctx, &ListEmailsQuery{ListQuery: ListQuery{Limit: 2}, Status: "sent"})
			return err
		}, "GET", "/emails?limit=2&status=sent", ""},
		{"emails.update", func(c *Client) error {
			_, err := c.Emails.Update(ctx, "e1", &UpdateEmailInput{ScheduledAt: "in 1 hour"})
			return err
		}, "PATCH", "/emails/e1", `{"scheduled_at":"in 1 hour"}`},
		{"emails.cancel", func(c *Client) error { _, err := c.Emails.Cancel(ctx, "e1"); return err }, "POST", "/emails/e1/cancel", ""},
		{"domains.create", func(c *Client) error { _, err := c.Domains.Create(ctx, &CreateDomainInput{Name: "x.test"}); return err },
			"POST", "/domains", `{"name":"x.test"}`},
		{"domains.update null", func(c *Client) error {
			_, err := c.Domains.Update(ctx, "d1", &UpdateDomainInput{TrackingSubdomain: Null[string](), OpenTracking: Ptr(false)})
			return err
		}, "PATCH", "/domains/d1", `{"open_tracking":false,"tracking_subdomain":null}`},
		{"domains.verify", func(c *Client) error { _, err := c.Domains.Verify(ctx, "d1"); return err }, "POST", "/domains/d1/verify", ""},
		{"domains.remove", func(c *Client) error { _, err := c.Domains.Remove(ctx, "d1"); return err }, "DELETE", "/domains/d1", ""},
		{"contacts.get e-posta", func(c *Client) error { _, err := c.Contacts.Get(ctx, "a+b@x.test"); return err },
			"GET", "/contacts/a%2Bb%40x.test", ""},
		{"contacts.update", func(c *Client) error {
			_, err := c.Contacts.Update(ctx, "c1", &UpdateContactInput{Unsubscribed: Ptr(true)})
			return err
		}, "PATCH", "/contacts/c1", `{"unsubscribed":true}`},
		{"contacts.segments.add", func(c *Client) error { _, err := c.Contacts.Segments.Add(ctx, "c1", "s1"); return err },
			"POST", "/contacts/c1/segments/s1", ""},
		{"contacts.segments.remove", func(c *Client) error { _, err := c.Contacts.Segments.Remove(ctx, "c1", "s1"); return err },
			"DELETE", "/contacts/c1/segments/s1", ""},
		{"contacts.topics.list", func(c *Client) error { _, err := c.Contacts.Topics.List(ctx, "c1", nil); return err },
			"GET", "/contacts/c1/topics", ""},
		{"contacts.topics.update çıplak dizi", func(c *Client) error {
			_, err := c.Contacts.Topics.Update(ctx, "c1", &UpdateContactTopicsInput{Topics: []ContactTopicInput{{ID: "t1", Subscription: "opt_in"}}})
			return err
		}, "PATCH", "/contacts/c1/topics", `[{"id":"t1","subscription":"opt_in"}]`},
		{"contactProperties.create", func(c *Client) error {
			_, err := c.ContactProperties.Create(ctx, &CreateContactPropertyInput{Key: "plan", Type: "string"})
			return err
		}, "POST", "/contact-properties", `{"key":"plan","type":"string"}`},
		{"segments.contacts", func(c *Client) error { _, err := c.Segments.Contacts(ctx, "s1", &ListQuery{Limit: 3}); return err },
			"GET", "/segments/s1/contacts?limit=3", ""},
		{"segments.create", func(c *Client) error { _, err := c.Segments.Create(ctx, &CreateSegmentInput{Name: "VIP"}); return err },
			"POST", "/segments", `{"name":"VIP"}`},
		{"topics.create", func(c *Client) error {
			_, err := c.Topics.Create(ctx, &CreateTopicInput{Name: "Haber", DefaultSubscription: "opt_out"})
			return err
		}, "POST", "/topics", `{"name":"Haber","default_subscription":"opt_out"}`},
		{"broadcasts.send", func(c *Client) error {
			_, err := c.Broadcasts.Send(ctx, "b1", &SendBroadcastInput{ScheduledAt: "in 1 hour"})
			return err
		}, "POST", "/broadcasts/b1/send", `{"scheduled_at":"in 1 hour"}`},
		{"broadcasts.cancel", func(c *Client) error { _, err := c.Broadcasts.Cancel(ctx, "b1"); return err }, "POST", "/broadcasts/b1/cancel", ""},
		{"templates.publish", func(c *Client) error { _, err := c.Templates.Publish(ctx, "welcome"); return err },
			"POST", "/templates/welcome/publish", ""},
		{"templates.duplicate", func(c *Client) error { _, err := c.Templates.Duplicate(ctx, "t1"); return err },
			"POST", "/templates/t1/duplicate", ""},
		{"templates.putTranslation", func(c *Client) error {
			_, err := c.Templates.PutTranslation(ctx, "welcome", "pt-BR", &PutTemplateTranslationInput{HTML: "<p>Olá</p>"})
			return err
		}, "PUT", "/templates/welcome/translations/pt-BR", `{"html":"<p>Olá</p>"}`},
		{"templates.removeTranslation", func(c *Client) error { _, err := c.Templates.RemoveTranslation(ctx, "welcome", "de"); return err },
			"DELETE", "/templates/welcome/translations/de", ""},
		{"templates.create brand", func(c *Client) error {
			_, err := c.Templates.Create(ctx, &CreateTemplateInput{Name: "W", HTML: "<p>x</p>",
				Brand: &TemplateBrand{Mode: "custom", Override: &TemplateBrandOverride{ShowHeader: Ptr(false)}}})
			return err
		}, "POST", "/templates", `{"name":"W","html":"<p>x</p>","brand":{"mode":"custom","override":{"show_header":false}}}`},
		{"templates.update brand", func(c *Client) error {
			_, err := c.Templates.Update(ctx, "welcome", &UpdateTemplateInput{Brand: &TemplateBrand{Mode: "inherit"}})
			return err
		}, "PATCH", "/templates/welcome", `{"brand":{"mode":"inherit"}}`},
		{"brand.get", func(c *Client) error { _, err := c.Brand.Get(ctx); return err }, "GET", "/brand", ""},
		{"brand.update", func(c *Client) error {
			_, err := c.Brand.Update(ctx, &UpdateBrandInput{AccentColor: "#112233",
				SocialLinks: []BrandSocialLink{{Network: "x", URL: "https://x.com/acme"}}})
			return err
		}, "PUT", "/brand", `{"accent_color":"#112233","social_links":[{"network":"x","url":"https://x.com/acme"}]}`},
		{"webhooks.create", func(c *Client) error {
			_, err := c.Webhooks.Create(ctx, &CreateWebhookInput{Endpoint: "https://x.test/h", Events: []string{"email.sent"}})
			return err
		}, "POST", "/webhooks", `{"endpoint":"https://x.test/h","events":["email.sent"]}`},
		{"apiKeys.create", func(c *Client) error { _, err := c.APIKeys.Create(ctx, &CreateAPIKeyInput{Name: "ci"}); return err },
			"POST", "/api-keys", `{"name":"ci"}`},
		{"apiKeys.remove", func(c *Client) error { _, err := c.APIKeys.Remove(ctx, "k1"); return err }, "DELETE", "/api-keys/k1", ""},
		{"events.send", func(c *Client) error {
			_, err := c.Events.Send(ctx, &SendEventInput{Name: "signed_up", Contact: EventContact{Email: "a@x.test"}})
			return err
		}, "POST", "/events", `{"name":"signed_up","contact":{"email":"a@x.test"}}`},
		{"events.batch", func(c *Client) error {
			_, err := c.Events.Batch(ctx, []SendEventInput{{Name: "a", Contact: EventContact{ID: "c1"}}})
			return err
		}, "POST", "/events/batch", `[{"name":"a","contact":{"id":"c1"}}]`},
		{"events.list", func(c *Client) error { _, err := c.Events.List(ctx, &ListEventsQuery{Email: "a@x.test"}); return err },
			"GET", "/events?email=a%40x.test", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, server := setup(t, 0, ok(`{"ok":true}`))
			if err := tc.run(client); err != nil {
				t.Fatal(err)
			}
			call := server.snapshot()[0]
			if call.method != tc.method || strings.TrimPrefix(call.url, "https://api.test") != tc.url {
				t.Fatalf("%s %s, beklenen %s %s", call.method, call.url, tc.method, tc.url)
			}
			var want any
			if tc.body != "" {
				_ = json.Unmarshal([]byte(tc.body), &want)
			}
			if got := call.json(t); !reflect.DeepEqual(got, want) {
				t.Fatalf("gövde %s, beklenen %s", call.body, tc.body)
			}
		})
	}
}

func TestEventsIdempotencyKey(t *testing.T) {
	client, server := setup(t, 0, ok(`{"id":"ev1"}`))
	if _, err := client.Events.Send(ctx, &SendEventInput{Name: "a", Contact: EventContact{ID: "c1"}}, SendEventOptions{IdempotencyKey: "abc"}); err != nil {
		t.Fatal(err)
	}
	if got := server.snapshot()[0].header.Get("Idempotency-Key"); got != "abc" {
		t.Fatalf("başlık %q", got)
	}
}

func TestBroadcastRecurrenceAndDataSource(t *testing.T) {
	body := `{"object":"broadcast","id":"b1","name":"Haftalık","status":"draft","from":"a@x.test",
		"recurrence":{"type":"weekly","days":[1,3],"time":"09:30"},"trigger_state":"active",
		"next_run_at":"2026-11-09T09:30:00Z","parent_id":null,"data":{"plan":"pro"},
		"data_source":{"type":"url","url":"https://x.test/d.json","header_name":"X-Key","has_header_value":true}}`
	client, server := setup(t, 0, ok(body))
	broadcast, err := client.Broadcasts.Get(ctx, "b1")
	if err != nil {
		t.Fatal(err)
	}
	want := &BroadcastRecurrence{Type: RecurrenceWeekly, Days: []int{1, 3}, Time: "09:30"}
	if !reflect.DeepEqual(broadcast.Recurrence, want) || *broadcast.TriggerState != "active" || broadcast.ParentID != nil ||
		broadcast.Data["plan"] != "pro" {
		t.Fatalf("yayın %+v", broadcast)
	}
	source := broadcast.DataSource
	if source.Type != DataSourceURL || source.URL != "https://x.test/d.json" || *source.HeaderName != "X-Key" || !source.HasHeaderValue {
		t.Fatalf("veri kaynağı %+v", source)
	}

	// Bilinmeyen tür çözümü bozmaz.
	client, _ = setup(t, 0, ok(`{"recurrence":{"type":"yearly","time":"10:00"},"data_source":{"type":"s3"}}`))
	if b, err := client.Broadcasts.Get(ctx, "b2"); err != nil || b.Recurrence.Type != "yearly" || b.DataSource.Type != "s3" {
		t.Fatalf("bilinmeyen tür: %+v, %v", b, err)
	}

	client, server = setup(t, 0, ok(`{"object":"broadcast","id":"b1"}`))
	_, err = client.Broadcasts.Create(ctx, &CreateBroadcastInput{SegmentID: "s1", From: "a@x.test",
		Recurrence: &BroadcastRecurrence{Type: RecurrenceMonthly, Day: 15, Time: "08:00"},
		DataSource: &BroadcastDataSourceInput{Type: DataSourceWebhook, RegenerateSecret: Ptr(true)}})
	if err != nil {
		t.Fatal(err)
	}
	var got, expected any
	_ = json.Unmarshal([]byte(`{"segment_id":"s1","from":"a@x.test","recurrence":{"type":"monthly","day":15,"time":"08:00"},
		"data_source":{"type":"webhook","regenerate_secret":true}}`), &expected)
	if got = server.snapshot()[0].json(t); !reflect.DeepEqual(got, expected) {
		t.Fatalf("gövde %s", server.snapshot()[0].body)
	}

	client, server = setup(t, 0, ok(`{"object":"broadcast","id":"b1"}`))
	_, err = client.Broadcasts.Update(ctx, "b1", &UpdateBroadcastInput{Recurrence: Null[BroadcastRecurrence](),
		DataSource: Value(BroadcastDataSourceInput{Type: DataSourceURL, URL: "https://x.test", HeaderValue: Null[string]()})})
	if err != nil {
		t.Fatal(err)
	}
	if body := server.snapshot()[0].body; body != `{"data_source":{"type":"url","url":"https://x.test","header_value":null},"recurrence":null}` {
		t.Fatalf("güncelleme gövdesi %s", body)
	}
}
