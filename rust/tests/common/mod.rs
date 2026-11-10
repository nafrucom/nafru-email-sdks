#![allow(dead_code)]

use nafru_email::{BoxFuture, HttpRequest, HttpResponse, NafruEmail, NafruEmailOptions, Transport};
use serde_json::Value;
use std::sync::{Arc, Mutex};
use std::time::Duration;

type Route = Box<dyn Fn(&HttpRequest) -> Result<HttpResponse, String> + Send + Sync>;

/// Sahte taşıyıcı: `route` her çağrıya yanıt verir; çağrılar kaydedilir. `/oauth/token` yanıtları `token_delay` kadar gecikir.
pub struct Mock {
    pub calls: Mutex<Vec<HttpRequest>>,
    route: Route,
    pub token_delay: Duration,
}

impl Mock {
    pub fn new(
        route: impl Fn(&HttpRequest) -> Result<HttpResponse, String> + Send + Sync + 'static,
    ) -> Arc<Self> {
        Arc::new(Self {
            calls: Mutex::new(Vec::new()),
            route: Box::new(route),
            token_delay: Duration::ZERO,
        })
    }

    pub fn with_delay(
        delay: Duration,
        route: impl Fn(&HttpRequest) -> Result<HttpResponse, String> + Send + Sync + 'static,
    ) -> Arc<Self> {
        Arc::new(Self {
            calls: Mutex::new(Vec::new()),
            route: Box::new(route),
            token_delay: delay,
        })
    }

    /// Yanıtları sırayla verir, son yanıtı tekrarlar.
    pub fn sequence(responses: Vec<Result<HttpResponse, String>>) -> Arc<Self> {
        let index = Mutex::new(0usize);
        Self::new(move |_| {
            let mut i = index.lock().unwrap();
            let response = responses[(*i).min(responses.len() - 1)].clone();
            *i += 1;
            response
        })
    }

    pub fn calls(&self) -> Vec<HttpRequest> {
        self.calls.lock().unwrap().clone()
    }

    pub fn count(&self, path_suffix: &str) -> usize {
        self.calls()
            .iter()
            .filter(|c| c.url.ends_with(path_suffix))
            .count()
    }
}

impl Transport for Mock {
    fn send(&self, request: HttpRequest) -> BoxFuture<'_, Result<HttpResponse, String>> {
        self.calls.lock().unwrap().push(request.clone());
        let response = (self.route)(&request);
        let delay = if request.url.contains("/oauth/token") {
            self.token_delay
        } else {
            Duration::ZERO
        };
        Box::pin(async move {
            tokio::time::sleep(delay).await;
            response
        })
    }
}

pub fn json(status: u16, body: Value) -> Result<HttpResponse, String> {
    json_with(status, body, &[])
}

pub fn json_with(
    status: u16,
    body: Value,
    headers: &[(&str, &str)],
) -> Result<HttpResponse, String> {
    Ok(HttpResponse {
        status,
        status_text: String::new(),
        headers: headers
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect(),
        body: body.to_string(),
    })
}

pub fn client(mock: &Arc<Mock>, max_retries: u32) -> NafruEmail {
    NafruEmail::with_options(NafruEmailOptions {
        transport: Some(mock.clone()),
        max_retries: Some(max_retries),
        dev_outbox: nafru_email::DevOutbox::Off,
        base_url: "https://api.test/".into(),
        api_key: "key_test".into(),
        ..Default::default()
    })
    .unwrap()
}

pub fn body(request: &HttpRequest) -> Value {
    serde_json::from_str(request.body.as_deref().unwrap_or("null")).unwrap()
}
