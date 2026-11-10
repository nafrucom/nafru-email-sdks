# frozen_string_literal: true

require_relative "test_helper"

class ResourcesTest < Minitest::Test
  def test_contacts_topics_update_sends_bare_array
    client, transport, = setup_client([json_response({ object: "contact", id: "c1" })])
    topics = [{ id: "t1", subscription: "opt_in" }]
    client.contacts.topics.update("a@b.co", { topics: topics })
    call = transport.calls.first
    assert_equal ["PATCH", "/contacts/a%40b.co/topics"], [call.method, URI(call.url).path]
    assert_equal [{ "id" => "t1", "subscription" => "opt_in" }], call.json
  end

  def test_routes
    client, transport, = setup_client([json_response({})])
    client.contacts.segments.add("c1", "s1")
    client.contacts.segments.remove("c1", "s1")
    client.contact_properties.update("p1", { fallback_value: 1 })
    client.segments.contacts("s1", limit: 2)
    client.broadcasts.send("b1")
    client.broadcasts.cancel("b1")
    client.templates.put_translation("welcome", "pt-BR", { html: "<p/>" })
    client.templates.remove_translation("welcome", "pt-BR")
    client.brand.update({ accent_color: "#ff6600" })
    client.webhooks.remove("w1")
    client.api_keys.create({ name: "k" })
    client.events.batch([{ name: "x", contact: { id: "c1" } }], idempotency_key: "ev-1")
    client.domains.verify("d1")
    client.emails.cancel("e1")
    assert_equal [
      "POST /contacts/c1/segments/s1", "DELETE /contacts/c1/segments/s1", "PATCH /contact-properties/p1",
      "GET /segments/s1/contacts?limit=2", "POST /broadcasts/b1/send", "POST /broadcasts/b1/cancel",
      "PUT /templates/welcome/translations/pt-BR", "DELETE /templates/welcome/translations/pt-BR", "PUT /brand",
      "DELETE /webhooks/w1", "POST /api-keys", "POST /events/batch", "POST /domains/d1/verify", "POST /emails/e1/cancel"
    ], transport.calls.map { |call| "#{call.method} #{call.url.delete_prefix('https://api.test')}" }
    assert_equal({}, transport.calls[4].json)
    assert_equal "ev-1", transport.calls[11].headers["idempotency-key"]
  end

  def test_paginate_follows_after_cursor
    pages = [
      json_response({ object: "list", data: [{ id: "c3" }, { id: "c2" }], has_more: true }),
      json_response({ object: "list", data: [{ id: "c1" }], has_more: false })
    ]
    client, transport, = setup_client(pages)
    ids = Nafru::Email.paginate(client.contacts.method(:list), limit: 2).map { |contact| contact[:id] }
    assert_equal %w[c3 c2 c1], ids
    assert_equal ["https://api.test/contacts?limit=2", "https://api.test/contacts?limit=2&after=c2"], transport.calls.map(&:url)
  end

  def test_paginate_raises_on_error
    client, = setup_client([json_response({ statusCode: 401, name: "unauthorized", message: "yok" }, status: 401)])
    error = assert_raises(Nafru::Email::Error) { Nafru::Email.paginate(client.contacts.method(:list)).to_a }
    assert_equal "unauthorized", error.name
  end
end

class BroadcastRecurrenceTest < Minitest::Test
  def test_decodes_recurrence_and_url_data_source_and_encodes_create
    detail = {
      object: "broadcast", id: "b1", name: "Haftalık", status: "draft", recurrence: { type: "weekly", days: [1, 3], time: "09:30" },
      trigger_state: "active", next_run_at: "2026-11-09T06:30:00.000Z", parent_id: nil, data: { plan: "pro" },
      data_source: { type: "url", url: "https://ornek.com/veri.json", header_name: "x-key", has_header_value: true }
    }
    client, transport, = setup_client([json_response(detail)])
    broadcast = client.broadcasts.get("b1")
    assert_equal({ type: "weekly", days: [1, 3], time: "09:30" }, broadcast[:recurrence])
    assert_equal [true, "x-key"], broadcast[:data_source].values_at(:has_header_value, :header_name)
    assert_equal ["active", nil], broadcast.values_at(:trigger_state, :parent_id)

    client.broadcasts.create({ segment_id: "s1", from: "a@b.co", html: "<p>{{{data.plan}}}</p>",
                               recurrence: { type: "monthly", day: 31, time: "08:00" },
                               data_source: { type: "webhook", regenerate_secret: true } })
    client.broadcasts.update("b1", { recurrence: nil, data: nil })
    client.broadcasts.send("b1", { data: { plan: "pro" } })
    create, update, send = transport.calls.drop(1).map(&:json)
    assert_equal({ "type" => "monthly", "day" => 31, "time" => "08:00" }, create["recurrence"])
    assert_equal({ "type" => "webhook", "regenerate_secret" => true }, create["data_source"])
    assert_equal({ "recurrence" => nil, "data" => nil }, update) # nil açıkça temizler, verilmeyen alan dokunulmaz
    assert_equal({ "data" => { "plan" => "pro" } }, send)
  end

  def test_unknown_recurrence_type_does_not_crash
    client, = setup_client([json_response({ id: "b1", recurrence: { type: "yearly", month: 1 },
                                            data_source: { type: "kafka" } })])
    assert_equal "yearly", client.broadcasts.get("b1")[:recurrence][:type]
  end
end
