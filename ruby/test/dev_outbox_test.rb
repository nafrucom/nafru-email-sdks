# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class DevOutboxTest < Minitest::Test
  def test_writes_txt_and_html_instead_of_sending
    Dir.mktmpdir do |dir|
      transport = FakeTransport.new([json_response({ id: "real" })])
      client = NafruEmail.new("k", base_url: "https://api.test", transport: transport, dev_outbox: dir)
      out, = capture_io do
        @data = client.emails.send({ from: "a@x.test", to: %w[b@x.test c@x.test], subject: "Selam",
                                     html: "<p>Merhaba &amp; <b>hoş</b> geldin</p>" })
        @batch = client.emails.batch([{ from: "a@x.test", to: "d@x.test", subject: "S2", text: "düz" }])
      end
      assert_empty transport.calls
      assert_match(/\Adev_[a-z0-9]+\z/, @data[:id])
      assert_equal 1, @batch[:data].size
      txt = Dir[File.join(dir, "*-#{@data[:id]}.txt")].first
      assert txt
      assert_equal "From: a@x.test\nTo: b@x.test, c@x.test\nSubject: Selam\n\nMerhaba & hoş geldin\n", File.read(txt, encoding: "UTF-8")
      assert_equal "<p>Merhaba &amp; <b>hoş</b> geldin</p>", File.read(txt.sub(/\.txt\z/, ".html"), encoding: "UTF-8")
      assert_includes out, "[nafru] dev: e-posta gönderilmedi"
      assert_includes out, txt
      assert_equal 4, Dir[File.join(dir, "*")].size
    end
  end

  def test_default_only_in_development
    previous = ENV.fetch("NODE_ENV", nil)
    ENV["NODE_ENV"] = "development"
    assert_equal ".nafru/emails", Nafru::Email::DevOutbox.resolve(nil)
    assert_equal false, Nafru::Email::DevOutbox.resolve(false)
    ENV["NODE_ENV"] = "production"
    assert_equal false, Nafru::Email::DevOutbox.resolve(nil)
    assert_equal "tmp/mail", Nafru::Email::DevOutbox.resolve("tmp/mail")
  ensure
    ENV["NODE_ENV"] = previous
  end
end
