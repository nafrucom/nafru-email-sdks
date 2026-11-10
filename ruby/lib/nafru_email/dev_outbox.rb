# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module Nafru
  module Email
    module DevOutbox
      module_function

      # `dev_outbox` verilmezse: yalnız `NODE_ENV=development` iken `.nafru/emails`; aksi hâlde gerçek gönderim.
      def resolve(dev_outbox)
        return dev_outbox unless dev_outbox.nil?

        ENV["NODE_ENV"] == "development" ? ".nafru/emails" : false
      end

      # E-postayı göndermeden `dir` altına `.txt` ve `.html` olarak yazar, yolu ve düz metni konsola basar.
      def write(dir, input)
        email = input.transform_keys(&:to_s)
        now = Time.now.utc
        id = "dev_#{(now.to_f * 1000).to_i.to_s(36)}#{SecureRandom.alphanumeric(6).downcase}"
        base = File.expand_path("#{now.iso8601(3).tr(':.', '--')}-#{id}", dir)
        headers = [
          "From: #{email['from']}",
          "To: #{list(email['to'])}",
          email["cc"] && "Cc: #{list(email['cc'])}",
          email["bcc"] && "Bcc: #{list(email['bcc'])}",
          email["reply_to"] && "Reply-To: #{list(email['reply_to'])}",
          "Subject: #{email['subject']}",
          email["scheduled_at"] && "Scheduled-At: #{email['scheduled_at']}"
        ].compact
        body = body_text(email)
        text = "#{headers.join("\n")}\n\n#{body}\n"
        html = email["html"] || "<pre>#{escape_html(body)}</pre>"

        FileUtils.mkdir_p(File.expand_path(dir))
        File.write("#{base}.txt", text)
        File.write("#{base}.html", html)
        $stdout.puts "[nafru] dev: e-posta gönderilmedi\n  #{base}.txt\n  #{base}.html\n\n#{text}"
        { id: id }
      end

      def list(value) = value.is_a?(Array) ? value.join(", ") : value.to_s

      def escape_html(text) = text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")

      # shortcut: kaba HTML→metin dönüşümü (etiket silme); yalnız dev önizlemesi için, gerçek gönderime girmez.
      def html_to_text(html)
        html.gsub(%r{<(style|script)[\s\S]*?</\1>}i, "")
            .gsub(%r{<br\s*/?>|</(p|div|h[1-6]|li|tr)>}i, "\n")
            .gsub(/<[^>]+>/, "")
            .gsub("&nbsp;", " ").gsub("&lt;", "<").gsub("&gt;", ">").gsub("&quot;", '"').gsub("&amp;", "&")
            .gsub(/\n{3,}/, "\n\n")
            .strip
      end

      def body_text(email)
        return email["text"] if email["text"] && !email["text"].empty?
        return html_to_text(email["html"]) if email["html"] && !email["html"].empty?

        template = email["template"]&.transform_keys(&:to_s)
        return "" unless template

        "[şablon #{template['id']}]\n#{JSON.pretty_generate(template['variables'] || {})}"
      end
    end
  end
end
