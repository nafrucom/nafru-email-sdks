# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "nafru_email"
require "minitest/autorun"
require "json"

# Sahte taşıyıcı: yanıtları sırayla verir, son yanıtı tekrarlar (ya da bloğa sorar); çağrıları kaydeder.
class FakeTransport
  Call = Struct.new(:method, :url, :headers, :body, keyword_init: true) do
    def json = body && JSON.parse(body)
    def path = URI(url).path
  end

  attr_reader :calls

  def initialize(responses = [], &route)
    @responses = responses
    @route = route
    @calls = []
    @lock = Mutex.new
  end

  def call(method:, url:, headers:, body:, timeout:) # rubocop:disable Lint/UnusedMethodArgument
    call = Call.new(method: method, url: url, headers: headers, body: body)
    next_response = @lock.synchronize do
      @calls << call
      @route ? nil : @responses[[@calls.size - 1, @responses.size - 1].min]
    end
    next_response = @route.call(call) if @route
    next_response.respond_to?(:call) ? next_response.call : next_response
  end
end

def json_response(body, status: 200, headers: {})
  Nafru::Email::Response.new(status: status, headers: { "content-type" => "application/json" }.merge(headers),
                             body: JSON.generate(body))
end

def setup_client(responses, max_retries: 0)
  transport = FakeTransport.new(responses)
  client = NafruEmail.new("key_test", base_url: "https://api.test/", transport: transport,
                                    max_retries: max_retries, dev_outbox: false)
  waits = []
  client.instance_variable_get(:@http).define_singleton_method(:pause) { |seconds| waits << seconds }
  [client, transport, waits]
end
