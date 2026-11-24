//! 2-gram SimHash fingerprinting and real-time spam/screen-flooding danmaku deduplication.

use std::collections::VecDeque;
use std::sync::Mutex;

/// 64-bit FNV-1a hash for string slices.
fn fnv1a_64(bytes: &[u8]) -> u64 {
    const FNV_OFFSET_BASIS: u64 = 0xcbf29ce484222325;
    const FNV_PRIME: u64 = 0x100000001b3;

    let mut hash = FNV_OFFSET_BASIS;
    for &byte in bytes {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    hash
}

/// Computes a 64-bit SimHash fingerprint using 2-gram character windowing.
pub fn compute_simhash64(text: &str) -> u64 {
    let clean = text.trim();
    if clean.is_empty() {
        return 0;
    }

    let chars: Vec<char> = clean.chars().collect();
    if chars.is_empty() {
        return 0;
    }

    let mut v = [0i32; 64];

    if chars.len() == 1 {
        let mut buf = [0u8; 4];
        let bytes = chars[0].encode_utf8(&mut buf).as_bytes();
        let h = fnv1a_64(bytes);
        return h;
    }

    // 2-gram character extraction
    for window in chars.windows(2) {
        let mut s = String::with_capacity(8);
        s.push(window[0]);
        s.push(window[1]);
        let h = fnv1a_64(s.as_bytes());

        for i in 0..64 {
            let bit = (h >> i) & 1;
            if bit == 1 {
                v[i] += 1;
            } else {
                v[i] -= 1;
            }
        }
    }

    let mut fingerprint = 0u64;
    for i in 0..64 {
        if v[i] > 0 {
            fingerprint |= 1u64 << i;
        }
    }

    fingerprint
}

/// Calculates the Hamming distance between two 64-bit fingerprints.
#[inline]
pub fn hamming_distance(h1: u64, h2: u64) -> u32 {
    (h1 ^ h2).count_ones()
}

/// Real-time danmaku deduplication filter with a bounded sliding window.
pub struct DanmakuDedupFilter {
    capacity: usize,
    threshold: u32,
    window: Mutex<VecDeque<u64>>,
}

impl DanmakuDedupFilter {
    /// Creates a new filter with [capacity] max history items and [threshold] max Hamming distance.
    pub fn new(capacity: usize, threshold: u32) -> Self {
        Self {
            capacity: if capacity == 0 { 256 } else { capacity },
            threshold,
            window: Mutex::new(VecDeque::with_capacity(capacity)),
        }
    }

    /// Checks if [text] is a near-duplicate of recent danmakus.
    ///
    /// If duplicate, returns true.
    /// If unique, adds [text]'s fingerprint to the sliding window and returns false.
    pub fn is_duplicate(&self, text: &str) -> bool {
        let hash = compute_simhash64(text);
        let mut guard = self.window.lock().unwrap();

        for &existing in guard.iter() {
            if hamming_distance(hash, existing) <= self.threshold {
                return true;
            }
        }

        if guard.len() >= self.capacity {
            guard.pop_front();
        }
        guard.push_back(hash);
        false
    }

    /// Clears the filter window.
    pub fn clear(&self) {
        let mut guard = self.window.lock().unwrap();
        guard.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simhash_similar_strings() {
        let h1 = compute_simhash64("主播牛逼牛逼！！！");
        let h2 = compute_simhash64("主播牛逼牛逼！！");
        let h3 = compute_simhash64("今天天气不错真不错");

        let dist_near = hamming_distance(h1, h2);
        let dist_far = hamming_distance(h1, h3);

        assert!(dist_near <= 8, "Expected close distance, got: {}", dist_near);
        assert!(dist_far >= 18, "Expected distant hashes, got: {}", dist_far);
    }

    #[test]
    fn test_dedup_filter() {
        let filter = DanmakuDedupFilter::new(100, 3);
        assert!(!filter.is_duplicate("主播666666"));
        // Near duplicate should be filtered
        assert!(filter.is_duplicate("主播66666"));
        // Unrelated should pass
        assert!(!filter.is_duplicate("打法很稳"));
    }
}
