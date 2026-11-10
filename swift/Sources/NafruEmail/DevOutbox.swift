import Foundation

/// Dev çıkış kutusu: açıkken `emails.send`/`batch` gönderim yapmaz, e-postayı klasöre `.txt` + `.html` yazar ve yolu konsola basar.
public enum DevOutbox: Sendable, Equatable {
    /// Her zaman gerçek gönderim.
    case disabled
    case directory(String)
}

/// `devOutbox` verilmezse: yalnız `NODE_ENV=development` iken `.nafru/emails`; aksi hâlde gerçek gönderim.
func resolveDevOutbox(_ option: DevOutbox?, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
    switch option {
    case .disabled: return nil
    case .directory(let directory): return directory
    case nil: return environment["NODE_ENV"] == "development" ? ".nafru/emails" : nil
    }
}

private func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}

// shortcut: kaba HTML→metin dönüşümü (etiket silme); yalnız dev önizlemesi için, gerçek gönderime girmez.
private func htmlToText(_ html: String) -> String {
    let rules: [(String, String)] = [
        ("<(style|script)[\\s\\S]*?</\\1>", ""),
        ("<br\\s*/?>|</(p|div|h[1-6]|li|tr)>", "\n"),
        ("<[^>]+>", ""),
        ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&amp;", "&"),
        ("\n{3,}", "\n\n")
    ]
    return rules.reduce(html) {
        $0.replacingOccurrences(of: $1.0, with: $1.1, options: [.regularExpression, .caseInsensitive])
    }.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func bodyText(_ email: SendEmailInput) -> String {
    if let text = email.text, !text.isEmpty { return text }
    if let html = email.html, !html.isEmpty { return htmlToText(html) }
    if let template = email.template {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let variables = (try? encoder.encode(template.variables ?? [:])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "[şablon \(template.id)]\n\(variables)"
    }
    return ""
}

/// E-postayı göndermeden `directory` altına `.txt` ve `.html` olarak yazar, yolu ve düz metni konsola basar; `dev_…` kimliği döner.
func writeDevEmail(_ directory: String, _ email: SendEmailInput) throws -> String {
    let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    let id = "dev_" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String((0..<6).map { _ in alphabet.randomElement()! })
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ".", with: "-")
    let folder = URL(fileURLWithPath: directory).standardizedFileURL
    let base = folder.appendingPathComponent("\(stamp)-\(id)").path

    let list = { (value: [String]?) in (value ?? []).joined(separator: ", ") }
    let headers: [String?] = [
        "From: \(email.from ?? "")",
        "To: \(list(email.to))",
        email.cc.map { "Cc: \(list($0))" },
        email.bcc.map { "Bcc: \(list($0))" },
        email.replyTo.map { "Reply-To: \(list($0))" },
        "Subject: \(email.subject ?? "")",
        email.scheduledAt.map { "Scheduled-At: \($0)" }
    ]
    let body = bodyText(email)
    let text = "\(headers.compactMap { $0 }.joined(separator: "\n"))\n\n\(body)\n"
    let html = email.html ?? "<pre>\(escapeHTML(body))</pre>"

    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(toFile: "\(base).txt", atomically: true, encoding: .utf8)
        try html.write(toFile: "\(base).html", atomically: true, encoding: .utf8)
    } catch {
        throw NafruError.network("Dev çıkış kutusuna yazılamadı: \(error.localizedDescription)")
    }
    print("[nafru] dev: e-posta gönderilmedi\n  \(base).txt\n  \(base).html\n\n\(text)")
    return id
}
