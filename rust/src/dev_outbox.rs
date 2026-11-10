use crate::error::{NafruError, Result};
use crate::types::{BatchEmailItem, EmailTemplate, SendEmailInput, SendEmailResponse};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

/// Dev çıkış kutusu: açıkken `emails.send`/`batch` gönderim yapmaz, e-postayı klasöre `.txt` + `.html` yazar ve yolu konsola basar.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub enum DevOutbox {
    /// `NODE_ENV=development` iken `.nafru/emails`, aksi hâlde kapalı.
    #[default]
    Auto,
    Dir(PathBuf),
    /// Her zaman gerçek gönderim.
    Off,
}

impl DevOutbox {
    pub(crate) fn resolve(&self) -> Option<PathBuf> {
        resolve_with(self, std::env::var("NODE_ENV").ok().as_deref())
    }
}

fn resolve_with(outbox: &DevOutbox, node_env: Option<&str>) -> Option<PathBuf> {
    match outbox {
        DevOutbox::Auto => {
            (node_env == Some("development")).then(|| PathBuf::from(".nafru/emails"))
        }
        DevOutbox::Dir(dir) => Some(dir.clone()),
        DevOutbox::Off => None,
    }
}

pub(crate) struct DevEmail<'a> {
    from: Option<&'a str>,
    to: &'a [String],
    cc: Option<&'a [String]>,
    bcc: Option<&'a [String]>,
    reply_to: Option<&'a [String]>,
    subject: Option<&'a str>,
    scheduled_at: Option<&'a str>,
    html: Option<&'a str>,
    text: Option<&'a str>,
    template: Option<&'a EmailTemplate>,
}

impl<'a> From<&'a SendEmailInput> for DevEmail<'a> {
    fn from(e: &'a SendEmailInput) -> Self {
        Self {
            from: e.from.as_deref(),
            to: &e.to,
            cc: e.cc.as_deref(),
            bcc: e.bcc.as_deref(),
            reply_to: e.reply_to.as_deref(),
            subject: e.subject.as_deref(),
            scheduled_at: e.scheduled_at.as_deref(),
            html: e.html.as_deref(),
            text: e.text.as_deref(),
            template: e.template.as_ref(),
        }
    }
}

impl<'a> From<&'a BatchEmailItem> for DevEmail<'a> {
    fn from(e: &'a BatchEmailItem) -> Self {
        Self {
            from: Some(&e.from),
            to: &e.to,
            cc: e.cc.as_deref(),
            bcc: e.bcc.as_deref(),
            reply_to: e.reply_to.as_deref(),
            subject: Some(&e.subject),
            scheduled_at: e.scheduled_at.as_deref(),
            html: e.html.as_deref(),
            text: e.text.as_deref(),
            template: None,
        }
    }
}

fn escape_html(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

// shortcut: kaba HTML→metin dönüşümü (etiket silme); yalnız dev önizlemesi için, gerçek gönderime girmez.
fn html_to_text(html: &str) -> String {
    // ASCII küçültme bayt konumlarını korur; dilimler iki metinde aynı yere düşer.
    let lower = html.to_ascii_lowercase();
    let mut out = String::new();
    let mut i = 0;
    while i < html.len() {
        if html.as_bytes()[i] == b'<'
            && let Some(end) = html[i..].find('>')
        {
            let tag = &lower[i + 1..i + end];
            let closing = tag.starts_with('/');
            let name: String = tag
                .trim_start_matches('/')
                .chars()
                .take_while(char::is_ascii_alphanumeric)
                .collect();
            if !closing
                && (name == "style" || name == "script")
                && let Some(close) = lower[i..].find(&format!("</{name}>"))
            {
                i += close + name.len() + 3;
                continue;
            }
            let heading = name.len() == 2
                && name.starts_with('h')
                && (b'1'..=b'6').contains(&name.as_bytes()[1]);
            if name == "br"
                || (closing && (heading || matches!(name.as_str(), "p" | "div" | "li" | "tr")))
            {
                out.push('\n');
            }
            i += end + 1;
            continue;
        }
        let ch = html[i..].chars().next().unwrap_or_default();
        out.push(ch);
        i += ch.len_utf8();
    }
    let mut text = out
        .replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&amp;", "&");
    while text.contains("\n\n\n") {
        text = text.replace("\n\n\n", "\n\n");
    }
    text.trim().to_owned()
}

fn body_text(email: &DevEmail) -> String {
    if let Some(text) = email.text.filter(|t| !t.is_empty()) {
        return text.to_owned();
    }
    if let Some(html) = email.html.filter(|h| !h.is_empty()) {
        return html_to_text(html);
    }
    if let Some(template) = email.template {
        let variables =
            serde_json::to_string_pretty(&template.variables.clone().unwrap_or_default())
                .unwrap_or_default();
        return format!("[şablon {}]\n{variables}", template.id);
    }
    String::new()
}

fn base36(mut n: u128) -> String {
    const DIGITS: &[u8] = b"0123456789abcdefghijklmnopqrstuvwxyz";
    let mut out = Vec::new();
    loop {
        out.push(DIGITS[(n % 36) as usize]);
        n /= 36;
        if n == 0 {
            break;
        }
    }
    out.reverse();
    String::from_utf8(out).unwrap_or_default()
}

/// `2026-01-01T00-00-00-000Z` (ISO 8601, dosya adına uygun).
fn file_timestamp(millis: u128) -> String {
    let secs = (millis / 1000) as i64;
    let (days, rem) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    // Hinnant'ın civil_from_days algoritması.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}-{:02}-{:02}-{:03}Z",
        rem / 3600,
        rem % 3600 / 60,
        rem % 60,
        millis % 1000
    )
}

/// E-postayı göndermeden `dir` altına `.txt` ve `.html` olarak yazar, yolu ve düz metni konsola basar.
pub(crate) fn write_dev_email(dir: &Path, email: &DevEmail) -> Result<SendEmailResponse> {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default();
    let random: String = base36(u128::from(getrandom::u64().map_err(|e| {
        NafruError::network(format!("Güvenli rastgele sayı üretilemedi: {e}"))
    })?))
    .chars()
    .take(6)
    .collect();
    let id = format!("dev_{}{random}", base36(millis));
    let dir = std::path::absolute(dir).unwrap_or_else(|_| dir.to_path_buf());
    let base = dir.join(format!("{}-{id}", file_timestamp(millis)));

    let join = |list: &[String]| list.join(", ");
    let mut headers = vec![
        format!("From: {}", email.from.unwrap_or_default()),
        format!("To: {}", join(email.to)),
    ];
    if let Some(cc) = email.cc {
        headers.push(format!("Cc: {}", join(cc)));
    }
    if let Some(bcc) = email.bcc {
        headers.push(format!("Bcc: {}", join(bcc)));
    }
    if let Some(reply_to) = email.reply_to {
        headers.push(format!("Reply-To: {}", join(reply_to)));
    }
    headers.push(format!("Subject: {}", email.subject.unwrap_or_default()));
    if let Some(at) = email.scheduled_at {
        headers.push(format!("Scheduled-At: {at}"));
    }
    let body = body_text(email);
    let text = format!("{}\n\n{body}\n", headers.join("\n"));
    let html = email.html.map_or_else(
        || format!("<pre>{}</pre>", escape_html(&body)),
        str::to_owned,
    );

    let (txt_path, html_path) = (base.with_extension("txt"), base.with_extension("html"));
    let write = || -> std::io::Result<()> {
        std::fs::create_dir_all(&dir)?;
        std::fs::write(&txt_path, &text)?;
        std::fs::write(&html_path, &html)
    };
    write().map_err(|e| NafruError::network(format!("Dev çıkış kutusuna yazılamadı: {e}")))?;
    println!(
        "[nafru] dev: e-posta gönderilmedi\n  {}\n  {}\n\n{text}",
        txt_path.display(),
        html_path.display()
    );
    Ok(SendEmailResponse { id })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_only_in_development() {
        assert_eq!(
            resolve_with(&DevOutbox::Auto, Some("development")),
            Some(PathBuf::from(".nafru/emails"))
        );
        assert_eq!(resolve_with(&DevOutbox::Off, Some("development")), None);
        assert_eq!(resolve_with(&DevOutbox::Auto, Some("production")), None);
        assert_eq!(resolve_with(&DevOutbox::Auto, None), None);
    }

    #[test]
    fn html_to_text_strips_tags() {
        let html = "<style>p{}</style><p>Selam <b>Ali</b></p><p>&amp; hoş geldin</p><br/>x";
        assert_eq!(html_to_text(html), "Selam Ali\n& hoş geldin\n\nx");
    }

    #[test]
    fn timestamp_is_iso() {
        assert_eq!(
            file_timestamp(1_767_225_600_123),
            "2026-01-01T00-00-00-123Z"
        );
    }
}
