import "dart:convert";
import "dart:ffi" as ffi;

// =============================================================================
// NIOOO M — NATIVE C++17 ENGINE FFI BRIDGE (ZERO-COPY STREAMTAPE EXTRACTOR &
// 60FPS HARDWARE PLAYBACK BOOSTER ON ANDROID NDK)
// =============================================================================

typedef _ExtractUrlNative = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> htmlUtf8,
);
typedef _ExtractUrlDart = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> htmlUtf8,
);

typedef _ExtractFileIdNative = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> rawInput,
);
typedef _ExtractFileIdDart = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> rawInput,
);

typedef _GetCachedUrlNative = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> fileId,
);
typedef _GetCachedUrlDart = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> fileId,
);

typedef _SetCachedUrlNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> fileId,
  ffi.Pointer<ffi.Uint8> directUrl,
);
typedef _SetCachedUrlDart = void Function(
  ffi.Pointer<ffi.Uint8> fileId,
  ffi.Pointer<ffi.Uint8> directUrl,
);

typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<ffi.Uint8> ptr);
typedef _FreeStringDart = void Function(ffi.Pointer<ffi.Uint8> ptr);

typedef _BoostPlaybackNative = ffi.Int32 Function(ffi.Int32 enableHighPriority);
typedef _BoostPlaybackDart = int Function(int enableHighPriority);

typedef _MallocNative = ffi.Pointer<ffi.Uint8> Function(ffi.IntPtr size);
typedef _MallocDart = ffi.Pointer<ffi.Uint8> Function(int size);

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Uint8> ptr);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Uint8> ptr);

class NativeCppEngine {
  static bool _initialized = false;
  static bool _available = false;

  static _ExtractUrlDart? _extractUrlFn;
  static _ExtractFileIdDart? _extractFileIdFn;
  static _GetCachedUrlDart? _getCachedUrlFn;
  static _SetCachedUrlDart? _setCachedUrlFn;
  static _FreeStringDart? _freeStringFn;
  static _BoostPlaybackDart? _boostPlaybackFn;
  static _MallocDart? _mallocFn;
  static _FreeDart? _freeFn;

  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    try {
      final lib = ffi.DynamicLibrary.open("libniooom_native_engine.so");
      final processLib = ffi.DynamicLibrary.process();

      _extractUrlFn = lib
          .lookup<ffi.NativeFunction<_ExtractUrlNative>>(
            "niooom_extract_streamtape_url",
          )
          .asFunction<_ExtractUrlDart>();

      _extractFileIdFn = lib
          .lookup<ffi.NativeFunction<_ExtractFileIdNative>>(
            "niooom_extract_file_id",
          )
          .asFunction<_ExtractFileIdDart>();

      _getCachedUrlFn = lib
          .lookup<ffi.NativeFunction<_GetCachedUrlNative>>(
            "niooom_get_cached_direct_url",
          )
          .asFunction<_GetCachedUrlDart>();

      _setCachedUrlFn = lib
          .lookup<ffi.NativeFunction<_SetCachedUrlNative>>(
            "niooom_set_cached_direct_url",
          )
          .asFunction<_SetCachedUrlDart>();

      _freeStringFn = lib
          .lookup<ffi.NativeFunction<_FreeStringNative>>(
            "niooom_free_string",
          )
          .asFunction<_FreeStringDart>();

      _boostPlaybackFn = lib
          .lookup<ffi.NativeFunction<_BoostPlaybackNative>>(
            "niooom_boost_playback_engine",
          )
          .asFunction<_BoostPlaybackDart>();

      _mallocFn = processLib
          .lookup<ffi.NativeFunction<_MallocNative>>("malloc")
          .asFunction<_MallocDart>();

      _freeFn = processLib
          .lookup<ffi.NativeFunction<_FreeNative>>("free")
          .asFunction<_FreeDart>();

      _available = true;
      _boostPlaybackFn?.call(1);
    } catch (_) {
      _available = false;
    }
  }

  static bool get isAvailable {
    ensureInitialized();
    return _available;
  }

  static ffi.Pointer<ffi.Uint8> _toNativeUtf8(String value) {
    final bytes = utf8.encode(value);
    final ptr = _mallocFn!(bytes.length + 1);
    final list = ptr.asTypedList(bytes.length + 1);
    list.setAll(0, bytes);
    list[bytes.length] = 0;
    return ptr;
  }

  static String? _fromNativeUtf8AndFree(ffi.Pointer<ffi.Uint8> ptr) {
    if (ptr == ffi.nullptr) return null;
    try {
      int length = 0;
      while (ptr[length] != 0) {
        length++;
        if (length > 1048576) break;
      }
      if (length == 0) return null;
      final bytes = ptr.asTypedList(length);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      _freeStringFn?.call(ptr);
    }
  }

  /// Uses Native C++17 (`std::string_view`) to extract the clean Streamtape File ID.
  static String? extractFileIdWithCpp(String rawInput) {
    ensureInitialized();
    if (!_available || _extractFileIdFn == null || _mallocFn == null) {
      return null;
    }
    final inPtr = _toNativeUtf8(rawInput);
    try {
      final outPtr = _extractFileIdFn!(inPtr);
      return _fromNativeUtf8AndFree(outPtr);
    } catch (_) {
      return null;
    } finally {
      _freeFn?.call(inPtr);
    }
  }

  /// Uses Native C++17 (`-O3` Zero-Copy Scanner) to extract the direct Streamtape
  /// `get_video` stream link from HTML in microseconds.
  static String? extractStreamtapeUrlWithCpp(String htmlContent) {
    ensureInitialized();
    if (!_available || _extractUrlFn == null || _mallocFn == null) {
      return null;
    }
    final inPtr = _toNativeUtf8(htmlContent);
    try {
      final outPtr = _extractUrlFn!(inPtr);
      return _fromNativeUtf8AndFree(outPtr);
    } catch (_) {
      return null;
    } finally {
      _freeFn?.call(inPtr);
    }
  }

  /// Queries the Native C++ in-memory hash map (`std::unordered_map`) for a cached direct URL.
  static String? getCachedDirectUrl(String fileId) {
    ensureInitialized();
    if (!_available || _getCachedUrlFn == null || _mallocFn == null) {
      return null;
    }
    final inPtr = _toNativeUtf8(fileId);
    try {
      final outPtr = _getCachedUrlFn!(inPtr);
      return _fromNativeUtf8AndFree(outPtr);
    } catch (_) {
      return null;
    } finally {
      _freeFn?.call(inPtr);
    }
  }

  /// Stores a resolved direct stream URL inside the Native C++ in-memory hash map.
  static void setCachedDirectUrl(String fileId, String directUrl) {
    ensureInitialized();
    if (!_available || _setCachedUrlFn == null || _mallocFn == null) {
      return;
    }
    final idPtr = _toNativeUtf8(fileId);
    final urlPtr = _toNativeUtf8(directUrl);
    try {
      _setCachedUrlFn!(idPtr, urlPtr);
    } catch (_) {
    } finally {
      _freeFn?.call(idPtr);
      _freeFn?.call(urlPtr);
    }
  }

  /// Boosts OS thread priority for ultra-smooth 60fps video decoding & playback.
  static void boostPlaybackPriority({bool highPriority = true}) {
    ensureInitialized();
    if (!_available || _boostPlaybackFn == null) return;
    try {
      _boostPlaybackFn!(highPriority ? 1 : 0);
    } catch (_) {}
  }
}
