# frozen_string_literal: true

require_relative "lib/nafru_email/version"

Gem::Specification.new do |spec|
  spec.name = "nafru-email"
  spec.version = Nafru::Email::VERSION
  spec.authors = ["Nafru"]
  spec.summary = "Official Ruby SDK for the Nafru Email API: send transactional email from Ruby"
  spec.description = "Nafru Email Ruby SDK: send transactional and marketing email from Ruby with a Resend-compatible email API. " \
                     "Contacts, broadcasts, templates, custom events, webhook verification and Connect with Nafru (OAuth). " \
                     "No dependencies (net/http, json, openssl)."
  spec.homepage = "https://github.com/nafrucom/nafru-email"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/nafrucom/nafru-email-sdks/tree/main/ruby",
    "bug_tracker_uri" => "https://github.com/nafrucom/nafru-email-sdks/issues",
    "rubygems_mfa_required" => "true"
  }
  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
