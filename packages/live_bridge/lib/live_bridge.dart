/// PureLive Native Rust Core Bridge.
///
/// Exposes high-performance native TLS fingerprinting, loopback relaying,
/// and Stream Tee zero-copy concurrent recording.
library live_bridge;

export 'src/bridge_bindings.dart' show PureLiveCoreBindings;
export 'src/purelive_core_bridge.dart'
    show DanmakuFilter, PureLiveCoreBridge, RustRelayServer, computeSimHash64, hammingDistance;
