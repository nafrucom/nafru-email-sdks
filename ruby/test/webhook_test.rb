# frozen_string_literal: true

require_relative "test_helper"

class WebhookTest < Minitest::Test
  VECTOR = JSON.parse(File.read(File.expand_path("../../webhook-test-vector.json", __dir__)), symbolize_names: true)

  def verify(payload: VECTOR[:payload], signature: VECTOR[:signature], timestamp: VECTOR[:timestamp], secret: VECTOR[:secret],
             now: VECTOR[:now_seconds])
    Nafru::Email::Webhook.verify(payload: payload, secret: secret, now: now,
                                 headers: { id: VECTOR[:id], timestamp: timestamp, signature: signature })
  end

  def test_shared_vector
    assert verify
    assert verify(now: Time.at(VECTOR[:now_seconds] + 299))
  end

  def test_tampered_payload_rejected
    refute verify(payload: VECTOR[:payload].sub("em_123", "em_124"))
  end

  def test_one_of_multiple_signatures_is_enough
    assert verify(signature: "v1,AAAA v2,xyz #{VECTOR[:signature]}")
    refute verify(signature: "v1,AAAA v1,!!!")
  end

  def test_stale_or_bad_timestamp_rejected
    refute verify(now: VECTOR[:now_seconds] + 301)
    refute verify(timestamp: "abc")
  end

  def test_bad_secret_raises
    assert_raises(ArgumentError) { verify(secret: "abc") }
    assert_raises(ArgumentError) { verify(secret: "whsec_!!!") }
  end
end

class WebhookTest
  def test_missing_or_empty_headers_return_false
    refute Nafru::Email::Webhook.verify(payload: "{}", headers: {}, secret: VECTOR[:secret])
    refute Nafru::Email::Webhook.verify(payload: "{}", headers: nil, secret: VECTOR[:secret])
    refute verify(signature: "")
    refute verify(timestamp: "")
  end

  def test_future_timestamp_rejected
    refute verify(now: VECTOR[:now_seconds] - 301)
  end

  def test_signatures_after_32_entries_are_ignored
    refute verify(signature: "#{(['v1,AAAA'] * 32).join(' ')} #{VECTOR[:signature]}")
    assert verify(signature: "#{(['v1,AAAA'] * 31).join(' ')} #{VECTOR[:signature]}")
  end
end
