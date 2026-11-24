use purelive_core_rs::purelive_core_version;
use purelive_core_rs::remuxer::{FlvParser, TimestampFixer, TAG_TYPE_VIDEO};
use purelive_core_rs::stream_tee::StreamTee;
use bytes::Bytes;
use std::ffi::CStr;

#[test]
fn test_version_c_api() {
    let version_ptr = purelive_core_version();
    assert!(!version_ptr.is_null());
    let c_str = unsafe { CStr::from_ptr(version_ptr) };
    assert_eq!(c_str.to_str().unwrap(), "0.1.0");
}

#[test]
fn test_timestamp_fixer_monotonicity() {
    let mut fixer = TimestampFixer::new();
    assert_eq!(fixer.fix(1000), 0);
    assert_eq!(fixer.fix(1040), 40);
    assert_eq!(fixer.fix(1080), 80);
    // Timestamp drop/wrap-around
    assert_eq!(fixer.fix(500), 81);
    assert_eq!(fixer.fix(520), 82);
}

#[test]
fn test_flv_parser_and_keyframe_detection() {
    let mut parser = FlvParser::new();
    
    // 9-byte FLV header + 4-byte PrevTagSize0
    let flv_hdr = b"FLV\x01\x05\x00\x00\x00\x09\x00\x00\x00\x00";
    parser.push(flv_hdr);

    let parsed_hdr = parser.parse_header();
    assert!(parsed_hdr.is_some());
    assert_eq!(parsed_hdr.unwrap().len(), 13);

    // Build a fake video keyframe tag:
    // Header (11): type=0x09, size=5, ts=0, streamId=0
    // Payload (5): 0x17 (Keyframe AVC), 0x01 (NALU), 0x00 0x00 0x00 (CTS)
    // PrevTagSize (4): 11 + 5 = 16 (0x00000010)
    let tag_bytes = vec![
        0x09, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x17, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x10,
    ];

    parser.push(&tag_bytes);
    let tag = parser.next_tag();
    assert!(tag.is_some());
    let tag = tag.unwrap();
    assert_eq!(tag.header.tag_type, TAG_TYPE_VIDEO);
    assert!(tag.is_keyframe());
    assert!(!tag.is_sequence_header());
}

#[tokio::test]
async fn test_stream_tee_broadcast() {
    let tee = StreamTee::new(16);
    let mut rx1 = tee.subscribe();
    let mut rx2 = tee.subscribe();

    tee.broadcast(Bytes::from_static(b"hello-stream-tee"));

    let chunk1 = rx1.recv().await.unwrap();
    let chunk2 = rx2.recv().await.unwrap();

    assert_eq!(chunk1.as_ref(), b"hello-stream-tee");
    assert_eq!(chunk2.as_ref(), b"hello-stream-tee");
}
