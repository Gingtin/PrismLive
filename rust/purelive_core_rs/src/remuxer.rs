use bytes::{Buf, BufMut, Bytes, BytesMut};

/// FLV Tag Types
pub const TAG_TYPE_AUDIO: u8 = 0x08;
pub const TAG_TYPE_VIDEO: u8 = 0x09;
pub const TAG_TYPE_SCRIPT: u8 = 0x12;

/// Frame Types
pub const FRAME_TYPE_KEYFRAME: u8 = 0x01;
pub const FRAME_TYPE_INTER: u8 = 0x02;

/// Parsed FLV Tag Header
#[derive(Debug, Clone)]
pub struct FlvTagHeader {
    pub tag_type: u8,
    pub data_size: u32,
    pub timestamp: u32,
    pub stream_id: u32,
}

/// A parsed FLV Tag containing header and raw payload
#[derive(Debug, Clone)]
pub struct FlvTag {
    pub header: FlvTagHeader,
    pub data: Bytes,
}

impl FlvTag {
    /// Whether this tag is an IDR keyframe (safe for splitting / slicing)
    pub fn is_keyframe(&self) -> bool {
        if self.header.tag_type != TAG_TYPE_VIDEO || self.data.is_empty() {
            return false;
        }
        let frame_type = (self.data[0] >> 4) & 0x0F;
        frame_type == FRAME_TYPE_KEYFRAME
    }

    /// Whether this tag is an AVC/HEVC sequence header (SPS/PPS)
    pub fn is_sequence_header(&self) -> bool {
        if self.header.tag_type != TAG_TYPE_VIDEO || self.data.len() < 2 {
            return false;
        }
        let packet_type = self.data[1];
        packet_type == 0 // AVC/HEVC sequence header
    }
}

/// Monotonic timestamp transformer for FLV streams
#[derive(Default)]
pub struct TimestampFixer {
    base_ts: Option<u32>,
    last_in_ts: u32,
    last_out_ts: u32,
}

impl TimestampFixer {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn fix(&mut self, in_ts: u32) -> u32 {
        let base = *self.base_ts.get_or_insert(in_ts);
        
        let mut out_ts = if in_ts >= base {
            in_ts - base
        } else {
            // Clock reset or wrap-around, clamp monotonically
            self.last_out_ts + 1
        };

        if out_ts < self.last_out_ts {
            out_ts = self.last_out_ts + 1;
        }

        self.last_in_ts = in_ts;
        self.last_out_ts = out_ts;
        out_ts
    }
}

/// FLV Stream Splicer and Tag Parser
pub struct FlvParser {
    buffer: BytesMut,
    header_parsed: bool,
    timestamp_fixer: TimestampFixer,
}

impl FlvParser {
    pub fn new() -> Self {
        Self {
            buffer: BytesMut::with_capacity(64 * 1024),
            header_parsed: false,
            timestamp_fixer: TimestampFixer::new(),
        }
    }

    /// Appends incoming bytes from upstream
    pub fn push(&mut self, chunk: &[u8]) {
        self.buffer.extend_from_slice(chunk);
    }

    /// Extracts standard 9-byte FLV Header + 4-byte PreviousTagSize0 if present
    pub fn parse_header(&mut self) -> Option<Bytes> {
        if self.header_parsed {
            return None;
        }
        // FLV header (9) + PreviousTagSize0 (4) = 13 bytes
        if self.buffer.len() < 13 {
            return None;
        }
        if &self.buffer[0..3] != b"FLV" {
            // Invalid signature, discard
            return None;
        }
        self.header_parsed = true;
        Some(self.buffer.split_to(13).freeze())
    }

    /// Tries to parse the next complete tag
    pub fn next_tag(&mut self) -> Option<FlvTag> {
        if !self.header_parsed && self.parse_header().is_none() {
            return None;
        }

        // Tag Header is 11 bytes
        if self.buffer.len() < 11 {
            return None;
        }

        let tag_type = self.buffer[0];
        let data_size = ((self.buffer[1] as u32) << 16)
            | ((self.buffer[2] as u32) << 8)
            | (self.buffer[3] as u32);
        
        // 24-bit timestamp + 8-bit timestamp extended
        let ts_lower = ((self.buffer[4] as u32) << 16)
            | ((self.buffer[5] as u32) << 8)
            | (self.buffer[6] as u32);
        let ts_upper = self.buffer[7] as u32;
        let raw_timestamp = (ts_upper << 24) | ts_lower;

        let stream_id = ((self.buffer[8] as u32) << 16)
            | ((self.buffer[9] as u32) << 8)
            | (self.buffer[10] as u32);

        let total_tag_len = 11 + (data_size as usize) + 4; // 11 hdr + data + 4 PrevTagSize
        if self.buffer.len() < total_tag_len {
            return None;
        }

        // Advance 11 bytes
        self.buffer.advance(11);
        let data = self.buffer.split_to(data_size as usize).freeze();
        // Skip PreviousTagSize (4 bytes)
        self.buffer.advance(4);

        let fixed_ts = self.timestamp_fixer.fix(raw_timestamp);

        Some(FlvTag {
            header: FlvTagHeader {
                tag_type,
                data_size,
                timestamp: fixed_ts,
                stream_id,
            },
            data,
        })
    }

    /// Serializes a tag into bytes with updated monotonic timestamps
    pub fn serialize_tag(tag: &FlvTag) -> Bytes {
        let mut buf = BytesMut::with_capacity(11 + tag.data.len() + 4);
        
        // TagType (1)
        buf.put_u8(tag.header.tag_type);
        
        // DataSize (3)
        let ds = tag.header.data_size;
        buf.put_u8(((ds >> 16) & 0xFF) as u8);
        buf.put_u8(((ds >> 8) & 0xFF) as u8);
        buf.put_u8((ds & 0xFF) as u8);

        // Timestamp (3) + TimestampExtended (1)
        let ts = tag.header.timestamp;
        buf.put_u8(((ts >> 16) & 0xFF) as u8);
        buf.put_u8(((ts >> 8) & 0xFF) as u8);
        buf.put_u8((ts & 0xFF) as u8);
        buf.put_u8(((ts >> 24) & 0xFF) as u8);

        // StreamID (3)
        let sid = tag.header.stream_id;
        buf.put_u8(((sid >> 16) & 0xFF) as u8);
        buf.put_u8(((sid >> 8) & 0xFF) as u8);
        buf.put_u8((sid & 0xFF) as u8);

        // Data
        buf.extend_from_slice(&tag.data);

        // PreviousTagSize (4) = 11 + DataSize
        let prev_size = 11 + tag.header.data_size;
        buf.put_u32(prev_size);

        buf.freeze()
    }
}
