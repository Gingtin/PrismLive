import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

// C-ABI Function Signatures
typedef _CoreVersionC = Pointer<Utf8> Function();
typedef _CoreVersionDart = Pointer<Utf8> Function();

typedef _CoreInitC = Int32 Function();
typedef _CoreInitDart = int Function();

typedef _RelayCreateC = Pointer<Void> Function(Pointer<Utf8> proxyConfigJson);
typedef _RelayCreateDart = Pointer<Void> Function(Pointer<Utf8> proxyConfigJson);

typedef _RelayGetPortC = Uint16 Function(Pointer<Void> handle);
typedef _RelayGetPortDart = int Function(Pointer<Void> handle);

typedef _RelayRegisterSessionC = Pointer<Utf8> Function(
  Pointer<Void> handle,
  Pointer<Utf8> sessionConfigJson,
);
typedef _RelayRegisterSessionDart = Pointer<Utf8> Function(
  Pointer<Void> handle,
  Pointer<Utf8> sessionConfigJson,
);

typedef _RelayUnregisterSessionC = Void Function(
  Pointer<Void> handle,
  Pointer<Utf8> sessionId,
);
typedef _RelayUnregisterSessionDart = void Function(
  Pointer<Void> handle,
  Pointer<Utf8> sessionId,
);

typedef _RelayStartRecordC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> sessionId,
  Pointer<Utf8> outputDir,
  Pointer<Utf8> filePrefix,
  Uint64 maxDurationSecs,
  Uint64 maxBytes,
);
typedef _RelayStartRecordDart = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> sessionId,
  Pointer<Utf8> outputDir,
  Pointer<Utf8> filePrefix,
  int maxDurationSecs,
  int maxBytes,
);

typedef _RelayStopRecordC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> sessionId,
);
typedef _RelayStopRecordDart = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> sessionId,
);

typedef _RelayIsRecordingC = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> sessionId,
);
typedef _RelayIsRecordingDart = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> sessionId,
);

typedef _RelayDestroyC = Void Function(Pointer<Void> handle);
typedef _RelayDestroyDart = void Function(Pointer<Void> handle);

typedef _FreeStringC = Void Function(Pointer<Utf8> ptr);
typedef _FreeStringDart = void Function(Pointer<Utf8> ptr);

/// Native FFI bindings to `purelive_core_rs`
final class PureLiveCoreBindings {
  PureLiveCoreBindings._(DynamicLibrary lib)
      : _version = lib.lookupFunction<_CoreVersionC, _CoreVersionDart>('purelive_core_version'),
        _init = lib.lookupFunction<_CoreInitC, _CoreInitDart>('purelive_core_init'),
        _relayCreate = lib.lookupFunction<_RelayCreateC, _RelayCreateDart>('purelive_relay_create'),
        _relayGetPort = lib.lookupFunction<_RelayGetPortC, _RelayGetPortDart>('purelive_relay_get_port'),
        _relayRegisterSession =
            lib.lookupFunction<_RelayRegisterSessionC, _RelayRegisterSessionDart>('purelive_relay_register_session'),
        _relayUnregisterSession = lib.lookupFunction<_RelayUnregisterSessionC, _RelayUnregisterSessionDart>(
          'purelive_relay_unregister_session',
        ),
        _relayStartRecord = lib.lookupFunction<_RelayStartRecordC, _RelayStartRecordDart>('purelive_relay_start_record'),
        _relayStopRecord = lib.lookupFunction<_RelayStopRecordC, _RelayStopRecordDart>('purelive_relay_stop_record'),
        _relayIsRecording = lib.lookupFunction<_RelayIsRecordingC, _RelayIsRecordingDart>('purelive_relay_is_recording'),
        _relayDestroy = lib.lookupFunction<_RelayDestroyC, _RelayDestroyDart>('purelive_relay_destroy'),
        _freeString = lib.lookupFunction<_FreeStringC, _FreeStringDart>('purelive_free_string');

  final _CoreVersionDart _version;
  final _CoreInitDart _init;
  final _RelayCreateDart _relayCreate;
  final _RelayGetPortDart _relayGetPort;
  final _RelayRegisterSessionDart _relayRegisterSession;
  final _RelayUnregisterSessionDart _relayUnregisterSession;
  final _RelayStartRecordDart _relayStartRecord;
  final _RelayStopRecordDart _relayStopRecord;
  final _RelayIsRecordingDart _relayIsRecording;
  final _RelayDestroyDart _relayDestroy;
  final _FreeStringDart _freeString;

  static PureLiveCoreBindings? _cached;

  /// Loads the dynamic library safely. Returns null if not found.
  static PureLiveCoreBindings? load() {
    if (_cached != null) return _cached;

    final libName = Platform.isWindows
        ? 'purelive_core_rs.dll'
        : Platform.isMacOS || Platform.isIOS
            ? 'libpurelive_core_rs.dylib'
            : 'libpurelive_core_rs.so';

    // Search paths in order:
    // 1. Explicit environment or current working directory build targets
    // 2. Relative cargo target paths
    // 3. System library default
    final candidatePaths = [
      p.join(Directory.current.path, 'rust', 'purelive_core_rs', 'target', 'release', libName),
      p.join(Directory.current.path, 'rust', 'purelive_core_rs', 'target', 'debug', libName),
      p.join(Directory.current.path, '..', '..', 'rust', 'purelive_core_rs', 'target', 'release', libName),
      p.join(Directory.current.path, '..', '..', 'rust', 'purelive_core_rs', 'target', 'debug', libName),
      libName,
    ];

    for (final candidate in candidatePaths) {
      if (candidate == libName || File(candidate).existsSync()) {
        try {
          final dylib = DynamicLibrary.open(candidate);
          return _cached = PureLiveCoreBindings._(dylib);
        } catch (_) {
          continue;
        }
      }
    }

    return null;
  }

  String get version {
    final ptr = _version();
    return ptr.toDartString();
  }

  int init() => _init();

  Pointer<Void> relayCreate(String proxyConfigJson) {
    final cStr = proxyConfigJson.toNativeUtf8();
    try {
      return _relayCreate(cStr);
    } finally {
      malloc.free(cStr);
    }
  }

  int relayGetPort(Pointer<Void> handle) => _relayGetPort(handle);

  String? relayRegisterSession(Pointer<Void> handle, String sessionConfigJson) {
    final cStr = sessionConfigJson.toNativeUtf8();
    try {
      final resPtr = _relayRegisterSession(handle, cStr);
      if (resPtr == nullptr) return null;
      try {
        return resPtr.toDartString();
      } finally {
        _freeString(resPtr);
      }
    } finally {
      malloc.free(cStr);
    }
  }

  void relayUnregisterSession(Pointer<Void> handle, String sessionId) {
    final cStr = sessionId.toNativeUtf8();
    try {
      _relayUnregisterSession(handle, cStr);
    } finally {
      malloc.free(cStr);
    }
  }

  bool relayStartRecord(
    Pointer<Void> handle,
    String sessionId,
    String outputDir,
    String filePrefix, {
    int maxDurationSecs = 0,
    int maxBytes = 0,
  }) {
    final cSid = sessionId.toNativeUtf8();
    final cDir = outputDir.toNativeUtf8();
    final cPrefix = filePrefix.toNativeUtf8();
    try {
      final code = _relayStartRecord(handle, cSid, cDir, cPrefix, maxDurationSecs, maxBytes);
      return code == 0;
    } finally {
      malloc.free(cSid);
      malloc.free(cDir);
      malloc.free(cPrefix);
    }
  }

  bool relayStopRecord(Pointer<Void> handle, String sessionId) {
    final cSid = sessionId.toNativeUtf8();
    try {
      return _relayStopRecord(handle, cSid) == 0;
    } finally {
      malloc.free(cSid);
    }
  }

  bool relayIsRecording(Pointer<Void> handle, String sessionId) {
    final cSid = sessionId.toNativeUtf8();
    try {
      return _relayIsRecording(handle, cSid) == 1;
    } finally {
      malloc.free(cSid);
    }
  }

  void relayDestroy(Pointer<Void> handle) => _relayDestroy(handle);
}
