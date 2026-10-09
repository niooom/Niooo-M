import "dart:convert";
import "dart:ffi" as ffi;

// =============================================================================
// NIOOO M — NATIVE C++17 ENGINE FFI BRIDGE
// 1. Video Player Engine (Strictly for playing video streams only)
// 2. High-Speed API Download & Real-Time Progress Engine (Strictly for
//    downloading via the API key `download_url` only)
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

typedef _PrepareApiDlUrlNative = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> apiDownloadUrl,
);
typedef _PrepareApiDlUrlDart = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> apiDownloadUrl,
);

typedef _ExtractApiDlBinaryNative = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> downloadPageHtml,
  ffi.Pointer<ffi.Uint8> fallbackApiDownloadUrl,
);
typedef _ExtractApiDlBinaryDart = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> downloadPageHtml,
  ffi.Pointer<ffi.Uint8> fallbackApiDownloadUrl,
);

typedef _DlSessionStartNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> movieId,
  ffi.Int64 totalBytes,
);
typedef _DlSessionStartDart = void Function(
  ffi.Pointer<ffi.Uint8> movieId,
  int totalBytes,
);

typedef _DlSessionOnChunkNative = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> movieId,
  ffi.Int64 chunkBytes,
  ffi.Int64 totalBytes,
);
typedef _DlSessionOnChunkDart = ffi.Pointer<ffi.Uint8> Function(
  ffi.Pointer<ffi.Uint8> movieId,
  int chunkBytes,
  int totalBytes,
);

typedef _DlSessionFinishNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> movieId,
);
typedef _DlSessionFinishDart = void Function(
  ffi.Pointer<ffi.Uint8> movieId,
);

typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<ffi.Uint8> ptr);
typedef _FreeStringDart = void Function(ffi.Pointer<ffi.Uint8> ptr);

typedef _BoostPlaybackNative = ffi.Int32 Function(ffi.Int32 enableHighPriority);
typedef _BoostPlaybackDart = int Function(int enableHighPriority);

typedef _MallocNative = ffi.Pointer<ffi.Uint8> Function(ffi.IntPtr size);
typedef _MallocDart = ffi.Pointer<ffi.Uint8> Function(int size);

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Uint8> ptr);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Uint8> ptr);

class CppDownloadProgressMetrics {
  final int percent;
  final double progressRatio;
  final int downloadedBytes;
  final int totalBytes;
  final String speedLabel;

  const CppDownloadProgressMetrics({
    required this.percent,
    required this.progressRatio,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speedLabel,
  });
}

class NativeCppEngine {
  static bool _initialized = false;
  static bool _available = false;

  static _ExtractUrlDart? _extractUrlFn;
  static _ExtractFileIdDart? _extractFileIdFn;
  static _GetCachedUrlDart? _getCachedUrlFn;
  static _SetCachedUrlDart? _setCachedUrlFn;
  static _PrepareApiDlUrlDart? _prepareApiDlUrlFn;
  static _ExtractApiDlBinaryDart? _extractApiDlBinaryFn;
  static _DlSessionStartDart? _dlSessionStartFn;
  static _DlSessionOnChunkDart? _dlSessionOnChunkFn;
  static _DlSessionFinishDart? _dlSessionFinishFn;
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

      _prepareApiDlUrlFn = lib
          .lookup<ffi.NativeFunction<_PrepareApiDlUrlNative>>(
            "niooom_prepare_api_download_url",
          )
          .asFunction<_PrepareApiDlUrlDart>();

      _extractApiDlBinaryFn = lib
          .lookup<ffi.NativeFunction<_ExtractApiDlBinaryNative>>(
            "niooom_extract_api_download_binary_link",
          )
          .asFunction<_ExtractApiDlBinaryDart>();

      _dlSessionStartFn = lib
          .lookup<ffi.NativeFunction<_DlSessionStartNative>>(
            "niooom_download_session_start",
          )
          .asFunction<_DlSessionStartDart>();

      _dlSessionOnChunkFn = lib
          .lookup<ffi.NativeFunction<_DlSessionOnChunkNative>>(
            "niooom_download_session_on_chunk",
          )
          .asFunction<_DlSessionOnChunkDart>();

      _dlSessionFinishFn = lib
          .lookup<ffi.NativeFunction<_DlSessionFinishNative>>(
            "niooom_download_session_finish",
          )
          .asFunction<_DlSessionFinishDart>();

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

  // ===========================================================================
  // 1. VIDEO PLAYBACK METHODS (STRICTLY FOR VIDEO PLAYER STREAMING ONLY)
  // ===========================================================================

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
  /// `get_video` playback stream link (`&stream=1`) for the video player ONLY.
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

  /// Queries the Native C++ in-memory hash map for a cached video player stream URL.
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

  /// Stores a resolved direct video player stream URL inside the Native C++ memory cache.
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

  // ===========================================================================
  // 2. C++17 HIGH-SPEED API DOWNLOAD & REAL-TIME PROGRESS METHODS
  //    (STRICTLY FOR DOWNLOADING VIA THE API KEY'S `download_url` ONLY)
  // ===========================================================================

  /// Validates and prepares the `download_url` from the Niooo M API key using C++17.
  /// Ensures `/e/` embed links or `&stream=1` playback links are never used for downloading.
  static String prepareApiDownloadUrl(String apiDownloadUrl) {
    final trimmed = apiDownloadUrl.trim();
    if (trimmed.isEmpty) return "";

    ensureInitialized();
    if (_available && _prepareApiDlUrlFn != null && _mallocFn != null) {
      final inPtr = _toNativeUtf8(trimmed);
      try {
        final outPtr = _prepareApiDlUrlFn!(inPtr);
        final res = _fromNativeUtf8AndFree(outPtr);
        if (res != null && res.isNotEmpty) {
          return res;
        }
      } catch (_) {
      } finally {
        _freeFn?.call(inPtr);
      }
    }

    String fallback = trimmed;
    if (!fallback.startsWith("http://") && !fallback.startsWith("https://")) {
      fallback = fallback.startsWith("//")
          ? "https:$fallback"
          : "https://$fallback";
    }
    fallback = fallback
        .replaceAll("streamtape.com/e/", "streamtape.com/v/")
        .replaceAll("&stream=1", "&dl=1");
    return fallback;
  }

  /// Parses the HTML of the API `download_url` page in C++17 (`-O3`) to resolve
  /// the `&dl=1` binary download link (strictly separate from video playback).
  static String? extractApiDownloadBinaryLink(
    String downloadPageHtml,
    String apiDownloadUrl,
  ) {
    ensureInitialized();
    if (_available && _extractApiDlBinaryFn != null && _mallocFn != null) {
      final htmlPtr = _toNativeUtf8(downloadPageHtml);
      final urlPtr = _toNativeUtf8(apiDownloadUrl);
      try {
        final outPtr = _extractApiDlBinaryFn!(htmlPtr, urlPtr);
        final res = _fromNativeUtf8AndFree(outPtr);
        if (res != null && res.isNotEmpty) {
          return res;
        }
      } catch (_) {
      } finally {
        _freeFn?.call(htmlPtr);
        _freeFn?.call(urlPtr);
      }
    }

    // Fallback Dart parser strictly for `#norobotlink` / `#ideoooolink` + `&dl=1`
    final regex = RegExp(
      r"""getElementById\(['"](?:norobotlink|ideoooolink|robotlink)['"]\)\.innerHTML\s*=\s*['"]([^'"]*)['"]\s*\+\s*(?:['"]['"]\s*\+\s*)?\(['"]([^'"]+)['"]\)((?:\.substring\(\d+\))+)""",
    );
    final matches = regex.allMatches(downloadPageHtml);
    String? candidate;
    for (final match in matches) {
      final prefix = match.group(1) ?? "";
      String suffix = match.group(2) ?? "";
      final subPart = match.group(3) ?? "";
      final subNums = RegExp(r"\d+").allMatches(subPart);
      for (final nMatch in subNums) {
        final skip = int.tryParse(nMatch.group(0) ?? "0") ?? 0;
        if (skip > 0 && skip < suffix.length) {
          suffix = suffix.substring(skip);
        }
      }
      final combined = "$prefix$suffix";
      if (combined.contains("get_video?") && combined.contains("token=")) {
        if (combined.startsWith("//")) {
          candidate = "https:$combined&dl=1";
        } else if (combined.startsWith("/")) {
          candidate = "https:/$combined&dl=1";
        } else {
          candidate = "https://$combined&dl=1";
        }
      }
    }
    return candidate;
  }

  /// Starts a Native C++17 download session for `movieId` and boosts I/O thread priority.
  static void startDownloadSession(String movieId, int totalBytes) {
    ensureInitialized();
    if (!_available || _dlSessionStartFn == null || _mallocFn == null) return;
    final idPtr = _toNativeUtf8(movieId);
    try {
      _dlSessionStartFn!(idPtr, totalBytes);
    } catch (_) {
    } finally {
      _freeFn?.call(idPtr);
    }
  }

  /// Feeds a downloaded chunk into the Native C++17 engine and returns smooth
  /// real-time progress bar metrics (`%`, ratio, downloaded bytes, total bytes, `MB/s`).
  static CppDownloadProgressMetrics? onDownloadChunk({
    required String movieId,
    required int chunkBytes,
    required int totalBytes,
  }) {
    ensureInitialized();
    if (!_available || _dlSessionOnChunkFn == null || _mallocFn == null) {
      return null;
    }
    final idPtr = _toNativeUtf8(movieId);
    try {
      final outPtr = _dlSessionOnChunkFn!(idPtr, chunkBytes, totalBytes);
      final raw = _fromNativeUtf8AndFree(outPtr);
      if (raw == null || raw.isEmpty) return null;
      final parts = raw.split("|");
      if (parts.length < 5) return null;
      final pct = int.tryParse(parts[0]) ?? 1;
      final ratio = double.tryParse(parts[1]) ?? (pct / 100.0);
      final dlBytes = int.tryParse(parts[2]) ?? 0;
      final totBytes = int.tryParse(parts[3]) ?? totalBytes;
      final speedLabel = parts.sublist(4).join("|");
      return CppDownloadProgressMetrics(
        percent: pct.clamp(1, 100),
        progressRatio: ratio.clamp(0.01, 1.0),
        downloadedBytes: dlBytes,
        totalBytes: totBytes,
        speedLabel: speedLabel,
      );
    } catch (_) {
      return null;
    } finally {
      _freeFn?.call(idPtr);
    }
  }

  /// Finishes and cleans up the Native C++17 download session for `movieId`.
  static void finishDownloadSession(String movieId) {
    ensureInitialized();
    if (!_available || _dlSessionFinishFn == null || _mallocFn == null) return;
    final idPtr = _toNativeUtf8(movieId);
    try {
      _dlSessionFinishFn!(idPtr);
    } catch (_) {
    } finally {
      _freeFn?.call(idPtr);
    }
  }

  /// Boosts OS thread priority for ultra-smooth 60fps video decoding & download I/O.
  static void boostPlaybackPriority({bool highPriority = true}) {
    ensureInitialized();
    if (!_available || _boostPlaybackFn == null) return;
    try {
      _boostPlaybackFn!(highPriority ? 1 : 0);
    } catch (_) {}
  }
}
