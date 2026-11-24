use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Instant;

use bytes::Bytes;
use tokio::sync::broadcast;
use tracing::{error, info, warn};

use crate::remuxer::{FlvParser, FlvTag, TAG_TYPE_SCRIPT, TAG_TYPE_VIDEO};

/// Recording Configuration
#[derive(Debug, Clone)]
pub struct RecordConfig {
    pub output_dir: PathBuf,
    pub file_prefix: String,
    pub max_slice_duration_secs: u64, // e.g. 3600 (1 hour)
    pub max_slice_bytes: u64,         // e.g. 2GB
}

/// Active Recording Sink
struct RecordSink {
    config: RecordConfig,
    current_file: Option<File>,
    current_path: PathBuf,
    slice_index: usize,
    slice_started_at: Instant,
    bytes_written: u64,
    flv_header: Option<Bytes>,
    metadata_tag: Option<Bytes>,
    video_seq_header: Option<Bytes>,
}

impl RecordSink {
    fn new(config: RecordConfig) -> Self {
        Self {
            config,
            current_file: None,
            current_path: PathBuf::new(),
            slice_index: 0,
            slice_started_at: Instant::now(),
            bytes_written: 0,
            flv_header: None,
            metadata_tag: None,
            video_seq_header: None,
        }
    }

    fn open_next_slice(&mut self) -> std::io::Result<()> {
        if let Some(mut f) = self.current_file.take() {
            let _ = f.flush();
        }

        self.slice_index += 1;
        let filename = format!("{}_part{:03}.flv", self.config.file_prefix, self.slice_index);
        let path = self.config.output_dir.join(&filename);
        
        info!("StreamTee opening recording slice: {:?}", path);
        let mut file = File::create(&path)?;

        // Write FLV Header
        if let Some(ref hdr) = self.flv_header {
            file.write_all(hdr)?;
        } else {
            // Default 9-byte FLV header (Audio+Video) + PrevTagSize0 (4)
            file.write_all(b"FLV\x01\x05\x00\x00\x00\x09\x00\x00\x00\x00")?;
        }

        // Write Script Metadata if cached
        if let Some(ref meta) = self.metadata_tag {
            file.write_all(meta)?;
        }

        // Write Video Sequence Header (SPS/PPS) if cached
        if let Some(ref seq) = self.video_seq_header {
            file.write_all(seq)?;
        }

        self.current_file = Some(file);
        self.current_path = path;
        self.slice_started_at = Instant::now();
        self.bytes_written = 0;
        Ok(())
    }

    fn should_slice(&self) -> bool {
        if self.current_file.is_none() {
            return true;
        }
        let elapsed = self.slice_started_at.elapsed().as_secs();
        if self.config.max_slice_duration_secs > 0 && elapsed >= self.config.max_slice_duration_secs {
            return true;
        }
        if self.config.max_slice_bytes > 0 && self.bytes_written >= self.config.max_slice_bytes {
            return true;
        }
        false
    }

    fn write_tag(&mut self, tag: &FlvTag, raw_tag_bytes: &Bytes) -> std::io::Result<()> {
        if tag.header.tag_type == TAG_TYPE_SCRIPT {
            self.metadata_tag = Some(raw_tag_bytes.clone());
        } else if tag.header.tag_type == TAG_TYPE_VIDEO && tag.is_sequence_header() {
            self.video_seq_header = Some(raw_tag_bytes.clone());
        }

        // Check IDR keyframe boundary for slicing
        if tag.is_keyframe() && self.should_slice() {
            self.open_next_slice()?;
        } else if self.current_file.is_none() {
            self.open_next_slice()?;
        }

        if let Some(ref mut file) = self.current_file {
            file.write_all(raw_tag_bytes)?;
            self.bytes_written += raw_tag_bytes.len() as u64;
        }
        Ok(())
    }

    fn finish(&mut self) {
        if let Some(mut file) = self.current_file.take() {
            let _ = file.flush();
        }
    }
}

/// Stream Tee Channel Controller
pub struct StreamTee {
    sender: broadcast::Sender<Bytes>,
    active_recorders: Arc<AtomicU64>,
    recording_active: Arc<AtomicBool>,
}

impl StreamTee {
    pub fn new(capacity: usize) -> Self {
        let (sender, _) = broadcast::channel(capacity);
        Self {
            sender,
            active_recorders: Arc::new(AtomicU64::new(0)),
            recording_active: Arc::new(AtomicBool::new(false)),
        }
    }

    /// Broadcasts an incoming chunk to all active consumers (player & recorders)
    pub fn broadcast(&self, chunk: Bytes) {
        // broadcast sends only if there are active subscribers
        let _ = self.sender.send(chunk);
    }

    /// Subscribes a consumer (e.g. playback reader)
    pub fn subscribe(&self) -> broadcast::Receiver<Bytes> {
        self.sender.subscribe()
    }

    /// Spawns a background worker that records the stream to disk without extra network requests
    pub fn start_recording(
        &self,
        config: RecordConfig,
        cancel_token: tokio_util::sync::CancellationToken,
        rt_handle: &tokio::runtime::Handle,
    ) {
        let mut rx = self.sender.subscribe();
        let active_count = self.active_recorders.clone();
        let recording_flag = self.recording_active.clone();

        rt_handle.spawn(async move {
            active_count.fetch_add(1, Ordering::SeqCst);
            recording_flag.store(true, Ordering::SeqCst);
            info!("StreamTee: recording worker started for {:?}", config.output_dir);

            let mut sink = RecordSink::new(config);
            let mut parser = FlvParser::new();

            loop {
                tokio::select! {
                    _ = cancel_token.cancelled() => {
                        info!("StreamTee: recording worker cancellation received");
                        break;
                    }
                    recv_res = rx.recv() => {
                        match recv_res {
                            Ok(bytes) => {
                                parser.push(&bytes);
                                
                                if sink.flv_header.is_none() {
                                    if let Some(hdr) = parser.parse_header() {
                                        sink.flv_header = Some(hdr);
                                    }
                                }

                                while let Some(tag) = parser.next_tag() {
                                    let serialized = FlvParser::serialize_tag(&tag);
                                    if let Err(e) = sink.write_tag(&tag, &serialized) {
                                        error!("StreamTee write error: {}", e);
                                        break;
                                    }
                                }
                            }
                            Err(broadcast::error::RecvError::Lagged(lagged)) => {
                                warn!("StreamTee recorder lagged behind by {} messages", lagged);
                            }
                            Err(broadcast::error::RecvError::Closed) => {
                                info!("StreamTee stream ended");
                                break;
                            }
                        }
                    }
                }
            }

            sink.finish();
            let remaining = active_count.fetch_sub(1, Ordering::SeqCst) - 1;
            if remaining == 0 {
                recording_flag.store(false, Ordering::SeqCst);
            }
            info!("StreamTee: recording worker finished, remaining active: {}", remaining);
        });
    }

    pub fn is_recording(&self) -> bool {
        self.recording_active.load(Ordering::SeqCst)
    }
}
