pub mod api;
pub mod relay;
pub mod remuxer;
pub mod stream_tee;
pub mod tls_client;

#[no_mangle]
pub extern "C" fn purelive_core_version() -> *const std::os::raw::c_char {
    static VERSION: &[u8] = b"0.1.0\0";
    VERSION.as_ptr() as *const std::os::raw::c_char
}
