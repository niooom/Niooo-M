#include <jni.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <string>
#include <string_view>
#include <unordered_map>
#include <mutex>
#include <algorithm>
#include <sys/resource.h>
#include <unistd.h>
#include <android/log.h>

#define LOG_TAG "NioooMNativeCPP"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

// ============================================================================
// 1. VIDEO PLAYBACK ENGINE STATE (STRICTLY FOR VIDEO STREAMING ONLY)
// ============================================================================
std::mutex g_cache_mutex;
std::unordered_map<std::string, std::string> g_direct_url_cache;

// ============================================================================
// 2. C++17 HIGH-SPEED API DOWNLOAD & REAL-TIME PROGRESS ENGINE STATE
//    (STRICTLY FOR API KEY `download_url` DOWNLOADING ONLY)
// ============================================================================
struct CppDownloadSession {
    int64_t downloaded_bytes = 0;
    int64_t total_bytes = 0;
    int64_t last_sample_bytes = 0;
    double ema_speed_bps = 0.0;
    std::chrono::steady_clock::time_point start_time;
    std::chrono::steady_clock::time_point last_sample_time;
};

std::mutex g_download_mutex;
std::unordered_map<std::string, CppDownloadSession> g_download_sessions;

inline char* alloc_c_string(std::string_view sv) {
    char* out = static_cast<char*>(std::malloc(sv.size() + 1));
    if (out != nullptr) {
        if (!sv.empty()) {
            std::memcpy(out, sv.data(), sv.size());
        }
        out[sv.size()] = '\0';
    }
    return out;
}

inline std::string_view trim_view(std::string_view sv) {
    while (!sv.empty() &&
           (sv.front() == ' ' || sv.front() == '\t' ||
            sv.front() == '\n' || sv.front() == '\r')) {
        sv.remove_prefix(1);
    }
    while (!sv.empty() &&
           (sv.back() == ' ' || sv.back() == '\t' ||
            sv.back() == '\n' || sv.back() == '\r')) {
        sv.remove_suffix(1);
    }
    return sv;
}

// Ultra-fast helper to sum all chained .substring(N) calls in Streamtape JS tokens
inline size_t parse_chained_substrings(std::string_view expr) {
    size_t total_skip = 0;
    size_t pos = 0;
    constexpr std::string_view kSubToken = ".substring(";
    while ((pos = expr.find(kSubToken, pos)) != std::string_view::npos) {
        pos += kSubToken.size();
        size_t num_val = 0;
        bool has_digits = false;
        while (pos < expr.size() && expr[pos] >= '0' && expr[pos] <= '9') {
            num_val = (num_val * 10) + static_cast<size_t>(expr[pos] - '0');
            has_digits = true;
            ++pos;
        }
        if (has_digits) {
            total_skip += num_val;
        }
    }
    return total_skip;
}

// Normalizes a raw Streamtape get_video path into a full HTTPS URL
// - For Video Playback: appends `&stream=1`
// - For API Download Link: appends `&dl=1` (never `&stream=1`)
inline std::string normalize_streamtape_url(std::string_view combined, bool for_download) {
    combined = trim_view(combined);
    if (combined.empty()) return {};

    std::string out;
    out.reserve(combined.size() + 24);
    if (combined.rfind("https://", 0) == 0 || combined.rfind("http://", 0) == 0) {
        out.assign(combined.data(), combined.size());
    } else if (combined.rfind("//", 0) == 0) {
        out = "https:";
        out.append(combined.data(), combined.size());
    } else if (combined.rfind("/", 0) == 0) {
        out = "https:/";
        out.append(combined.data(), combined.size());
    } else {
        out = "https://";
        out.append(combined.data(), combined.size());
    }

    if (for_download) {
        // Ensure download link uses `&dl=1` and NEVER `&stream=1`
        size_t stream_pos = out.find("&stream=1");
        if (stream_pos != std::string::npos) {
            out.replace(stream_pos, 9, "&dl=1");
        } else if (out.find("&dl=1") == std::string::npos) {
            out += "&dl=1";
        }
    } else {
        if (out.find("&stream=1") == std::string::npos) {
            out += "&stream=1";
        }
    }
    return out;
}

// Evaluates a single JS assignment right-hand-side expression such as:
// '//st' + ('xcdreamtape.com/get_video?id=...').substring(2).substring(1)
std::string evaluate_js_concat_statement(std::string_view stmt, bool for_download) {
    size_t q1_start = stmt.find_first_of("'\"");
    if (q1_start == std::string_view::npos) return {};
    char q1_char = stmt[q1_start];
    size_t q1_end = stmt.find(q1_char, q1_start + 1);
    if (q1_end == std::string_view::npos) return {};

    std::string_view prefix = stmt.substr(q1_start + 1, q1_end - q1_start - 1);

    size_t paren_pos = stmt.find('(', q1_end + 1);
    while (paren_pos != std::string_view::npos && paren_pos + 2 < stmt.size()) {
        size_t q2_start = stmt.find_first_of("'\"", paren_pos + 1);
        if (q2_start == std::string_view::npos) break;
        char q2_char = stmt[q2_start];
        size_t q2_end = stmt.find(q2_char, q2_start + 1);
        if (q2_end == std::string_view::npos) break;

        std::string_view raw_suffix = stmt.substr(q2_start + 1, q2_end - q2_start - 1);
        std::string_view tail = stmt.substr(q2_end + 1);
        size_t skip = parse_chained_substrings(tail);

        if (skip < raw_suffix.size()) {
            std::string combined;
            combined.reserve(prefix.size() + (raw_suffix.size() - skip));
            combined.append(prefix.data(), prefix.size());
            combined.append(raw_suffix.data() + skip, raw_suffix.size() - skip);
            if (combined.find("get_video?") != std::string::npos &&
                combined.find("token=") != std::string::npos) {
                return normalize_streamtape_url(combined, for_download);
            }
        }
        paren_pos = stmt.find('(', q2_end + 1);
    }
    return {};
}

// Zero-copy C++17 scanner for VIDEO PLAYBACK ONLY (`&stream=1`)
std::string extract_streamtape_token_fast(std::string_view html) {
    constexpr std::string_view kRobotMarkers[] = {
        "getElementById('robotlink').innerHTML",
        "getElementById(\"robotlink\").innerHTML",
        "getElementById('botlink').innerHTML",
        "getElementById(\"botlink\").innerHTML",
        "getElementById('norobotlink').innerHTML",
        "getElementById(\"norobotlink\").innerHTML",
        "getElementById('ideoolink').innerHTML",
        "getElementById(\"ideoolink\").innerHTML"
    };

    for (std::string_view marker : kRobotMarkers) {
        std::string last_valid_for_marker;
        size_t search_pos = 0;
        while ((search_pos = html.find(marker, search_pos)) != std::string_view::npos) {
            size_t line_start = search_pos + marker.size();
            size_t semi_pos = html.find(';', line_start);
            size_t newline_pos = html.find('\n', line_start);
            size_t end_pos = semi_pos;
            if (newline_pos != std::string_view::npos && (end_pos == std::string_view::npos || newline_pos < end_pos)) {
                end_pos = newline_pos;
            }
            if (end_pos == std::string_view::npos || (end_pos - line_start) > 1024) {
                end_pos = std::min(html.size(), line_start + 512);
            }

            std::string_view stmt = html.substr(line_start, end_pos - line_start);
            std::string candidate = evaluate_js_concat_statement(stmt, false);
            if (!candidate.empty()) {
                last_valid_for_marker = std::move(candidate);
            }
            search_pos = end_pos;
        }
        if (!last_valid_for_marker.empty()) {
            return last_valid_for_marker;
        }
    }

    return {};
}

// Zero-copy C++17 scanner strictly for API Key `download_url` page (`#norobotlink` / `#ideoooolink` + `&dl=1`)
std::string extract_api_download_binary_fast(std::string_view html) {
    constexpr std::string_view kDownloadMarkers[] = {
        "getElementById('norobotlink').innerHTML",
        "getElementById(\"norobotlink\").innerHTML",
        "getElementById('ideoooolink').innerHTML",
        "getElementById(\"ideoooolink\").innerHTML",
        "getElementById('robotlink').innerHTML",
        "getElementById(\"robotlink\").innerHTML"
    };

    for (std::string_view marker : kDownloadMarkers) {
        std::string last_valid;
        size_t search_pos = 0;
        while ((search_pos = html.find(marker, search_pos)) != std::string_view::npos) {
            size_t line_start = search_pos + marker.size();
            size_t semi_pos = html.find(';', line_start);
            size_t newline_pos = html.find('\n', line_start);
            size_t end_pos = semi_pos;
            if (newline_pos != std::string_view::npos &&
                (end_pos == std::string_view::npos || newline_pos < end_pos)) {
                end_pos = newline_pos;
            }
            if (end_pos == std::string_view::npos || (end_pos - line_start) > 1024) {
                end_pos = std::min(html.size(), line_start + 512);
            }

            std::string_view stmt = html.substr(line_start, end_pos - line_start);
            std::string candidate = evaluate_js_concat_statement(stmt, true);
            if (!candidate.empty()) {
                last_valid = std::move(candidate);
            }
            search_pos = end_pos;
        }
        if (!last_valid.empty()) {
            return last_valid;
        }
    }
    return {};
}

} // namespace

extern "C" {

// ============================================================================
// SECTION A: VIDEO PLAYBACK FFI EXPORTS (FOR VIDEO STREAMING ONLY)
// ============================================================================

// Exported for Dart FFI (`dart:ffi`) — extracts direct Streamtape playback URL (`&stream=1`)
__attribute__((visibility("default"))) __attribute__((used))
char* niooom_extract_streamtape_url(const char* html_utf8) {
    if (html_utf8 == nullptr) return nullptr;
    std::string_view html_view(html_utf8);
    if (html_view.empty()) return nullptr;

    std::string extracted = extract_streamtape_token_fast(html_view);
    if (extracted.empty()) return nullptr;

    return alloc_c_string(extracted);
}

// Exported for Dart FFI — extracts clean Streamtape File ID from any URL or ID string
__attribute__((visibility("default"))) __attribute__((used))
char* niooom_extract_file_id(const char* raw_input) {
    if (raw_input == nullptr) return nullptr;
    std::string_view view = trim_view(std::string_view(raw_input));
    if (view.empty()) return nullptr;

    constexpr std::string_view kMarkers[] = {
        "streamtape.com/e/",
        "streamtape.com/v/",
        "streamtape.to/e/",
        "streamtape.to/v/",
        "strcloud.in/e/",
        "strcloud.in/v/"
    };

    for (std::string_view marker : kMarkers) {
        size_t pos = view.find(marker);
        if (pos != std::string_view::npos) {
            size_t start = pos + marker.size();
            size_t end = start;
            while (end < view.size()) {
                char c = view[end];
                bool valid = (c >= 'a' && c <= 'z') ||
                             (c >= 'A' && c <= 'Z') ||
                             (c >= '0' && c <= '9') ||
                             c == '_' || c == '-';
                if (!valid) break;
                ++end;
            }
            if (end > start) {
                return alloc_c_string(view.substr(start, end - start));
            }
        }
    }

    std::string cleaned;
    cleaned.reserve(view.size());
    for (char c : view) {
        if ((c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') ||
            c == '_' || c == '-') {
            cleaned.push_back(c);
        }
    }
    if (cleaned.empty()) return nullptr;
    return alloc_c_string(cleaned);
}

// Exported for Dart FFI — native C++ in-memory direct stream URL cache lookup (Video Player ONLY)
__attribute__((visibility("default"))) __attribute__((used))
char* niooom_get_cached_direct_url(const char* file_id) {
    if (file_id == nullptr) return nullptr;
    std::lock_guard<std::mutex> lock(g_cache_mutex);
    auto it = g_direct_url_cache.find(file_id);
    if (it == g_direct_url_cache.end() || it->second.empty()) {
        return nullptr;
    }
    return alloc_c_string(it->second);
}

// Exported for Dart FFI — store resolved direct stream URL in native C++ memory cache (Video Player ONLY)
__attribute__((visibility("default"))) __attribute__((used))
void niooom_set_cached_direct_url(const char* file_id, const char* direct_url) {
    if (file_id == nullptr || direct_url == nullptr) return;
    std::lock_guard<std::mutex> lock(g_cache_mutex);
    g_direct_url_cache[std::string(file_id)] = std::string(direct_url);
}

// ============================================================================
// SECTION B: C++17 HIGH-SPEED API DOWNLOAD & REAL-TIME PROGRESS ENGINE EXPORTS
//            (STRICTLY FOR API KEY `download_url` DOWNLOADING ONLY)
// ============================================================================

// Validates & prepares the main `download_url` coming from the API key.
// Strictly ensures `/e/` embed links or `&stream=1` playback links are NEVER used for download.
__attribute__((visibility("default"))) __attribute__((used))
char* niooom_prepare_api_download_url(const char* api_download_url) {
    if (api_download_url == nullptr) return nullptr;
    std::string_view raw = trim_view(std::string_view(api_download_url));
    if (raw.empty()) return nullptr;

    std::string url(raw);
    if (url.rfind("http://", 0) != 0 && url.rfind("https://", 0) != 0) {
        if (url.rfind("//", 0) == 0) {
            url = "https:" + url;
        } else {
            url = "https://" + url;
        }
    }

    // Never allow `/e/` embed stream path in a download URL; convert to `/v/` download path if needed
    size_t embed_pos = url.find("streamtape.com/e/");
    if (embed_pos != std::string::npos) {
        url.replace(embed_pos, 17, "streamtape.com/v/");
    }

    // Never allow `&stream=1` video playback parameter in a download URL
    size_t stream_param = url.find("&stream=1");
    if (stream_param != std::string::npos) {
        url.replace(stream_param, 9, "&dl=1");
    }

    return alloc_c_string(url);
}

// Parses the HTML of the API `download_url` page in C++17 (-O3) to get the `&dl=1` binary download link.
// Never touches `/e/` or the video player's direct stream cache.
__attribute__((visibility("default"))) __attribute__((used))
char* niooom_extract_api_download_binary_link(
    const char* download_page_html,
    const char* fallback_api_download_url
) {
    if (download_page_html != nullptr) {
        std::string_view html_view(download_page_html);
        if (!html_view.empty()) {
            std::string dl_link = extract_api_download_binary_fast(html_view);
            if (!dl_link.empty()) {
                return alloc_c_string(dl_link);
            }
        }
    }
    if (fallback_api_download_url != nullptr) {
        return niooom_prepare_api_download_url(fallback_api_download_url);
    }
    return nullptr;
}

// Starts a high-speed C++17 download session for `movie_id`, boosting thread priority
// and initializing `std::chrono::steady_clock` speed & progress tracking.
__attribute__((visibility("default"))) __attribute__((used))
void niooom_download_session_start(const char* movie_id, int64_t total_bytes) {
    if (movie_id == nullptr) return;
    pid_t tid = gettid();
    setpriority(PRIO_PROCESS, static_cast<id_t>(tid), -10);

    std::lock_guard<std::mutex> lock(g_download_mutex);
    auto now = std::chrono::steady_clock::now();
    CppDownloadSession session;
    session.downloaded_bytes = 0;
    session.total_bytes = (total_bytes > 0) ? total_bytes : (250LL * 1024LL * 1024LL);
    session.last_sample_bytes = 0;
    session.ema_speed_bps = 0.0;
    session.start_time = now;
    session.last_sample_time = now;
    g_download_sessions[std::string(movie_id)] = session;
}

// Processes a downloaded byte chunk in C++17 and returns a compact real-time metrics string:
// Format: "pct_int|progress_float|downloaded_bytes|total_bytes|speed_label"
// Example: "48|0.4825|284164096|589618080|16.4 MB/s"
__attribute__((visibility("default"))) __attribute__((used))
char* niooom_download_session_on_chunk(
    const char* movie_id,
    int64_t chunk_bytes,
    int64_t total_bytes
) {
    if (movie_id == nullptr) return nullptr;
    std::lock_guard<std::mutex> lock(g_download_mutex);

    std::string key(movie_id);
    auto now = std::chrono::steady_clock::now();
    auto it = g_download_sessions.find(key);
    if (it == g_download_sessions.end()) {
        CppDownloadSession init_s;
        init_s.downloaded_bytes = 0;
        init_s.total_bytes = (total_bytes > 0) ? total_bytes : (250LL * 1024LL * 1024LL);
        init_s.last_sample_bytes = 0;
        init_s.ema_speed_bps = 0.0;
        init_s.start_time = now;
        init_s.last_sample_time = now;
        it = g_download_sessions.emplace(key, init_s).first;
    }

    CppDownloadSession& s = it->second;
    if (total_bytes > 0) {
        s.total_bytes = total_bytes;
    }
    if (chunk_bytes > 0) {
        s.downloaded_bytes += chunk_bytes;
    }
    if (s.total_bytes > 0 && s.downloaded_bytes > s.total_bytes) {
        s.total_bytes = s.downloaded_bytes;
    }

    double elapsed_ms = std::chrono::duration<double, std::milli>(now - s.last_sample_time).count();
    if (elapsed_ms >= 80.0) {
        int64_t delta_bytes = s.downloaded_bytes - s.last_sample_bytes;
        double instant_bps = (elapsed_ms > 0.0) ? (static_cast<double>(delta_bytes) * 1000.0 / elapsed_ms) : 0.0;
        if (instant_bps > 0.0) {
            if (s.ema_speed_bps <= 1.0) {
                s.ema_speed_bps = instant_bps;
            } else {
                s.ema_speed_bps = (0.35 * instant_bps) + (0.65 * s.ema_speed_bps);
            }
        }
        s.last_sample_bytes = s.downloaded_bytes;
        s.last_sample_time = now;
    }

    double effective_bps = s.ema_speed_bps;
    if (effective_bps <= 1024.0) {
        double total_elapsed_sec = std::chrono::duration<double>(now - s.start_time).count();
        if (total_elapsed_sec > 0.05) {
            effective_bps = static_cast<double>(s.downloaded_bytes) / total_elapsed_sec;
        }
    }

    double ratio = (s.total_bytes > 0)
        ? (static_cast<double>(s.downloaded_bytes) / static_cast<double>(s.total_bytes))
        : 0.0;
    if (ratio < 0.01) ratio = 0.01;
    if (ratio > 1.0) ratio = 1.0;

    int pct = static_cast<int>(ratio * 100.0 + 0.5);
    if (pct < 1) pct = 1;
    if (pct > 100) pct = 100;

    char speed_buf[64];
    if (effective_bps >= 1024.0 * 1024.0) {
        std::snprintf(
            speed_buf,
            sizeof(speed_buf),
            "%.1f MB/s · C++ Engine",
            effective_bps / (1024.0 * 1024.0)
        );
    } else if (effective_bps >= 1024.0) {
        std::snprintf(
            speed_buf,
            sizeof(speed_buf),
            "%d KB/s · C++ Engine",
            static_cast<int>(effective_bps / 1024.0)
        );
    } else {
        std::snprintf(speed_buf, sizeof(speed_buf), "C++ Fast Stream");
    }

    char out_buf[256];
    std::snprintf(
        out_buf,
        sizeof(out_buf),
        "%d|%.4f|%lld|%lld|%s",
        pct,
        ratio,
        static_cast<long long>(s.downloaded_bytes),
        static_cast<long long>(s.total_bytes),
        speed_buf
    );

    return alloc_c_string(out_buf);
}

// Finishes and cleans up a C++17 download session
__attribute__((visibility("default"))) __attribute__((used))
void niooom_download_session_finish(const char* movie_id) {
    if (movie_id == nullptr) return;
    std::lock_guard<std::mutex> lock(g_download_mutex);
    g_download_sessions.erase(std::string(movie_id));
}

// Exported for Dart FFI — frees strings allocated by the C++ engine
__attribute__((visibility("default"))) __attribute__((used))
void niooom_free_string(char* ptr) {
    if (ptr != nullptr) {
        std::free(ptr);
    }
}

// Exported for Dart FFI & JNI — boosts Android thread priority & playback pipeline for smooth 60fps video
__attribute__((visibility("default"))) __attribute__((used))
int32_t niooom_boost_playback_engine(int32_t enable_high_priority) {
    pid_t tid = gettid();
    int target_nice = (enable_high_priority != 0) ? -8 : 0;
    setpriority(PRIO_PROCESS, static_cast<id_t>(tid), target_nice);
    LOGI("Niooo M C++ Engine tuned (tid=%d, nice=%d)", static_cast<int>(tid), target_nice);
    return 1;
}

// JNI Bridge for MainActivity.kt to initialize and tune the C++ engine on app startup
JNIEXPORT jstring JNICALL
Java_com_niooo_m_flutter_1live_1app_MainActivity_initNativeCppEngine(JNIEnv* env, jobject /* this */) {
    niooom_boost_playback_engine(1);
    return env->NewStringUTF("NioooM C++17 Engine Active (-O3 Playback + API Download Engine)");
}

} // extern "C"
