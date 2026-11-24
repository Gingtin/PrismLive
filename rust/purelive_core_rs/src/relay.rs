use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;

use futures_util::StreamExt;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_util::sync::CancellationToken;
use tracing::{error, info, warn};

use crate::remuxer::FlvParser;
use crate::stream_tee::{RecordConfig, StreamTee};
use crate::tls_client::{NetworkMode, ProxyConfig, StealthTlsClient};

/// Upstream Live Stream Configuration passed from Dart
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamSessionConfig {
    pub session_id: String,
    pub upstream_url: String,
    pub site: String,
    pub network_mode: NetworkMode,
    pub headers: HashMap<String, String>,
    pub is_flv: bool,
}

/// An active registered stream session
struct ActiveSession {
    config: StreamSessionConfig,
    tee: Arc<StreamTee>,
    record_cancel: Option<CancellationToken>,
}

/// Native Loopback Relay Engine
pub struct LoopbackRelayEngine {
    port: u16,
    client: StealthTlsClient,
    sessions: Arc<RwLock<HashMap<String, ActiveSession>>>,
    shutdown_token: CancellationToken,
    rt_handle: tokio::runtime::Handle,
}

impl LoopbackRelayEngine {
    pub async fn start(
        proxy_config: ProxyConfig,
        rt_handle: tokio::runtime::Handle,
    ) -> Result<Arc<Self>, std::io::Error> {
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        let local_addr = listener.local_addr()?;
        let port = local_addr.port();

        info!("LoopbackRelayEngine listening on http://127.0.0.1:{}", port);

        let client = StealthTlsClient::new(proxy_config)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;

        let sessions = Arc::new(RwLock::new(HashMap::new()));
        let shutdown_token = CancellationToken::new();

        let engine = Arc::new(Self {
            port,
            client,
            sessions: sessions.clone(),
            shutdown_token: shutdown_token.clone(),
            rt_handle: rt_handle.clone(),
        });

        // Spawn listener loop
        let engine_clone = engine.clone();
        rt_handle.spawn(async move {
            loop {
                tokio::select! {
                    _ = shutdown_token.cancelled() => {
                        info!("LoopbackRelayEngine server stopped");
                        break;
                    }
                    accept_res = listener.accept() => {
                        match accept_res {
                            Ok((stream, peer)) => {
                                let engine_ref = engine_clone.clone();
                                engine_clone.rt_handle.spawn(async move {
                                    if let Err(e) = engine_ref.handle_client(stream, peer).await {
                                        warn!("Relay client error from {}: {}", peer, e);
                                    }
                                });
                            }
                            Err(e) => {
                                error!("Relay accept error: {}", e);
                            }
                        }
                    }
                }
            }
        });

        Ok(engine)
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn register_session(&self, config: StreamSessionConfig) -> String {
        let path = format!("/stream/{}", config.session_id);
        let session_id = config.session_id.clone();
        let tee = Arc::new(StreamTee::new(256));

        let active = ActiveSession {
            config,
            tee,
            record_cancel: None,
        };

        self.sessions.write().insert(session_id, active);
        format!("http://127.0.0.1:{}{}", self.port, path)
    }

    pub fn unregister_session(&self, session_id: &str) {
        let mut map = self.sessions.write();
        if let Some(mut session) = map.remove(session_id) {
            if let Some(cancel) = session.record_cancel.take() {
                cancel.cancel();
            }
        }
    }

    pub fn start_record(
        &self,
        session_id: &str,
        output_dir: PathBuf,
        file_prefix: String,
        max_slice_duration_secs: u64,
        max_slice_bytes: u64,
    ) -> bool {
        let mut map = self.sessions.write();
        if let Some(session) = map.get_mut(session_id) {
            if session.record_cancel.is_some() {
                return false; // Already recording
            }
            let cancel = CancellationToken::new();
            session.record_cancel = Some(cancel.clone());

            let config = RecordConfig {
                output_dir,
                file_prefix,
                max_slice_duration_secs,
                max_slice_bytes,
            };

            session.tee.start_recording(config, cancel, &self.rt_handle);
            true
        } else {
            false
        }
    }

    pub fn stop_record(&self, session_id: &str) -> bool {
        let mut map = self.sessions.write();
        if let Some(session) = map.get_mut(session_id) {
            if let Some(cancel) = session.record_cancel.take() {
                cancel.cancel();
                return true;
            }
        }
        false
    }

    pub fn is_recording(&self, session_id: &str) -> bool {
        let map = self.sessions.read();
        map.get(session_id)
            .map(|s| s.tee.is_recording())
            .unwrap_or(false)
    }

    pub fn shutdown(&self) {
        self.shutdown_token.cancel();
        let mut map = self.sessions.write();
        for (_, mut session) in map.drain() {
            if let Some(cancel) = session.record_cancel.take() {
                cancel.cancel();
            }
        }
    }

    async fn handle_client(&self, mut stream: TcpStream, _peer: SocketAddr) -> Result<(), std::io::Error> {
        let mut buf = [0u8; 2048];
        let n = stream.read(&mut buf).await?;
        if n == 0 {
            return Ok(());
        }

        let request_str = String::from_utf8_lossy(&buf[..n]);
        let mut lines = request_str.lines();
        let request_line = match lines.next() {
            Some(l) => l,
            None => return Ok(()),
        };

        let mut parts = request_line.split_whitespace();
        let _method = parts.next().unwrap_or("GET");
        let path = parts.next().unwrap_or("/");

        // Match /stream/<session_id>
        if let Some(session_id) = path.strip_prefix("/stream/") {
            let session_info = {
                let map = self.sessions.read();
                map.get(session_id).map(|s| (s.config.clone(), s.tee.clone()))
            };

            if let Some((config, tee)) = session_info {
                self.proxy_stream_response(&mut stream, &config, &tee).await?;
                return Ok(());
            }
        }

        // Default 404 response
        let not_found = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        stream.write_all(not_found.as_bytes()).await?;
        Ok(())
    }

    async fn proxy_stream_response(
        &self,
        stream: &mut TcpStream,
        config: &StreamSessionConfig,
        tee: &Arc<StreamTee>,
    ) -> Result<(), std::io::Error> {
        info!("Loopback relay proxying stream for: {}", config.upstream_url);

        let upstream_res = self
            .client
            .fetch_stream(
                &config.upstream_url,
                &config.headers,
                &config.site,
                config.network_mode,
            )
            .await;

        let upstream_resp = match upstream_res {
            Ok(resp) => resp,
            Err(e) => {
                error!("Upstream fetch failed: {}", e);
                let err_resp = "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                stream.write_all(err_resp.as_bytes()).await?;
                return Ok(());
            }
        };

        let content_type = if config.is_flv {
            "video/x-flv"
        } else {
            "application/vnd.apple.mpegurl"
        };

        // Send HTTP 200 OK Chunked Response Headers to local player
        let response_headers = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: {}\r\nTransfer-Encoding: chunked\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n",
            content_type
        );
        stream.write_all(response_headers.as_bytes()).await?;

        let mut byte_stream = upstream_resp.bytes_stream();
        let mut flv_parser = if config.is_flv { Some(FlvParser::new()) } else { None };

        while let Some(chunk_res) = byte_stream.next().await {
            match chunk_res {
                Ok(chunk) => {
                    // Send to Stream Tee for concurrent zero-copy recording
                    tee.broadcast(chunk.clone());

                    // If FLV, verify monotonicity
                    let out_bytes = if let Some(ref mut parser) = flv_parser {
                        parser.push(&chunk);
                        let mut fixed_buf = bytes::BytesMut::new();
                        if let Some(hdr) = parser.parse_header() {
                            fixed_buf.extend_from_slice(&hdr);
                        }
                        while let Some(tag) = parser.next_tag() {
                            fixed_buf.extend_from_slice(&FlvParser::serialize_tag(&tag));
                        }
                        if fixed_buf.is_empty() {
                            chunk
                        } else {
                            fixed_buf.freeze()
                        }
                    } else {
                        chunk
                    };

                    // Send HTTP Chunk: <hex_len>\r\n<data>\r\n
                    let hex_len = format!("{:X}\r\n", out_bytes.len());
                    if stream.write_all(hex_len.as_bytes()).await.is_err() {
                        break; // Local client disconnected
                    }
                    if stream.write_all(&out_bytes).await.is_err() {
                        break;
                    }
                    if stream.write_all(b"\r\n").await.is_err() {
                        break;
                    }
                }
                Err(e) => {
                    warn!("Stream chunk error: {}", e);
                    break;
                }
            }
        }

        // Close chunked stream
        let _ = stream.write_all(b"0\r\n\r\n").await;
        Ok(())
    }
}
