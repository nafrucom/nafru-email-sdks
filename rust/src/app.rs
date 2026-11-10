//! "Nafru ile bağlan": müşterinin Nafru Email hesabına tek tıkla bağlanır, o hesap adına gönderir.

use crate::error::{NafruError, Result};
use crate::http::{Auth, BoxFuture, Http, HttpConfig, Req};
use crate::resources::Emails;
use crate::types::*;
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::fmt::Display;
use std::future::Future;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

/// PKCE (S256): işletim sisteminin CSPRNG'sinden 32 bayt → 43 karakterlik doğrulayıcı ve SHA-256 sınaması. `(verifier, challenge)` döner.
pub fn create_pkce() -> Result<(String, String)> {
    let mut bytes = [0u8; 32];
    getrandom::fill(&mut bytes)
        .map_err(|e| NafruError::network(format!("Güvenli rastgele sayı üretilemedi: {e}")))?;
    let verifier = URL_SAFE_NO_PAD.encode(bytes);
    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
    Ok((verifier, challenge))
}

#[derive(Clone)]
pub(crate) struct Credentials {
    pub client_id: String,
    pub client_secret: String,
}

#[derive(Deserialize)]
struct GrantPayload {
    refresh_token: String,
    connection_id: String,
    scopes: Vec<AppScope>,
}

impl NafruConnect {
    /// Müşteriyi yönlendireceğiniz "Nafru ile bağlan" adresi. `code_verifier`'ı oturumda saklayın; dönüşte `exchange`'e verin.
    /// Dönüşte `state`'i kendi sakladığınız değerle karşılaştırmak sizin sorumluluğunuzdur.
    pub fn authorize_url(&self, input: &AuthorizeUrlInput) -> Result<AuthorizeUrl> {
        if input.state.is_empty() {
            return Err(NafruError::invalid(
                "Nafru SDK: state gerekli (CSRF koruması)",
            ));
        }
        if input.scopes.is_empty() {
            return Err(NafruError::invalid(
                "Nafru SDK: en az bir izin (scopes) gerekli",
            ));
        }
        let (verifier, challenge) = create_pkce()?;
        let mut url =
            url::Url::parse(&format!("{}/connect", self.web_url.trim_end_matches('/')))
                .map_err(|e| NafruError::invalid(format!("Nafru SDK: geçersiz webUrl: {e}")))?;
        {
            let mut params = url.query_pairs_mut();
            params
                .append_pair("client_id", &self.credentials.client_id)
                .append_pair("redirect_uri", &input.redirect_uri)
                .append_pair("state", &input.state)
                .append_pair(
                    "scope",
                    &input
                        .scopes
                        .iter()
                        .map(AppScope::as_str)
                        .collect::<Vec<_>>()
                        .join(" "),
                )
                .append_pair("code_challenge", &challenge)
                .append_pair("code_challenge_method", "S256");
            if let Some(hint) = input.login_hint.as_deref().filter(|h| !h.is_empty()) {
                params.append_pair("login_hint", hint);
            }
        }
        Ok(AuthorizeUrl {
            url: url.into(),
            code_verifier: verifier,
        })
    }

    /// Dönüşteki tek kullanımlık `code`'u bağlantıya çevirir (sunucunuzdan çağırın).
    pub async fn exchange(&self, input: &ExchangeInput) -> Result<ConnectionGrant> {
        let body = json!({
            "grant_type": "authorization_code",
            "client_id": self.credentials.client_id,
            "client_secret": self.credentials.client_secret,
            "code": input.code,
            "code_verifier": input.code_verifier,
            "redirect_uri": input.redirect_uri,
        });
        let grant: GrantPayload = self
            .oauth
            .request(Req::new("POST", "/oauth/token".into()).body(&body))
            .await?;
        Ok(ConnectionGrant {
            connection_id: grant.connection_id,
            refresh_token: grant.refresh_token,
            scopes: grant.scopes,
        })
    }

    /// Bağlantıyı uygulama tarafından iptal eder (müşteri hesabını kapattığında). Belirteçler anında geçersiz olur.
    pub async fn revoke(&self, refresh_token: &str) -> Result<()> {
        let body = json!({
            "client_id": self.credentials.client_id,
            "client_secret": self.credentials.client_secret,
            "token": refresh_token,
        });
        self.oauth
            .request::<Value>(Req::new("POST", "/oauth/revoke".into()).body(&body))
            .await
            .map(|_| ())
    }
}

type RefreshCallback = Arc<
    dyn Fn(ConnectionTokens) -> BoxFuture<'static, std::result::Result<(), String>> + Send + Sync,
>;

/// Saklanan yenileme belirteci ve döndüğünde yenisini KALICI yazan geri çağırma.
#[derive(Clone)]
pub struct ConnectionOptions {
    refresh_token: String,
    on_token_refresh: RefreshCallback,
}

impl ConnectionOptions {
    /// `on_token_refresh` yeni değeri kalıcı yazmadan eskisi geçersizdir; hata dönerse çağrı `token_persist_failed` ile döner.
    pub fn new<F, Fut, E>(refresh_token: impl Into<String>, on_token_refresh: F) -> Self
    where
        F: Fn(ConnectionTokens) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = std::result::Result<(), E>> + Send + 'static,
        E: Display,
    {
        let callback = Arc::new(on_token_refresh);
        Self {
            refresh_token: refresh_token.into(),
            on_token_refresh: Arc::new(move |tokens| {
                let future = callback(tokens);
                Box::pin(async move { future.await.map_err(|e| e.to_string()) })
            }),
        }
    }
}

#[derive(Deserialize)]
struct TokenPayload {
    access_token: String,
    refresh_token: String,
    expires_in: u64,
}

/// Süre dolmadan bu kadar önce yenilenir (saat farkı ve ağ gecikmesi payı).
const EARLY_REFRESH: Duration = Duration::from_secs(30);

struct TokenState {
    refresh_token: String,
    access_token: Option<String>,
    expires_at: Instant,
    /// Yenileme sunucuda başarılı oldu ama yeni yenileme belirteci saklanamadı: eski belirteç artık geçersiz, bu kaybolmamalı.
    unpersisted: bool,
}

/// Bağlantının erişim belirtecini tutar ve yeniler. Eşzamanlı çağrılar TEK yenilemeyi paylaşır (tek uçuş, kilit yenileme boyunca
/// tutulur): dönüşlü yenileme belirteci ikinci bir eşzamanlı yenilemede "yeniden kullanım" sayılır ve bağlantıyı iptal ettirirdi.
pub(crate) struct TokenManager {
    oauth: Http,
    credentials: Credentials,
    on_token_refresh: RefreshCallback,
    state: Mutex<TokenState>,
}

impl TokenManager {
    async fn persist(&self, state: &mut TokenState) -> Result<()> {
        let tokens = ConnectionTokens {
            refresh_token: state.refresh_token.clone(),
        };
        match (self.on_token_refresh)(tokens).await {
            Ok(()) => {
                state.unpersisted = false;
                Ok(())
            }
            Err(cause) => {
                state.unpersisted = true;
                Err(NafruError::new(
                    None,
                    "token_persist_failed",
                    format!("Yeni yenileme belirteci saklanamadı: {cause}"),
                ))
            }
        }
    }

    async fn refresh(&self, state: &mut TokenState) -> Result<String> {
        let body = json!({
            "grant_type": "refresh_token",
            "client_id": self.credentials.client_id,
            "client_secret": self.credentials.client_secret,
            "refresh_token": state.refresh_token,
        });
        let payload: TokenPayload = match self
            .oauth
            .request(Req::new("POST", "/oauth/token".into()).body(&body))
            .await
        {
            Ok(payload) => payload,
            // Geçersiz/tüketilmiş belirteç ya da iptal: kalıcı hata. Ağ ve 5xx geçici hata olarak olduğu gibi döner.
            Err(error)
                if error.name == "invalid_grant"
                    || error.name == "connection_revoked"
                    || (error.status_code == Some(403) && error.name != "rate_limit_exceeded") =>
            {
                return Err(NafruError {
                        name: "connection_revoked".into(),
                        message: "Bağlantı iptal edilmiş ya da yenileme belirteci geçersiz; müşterinin yeniden bağlanması gerekir."
                            .into(),
                        ..error
                    });
            }
            Err(error) => return Err(error),
        };
        state.refresh_token = payload.refresh_token;
        state.access_token = Some(payload.access_token.clone());
        state.expires_at = Instant::now() + Duration::from_secs(payload.expires_in);
        self.persist(state).await?;
        Ok(payload.access_token)
    }

    /// Geçerli erişim belirteci; yoksa ya da dolmak üzereyse tek uçuşla yeniler.
    /// Kutulu dönüş: HTTP isteği → yenileme → OAuth isteği zinciri özyinelemeli future türü kurardı.
    pub fn access_token(&self) -> BoxFuture<'_, Result<String>> {
        Box::pin(async move {
            let mut state = self.state.lock().await;
            if state.unpersisted {
                self.persist(&mut state).await?;
            }
            if let Some(token) = &state.access_token
                && Instant::now() + EARLY_REFRESH < state.expires_at
            {
                return Ok(token.clone());
            }
            self.refresh(&mut state).await
        })
    }

    /// Sunucu 401 `invalid_token` dedi: eldeki belirteci at ve yenile (aynı belirteçle eşzamanlı 401'ler tek yenilemeyi paylaşır).
    pub fn invalidate<'a>(&'a self, stale: &'a str) -> BoxFuture<'a, Result<String>> {
        Box::pin(async move {
            let mut state = self.state.lock().await;
            if state.access_token.as_deref() == Some(stale) {
                state.access_token = None;
            }
            match state.access_token.clone() {
                Some(token) => Ok(token),
                None => self.refresh(&mut state).await,
            }
        })
    }
}

/// Bağlantının e-posta yüzeyi: yalnız `send`, `get`, `list`.
#[derive(Clone)]
pub struct ConnectionEmails(Emails);

impl ConnectionEmails {
    pub async fn send(
        &self,
        input: &SendEmailInput,
        options: SendEmailOptions,
    ) -> Result<SendEmailResponse> {
        self.0.send(input, options).await
    }

    pub async fn get(&self, id: &str) -> Result<Email> {
        self.0.get(id).await
    }

    pub async fn list(&self, query: ListEmailsQuery) -> Result<ListResponse<EmailListItem>> {
        self.0.list(query).await
    }
}

#[derive(Clone)]
pub struct ConnectionSendersResource(Http);

impl ConnectionSendersResource {
    pub async fn list(&self) -> Result<ConnectionSenders> {
        self.0.request(Req::new("GET", "/senders".into())).await
    }
}

#[derive(Clone)]
pub struct ConnectionTemplatesResource(Http);

impl ConnectionTemplatesResource {
    /// Müşterinin yayınlanmış şablonları ile uygulamanın paketi: anahtar başına tek öğe (müşterinin kendi kopyası paketi gölgeler).
    pub async fn list(&self) -> Result<ListResponse<ConnectionTemplate>> {
        self.0.request(Req::new("GET", "/templates".into())).await
    }
}

/// Bir müşteri bağlantısı adına çağrı yapar. Her denemede geçerli erişim belirteci alınır; 401 `invalid_token`
/// (süre dolmuş / yenilenmiş) ise bir kez yenileyip tekrar dener. Yönetim uçları yoktur.
#[derive(Clone)]
pub struct Connection {
    pub id: String,
    http: Http,
    pub senders: ConnectionSendersResource,
    pub templates: ConnectionTemplatesResource,
    pub emails: ConnectionEmails,
}

impl Connection {
    /// `GET /connection`: hazır mı, eksik ne, ücret modu ve müşterinin kurulum adresi.
    pub async fn status(&self) -> Result<ConnectionStatus> {
        self.http
            .request(Req::new("GET", "/connection".into()))
            .await
    }
}

#[derive(Clone, Default)]
pub struct NafruConnectOptions {
    /// Kayıtlı uygulamanın `app_…` kimliği (değişmez).
    pub client_id: String,
    /// Yalnız sunucunuzda; tarayıcıya ve istemci paketine girmez.
    pub client_secret: String,
    /// API'nin kök adresi; boşsa `DEFAULT_BASE_URL`.
    pub base_url: String,
    /// İzin ekranının kök adresi; verilmezse `base_url` sonundaki `/api` atılır.
    pub web_url: Option<String>,
    pub transport: Option<Arc<dyn crate::Transport>>,
    /// Varsayılan 2.
    pub max_retries: Option<u32>,
    /// Varsayılan 30 sn.
    pub timeout: Option<Duration>,
    /// `connection(...).emails.send` için dev çıkış kutusu.
    pub dev_outbox: crate::DevOutbox,
}

/// "Nafru ile bağlan" istemcisi: `authorize_url`, `exchange`, `revoke`, `connection`. Tek alan adı/anahtar için `NafruEmail::new` kullanın.
#[derive(Clone)]
pub struct NafruConnect {
    web_url: String,
    config: Arc<HttpConfig>,
    oauth: Http,
    credentials: Credentials,
    dev_outbox: Option<PathBuf>,
}

impl NafruConnect {
    pub fn new(options: NafruConnectOptions) -> Result<Self> {
        if options.client_id.is_empty() {
            return Err(NafruError::invalid("Nafru SDK: clientId gerekli"));
        }
        if options.client_secret.is_empty() {
            return Err(NafruError::invalid("Nafru SDK: clientSecret gerekli"));
        }
        let base_url = crate::effective_base_url(options.base_url);
        let web_url = options.web_url.clone().unwrap_or_else(|| {
            let trimmed = base_url.trim_end_matches('/');
            trimmed.strip_suffix("/api").unwrap_or(trimmed).to_owned()
        });
        crate::require_https(&base_url, "baseUrl")?;
        crate::require_https(&web_url, "webUrl")?;
        let config = crate::http_config(
            base_url,
            options.transport,
            options.max_retries,
            options.timeout,
        );
        let credentials = Credentials {
            client_id: options.client_id,
            client_secret: options.client_secret,
        };
        // Token uçları kimlik bilgisini gövdede taşır; Authorization başlığı yok.
        let oauth = Http::new(config.clone(), Auth::None);
        Ok(Self {
            web_url,
            config,
            oauth,
            credentials,
            dev_outbox: options.dev_outbox.resolve(),
        })
    }

    /// Saklanan yenileme belirteciyle bir müşteri bağlantısı. Yenileme otomatiktir; yeni belirteç `on_token_refresh` ile gelir.
    pub fn connection(
        &self,
        connection_id: impl Into<String>,
        options: ConnectionOptions,
    ) -> Connection {
        let tokens = TokenManager {
            oauth: self.oauth.clone(),
            credentials: self.credentials.clone(),
            on_token_refresh: options.on_token_refresh,
            state: Mutex::new(TokenState {
                refresh_token: options.refresh_token,
                access_token: None,
                expires_at: Instant::now(),
                unpersisted: false,
            }),
        };
        let http = Http::new(self.config.clone(), Auth::Connection(Arc::new(tokens)));
        Connection {
            id: connection_id.into(),
            senders: ConnectionSendersResource(http.clone()),
            templates: ConnectionTemplatesResource(http.clone()),
            emails: ConnectionEmails(Emails::new(http.clone(), self.dev_outbox.clone())),
            http,
        }
    }
}

redacted_debug!(ConnectionOptions {} secret { refresh_token, on_token_refresh });
redacted_debug!(NafruConnectOptions { client_id, base_url, web_url, max_retries, timeout, dev_outbox } secret { client_secret });

impl std::fmt::Debug for Connection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Connection")
            .field("id", &self.id)
            .field("http", &self.http)
            .finish()
    }
}

impl std::fmt::Debug for NafruConnect {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NafruConnect")
            .field("client_id", &self.credentials.client_id)
            .field("client_secret", &crate::REDACTED)
            .field("web_url", &self.web_url)
            .field("http", &self.oauth)
            .finish()
    }
}
