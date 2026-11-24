use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use bytes::Bytes;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue, USER_AGENT};
use reqwest::{Client, Method, Proxy, Response};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum TlsClientError {
    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),
    #[error("Invalid proxy URL: {0}")]
    InvalidProxy(String),
    #[error("Invalid header: {0}")]
    InvalidHeader(String),
}

/// Network modes aligned with Dart `NetworkMode`
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum NetworkMode {
    Direct,
    ProxyRecommended,
    ProxyRequired,
}

/// Proxy configuration for routing
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProxyConfig {
    pub default_proxy: Option<String>,
    pub site_proxies: HashMap<String, String>,
}

/// Stealth TLS Client Engine with browser fingerprint simulation
#[derive(Clone)]
pub struct StealthTlsClient {
    default_client: Client,
    proxy_clients: Arc<parking_lot::RwLock<HashMap<String, Client>>>,
    config: Arc<parking_lot::RwLock<ProxyConfig>>,
}

impl StealthTlsClient {
    pub fn new(config: ProxyConfig) -> Result<Self, TlsClientError> {
        let default_client = Self::build_client(None)?;
        let proxy_clients = Arc::new(parking_lot::RwLock::new(HashMap::new()));
        
        let client = Self {
            default_client,
            proxy_clients,
            config: Arc::new(parking_lot::RwLock::new(config)),
        };

        Ok(client)
    }

    fn build_client(proxy_url: Option<&str>) -> Result<Client, TlsClientError> {
        let mut builder = Client::builder()
            .timeout(Duration::from_secs(30))
            .connect_timeout(Duration::from_secs(10))
            .tcp_keepalive(Duration::from_secs(60))
            .pool_idle_timeout(Duration::from_secs(90))
            .pool_max_idle_per_host(10);

        if let Some(proxy_str) = proxy_url {
            if !proxy_str.is_empty() {
                let proxy = if proxy_str.starts_with("socks5://") || proxy_str.starts_with("socks5h://") {
                    Proxy::all(proxy_str).map_err(|e| TlsClientError::InvalidProxy(e.to_string()))?
                } else if proxy_str.starts_with("http://") || proxy_str.starts_with("https://") {
                    Proxy::all(proxy_str).map_err(|e| TlsClientError::InvalidProxy(e.to_string()))?
                } else {
                    Proxy::all(format!("http://{}", proxy_str))
                        .map_err(|e| TlsClientError::InvalidProxy(e.to_string()))?
                };
                builder = builder.proxy(proxy);
            }
        }

        // Modern Chrome/Windows JA3-aligned headers
        let mut default_headers = HeaderMap::new();
        default_headers.insert(
            USER_AGENT,
            HeaderValue::from_static(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            ),
        );
        default_headers.insert(
            HeaderName::from_static("sec-ch-ua"),
            HeaderValue::from_static("\"Google Chrome\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\""),
        );
        default_headers.insert(
            HeaderName::from_static("sec-ch-ua-mobile"),
            HeaderValue::from_static("?0"),
        );
        default_headers.insert(
            HeaderName::from_static("sec-ch-ua-platform"),
            HeaderValue::from_static("\"Windows\""),
        );
        default_headers.insert(
            HeaderName::from_static("accept-language"),
            HeaderValue::from_static("zh-CN,zh;q=0.9,en;q=0.8,ja;q=0.7"),
        );

        builder = builder.default_headers(default_headers);

        let client = builder.build()?;
        Ok(client)
    }

    pub fn get_client_for_site(&self, site: &str, mode: NetworkMode) -> Client {
        let config = self.config.read();
        
        let proxy_target = match mode {
            NetworkMode::Direct => None,
            NetworkMode::ProxyRecommended | NetworkMode::ProxyRequired => {
                config.site_proxies.get(site).or(config.default_proxy.as_ref())
            }
        };

        match proxy_target {
            Some(proxy_url) if !proxy_url.is_empty() => {
                let mut map = self.proxy_clients.write();
                if let Some(existing) = map.get(proxy_url) {
                    existing.clone()
                } else if let Ok(new_client) = Self::build_client(Some(proxy_url)) {
                    map.insert(proxy_url.to_string(), new_client.clone());
                    new_client
                } else {
                    self.default_client.clone()
                }
            }
            _ => self.default_client.clone(),
        }
    }

    pub async fn fetch_stream(
        &self,
        url: &str,
        headers: &HashMap<String, String>,
        site: &str,
        mode: NetworkMode,
    ) -> Result<Response, TlsClientError> {
        let client = self.get_client_for_site(site, mode);
        let mut req = client.get(url);

        for (k, v) in headers {
            if let (Ok(name), Ok(val)) = (HeaderName::from_bytes(k.as_bytes()), HeaderValue::from_str(v)) {
                req = req.header(name, val);
            }
        }

        let resp = req.send().await?;
        Ok(resp)
    }

    pub async fn send_request(
        &self,
        method: Method,
        url: &str,
        headers: &HashMap<String, String>,
        body: Option<Bytes>,
        site: &str,
        mode: NetworkMode,
    ) -> Result<(u16, HashMap<String, String>, Bytes), TlsClientError> {
        let client = self.get_client_for_site(site, mode);
        let mut req = client.request(method, url);

        for (k, v) in headers {
            if let (Ok(name), Ok(val)) = (HeaderName::from_bytes(k.as_bytes()), HeaderValue::from_str(v)) {
                req = req.header(name, val);
            }
        }

        if let Some(b) = body {
            req = req.body(b);
        }

        let resp = req.send().await?;
        let status = resp.status().as_u16();
        
        let mut resp_headers = HashMap::new();
        for (name, val) in resp.headers() {
            if let Ok(v_str) = val.to_str() {
                resp_headers.insert(name.as_str().to_string(), v_str.to_string());
            }
        }

        let bytes = resp.bytes().await?;
        Ok((status, resp_headers, bytes))
    }
}
