use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::Arc;

use lazy_static::lazy_static;
use tokio::runtime::Runtime;

use crate::relay::{LoopbackRelayEngine, StreamSessionConfig};
use crate::tls_client::ProxyConfig;

lazy_static! {
    static ref GLOBAL_RUNTIME: Runtime = {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .thread_name("purelive-core-tokio")
            .build()
            .expect("Failed to initialize Tokio runtime for PureLive Core")
    };
}

/// Global relay holder struct for FFI pointer
pub struct RelayHandle {
    pub engine: Arc<LoopbackRelayEngine>,
}

#[no_mangle]
pub extern "C" fn purelive_core_init() -> i32 {
    // Force runtime lazy initialization
    let _ = &*GLOBAL_RUNTIME;
    0
}

#[no_mangle]
pub extern "C" fn purelive_relay_create(proxy_config_json: *const c_char) -> *mut RelayHandle {
    let proxy_config: ProxyConfig = if !proxy_config_json.is_null() {
        let c_str = unsafe { CStr::from_ptr(proxy_config_json) };
        if let Ok(json_str) = c_str.to_str() {
            serde_json::from_str(json_str).unwrap_or_default()
        } else {
            ProxyConfig::default()
        }
    } else {
        ProxyConfig::default()
    };

    let rt_handle = GLOBAL_RUNTIME.handle().clone();
    let result = GLOBAL_RUNTIME.block_on(async {
        LoopbackRelayEngine::start(proxy_config, rt_handle).await
    });

    match result {
        Ok(engine) => {
            let handle = Box::new(RelayHandle { engine });
            Box::into_raw(handle)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn purelive_relay_get_port(handle: *mut RelayHandle) -> u16 {
    if handle.is_null() {
        return 0;
    }
    let handle = unsafe { &*handle };
    handle.engine.port()
}

#[no_mangle]
pub extern "C" fn purelive_relay_register_session(
    handle: *mut RelayHandle,
    session_config_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || session_config_json.is_null() {
        return std::ptr::null_mut();
    }
    let handle = unsafe { &*handle };
    let c_str = unsafe { CStr::from_ptr(session_config_json) };
    
    let config: StreamSessionConfig = match c_str.to_str() {
        Ok(s) => match serde_json::from_str(s) {
            Ok(c) => c,
            Err(_) => return std::ptr::null_mut(),
        },
        Err(_) => return std::ptr::null_mut(),
    };

    let loopback_url = handle.engine.register_session(config);
    match CString::new(loopback_url) {
        Ok(c_res) => c_res.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn purelive_relay_unregister_session(handle: *mut RelayHandle, session_id: *const c_char) {
    if handle.is_null() || session_id.is_null() {
        return;
    }
    let handle = unsafe { &*handle };
    let c_str = unsafe { CStr::from_ptr(session_id) };
    if let Ok(id) = c_str.to_str() {
        handle.engine.unregister_session(id);
    }
}

#[no_mangle]
pub extern "C" fn purelive_relay_start_record(
    handle: *mut RelayHandle,
    session_id: *const c_char,
    output_dir: *const c_char,
    file_prefix: *const c_char,
    max_duration_secs: u64,
    max_bytes: u64,
) -> i32 {
    if handle.is_null() || session_id.is_null() || output_dir.is_null() || file_prefix.is_null() {
        return -1;
    }
    let handle = unsafe { &*handle };
    
    let sid = match unsafe { CStr::from_ptr(session_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return -2,
    };
    let out = match unsafe { CStr::from_ptr(output_dir) }.to_str() {
        Ok(s) => PathBuf::from(s),
        Err(_) => return -3,
    };
    let prefix = match unsafe { CStr::from_ptr(file_prefix) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return -4,
    };

    if handle.engine.start_record(sid, out, prefix, max_duration_secs, max_bytes) {
        0
    } else {
        1
    }
}

#[no_mangle]
pub extern "C" fn purelive_relay_stop_record(handle: *mut RelayHandle, session_id: *const c_char) -> i32 {
    if handle.is_null() || session_id.is_null() {
        return -1;
    }
    let handle = unsafe { &*handle };
    let sid = match unsafe { CStr::from_ptr(session_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return -2,
    };

    if handle.engine.stop_record(sid) {
        0
    } else {
        1
    }
}

#[no_mangle]
pub extern "C" fn purelive_relay_is_recording(handle: *mut RelayHandle, session_id: *const c_char) -> i32 {
    if handle.is_null() || session_id.is_null() {
        return 0;
    }
    let handle = unsafe { &*handle };
    let sid = match unsafe { CStr::from_ptr(session_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    if handle.engine.is_recording(sid) {
        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "C" fn purelive_relay_destroy(handle: *mut RelayHandle) {
    if handle.is_null() {
        return;
    }
    let handle = unsafe { Box::from_raw(handle) };
    handle.engine.shutdown();
}

#[no_mangle]
pub extern "C" fn purelive_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

use crate::simhash::{compute_simhash64, hamming_distance, DanmakuDedupFilter};

/// Danmaku deduplication filter handle for FFI
pub struct DanmakuFilterHandle {
    pub filter: DanmakuDedupFilter,
}

#[no_mangle]
pub extern "C" fn purelive_simhash64(text: *const c_char) -> u64 {
    if text.is_null() {
        return 0;
    }
    let c_str = unsafe { CStr::from_ptr(text) };
    if let Ok(s) = c_str.to_str() {
        compute_simhash64(s)
    } else {
        0
    }
}

#[no_mangle]
pub extern "C" fn purelive_hamming_distance(h1: u64, h2: u64) -> u32 {
    hamming_distance(h1, h2)
}

#[no_mangle]
pub extern "C" fn purelive_danmaku_filter_create(capacity: usize, threshold: u32) -> *mut DanmakuFilterHandle {
    let filter = DanmakuDedupFilter::new(capacity, threshold);
    Box::into_raw(Box::new(DanmakuFilterHandle { filter }))
}

#[no_mangle]
pub extern "C" fn purelive_danmaku_filter_is_duplicate(
    handle: *mut DanmakuFilterHandle,
    text: *const c_char,
) -> bool {
    if handle.is_null() || text.is_null() {
        return false;
    }
    let filter_ref = unsafe { &*handle };
    let c_str = unsafe { CStr::from_ptr(text) };
    if let Ok(s) = c_str.to_str() {
        filter_ref.filter.is_duplicate(s)
    } else {
        false
    }
}

#[no_mangle]
pub extern "C" fn purelive_danmaku_filter_free(handle: *mut DanmakuFilterHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle));
        }
    }
}
