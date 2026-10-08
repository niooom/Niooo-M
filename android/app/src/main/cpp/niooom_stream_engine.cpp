#include <jni.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>
#include <unordered_map>
#include <mutex>
#include <sys/resource.h>
#include <unistd.h>
#include <android/log.h>

#define LOG_TAG "NioooMNativeCPP"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

std::mutex g_cache_mutex;
std::unordered_map<std::string, std::string> g_direct_url_cache;

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

// Normalizes a raw Streamtape get_video path into a full HTTPS stream URL
inline std::string normalize_streamtape_url(std::string_view combined) {
    while (!combined.empty() &&
           (combined.front() == ' ' || combined.front() == '\t' ||
            combined.front() == '\n' || combined.front() == '\r')) {
        combined.remove_prefix(1);
    }
    while (!combined.empty() &&
           (combined.back() == ' ' || combined.back() == '\t' ||
            combined.back() == '\n' || combined.back() == '\r')) {
        combined.remove_suffix(1);
    }
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
    if (out.find("&stream=1") == std::string::npos) {
        out += "&stream=1";
    }
    return out;
}

// Evaluates a single JS assignment right-hand-side expression such as:
// '//st' + ('xcdreamtape.com/get_video?id=...').substring(2).substring(1)
// or "/streamtape.c" + '' + ('xcdbom/get_video?id=...').substring(1).substring(2)
std::string evaluate_js_concat_statement(std::string_view stmt) {
    size_t q1_start = stmt.find_first_of("'\"");
    if (q1_start == std::string_view::npos) return {};
    char q1_char = stmt[q1_start];
    size_t q1_end = stmt.find(q1_char, q1_start + 1);
    if (q1_end == std::string_view::npos) return {};

    std::string_view prefix = stmt.substr(q1_start + 1, q1_end - q1_start - 1);

    // Locate parenthesized string ('...') or ("...")
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
                return normalize_streamtape_url(combined);
            }
        }
        paren_pos = stmt.find('(', q2_end + 1);
    }
    return {};
}

// Zero-copy C++17 scanner that extracts the latest valid robotlink / botlink / ideoolink token
std::string extract_streamtape_token_fast(std::string_view html) {
    // Priority order: robotlink first (final live token), then botlink, then norobotlink, then ideoolink
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
            std::string candidate = evaluate_js_concat_statement(stmt);
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

} // namespace

extern "C" {

// Exported for Dart FFI (`dart:ffi`) — extracts direct Streamtape URL in microseconds
__attribute__((visibility("default"))) __attribute__((used))
char* niooom_extract_streamtape_url(const char* html_utf8) {
    if (html_utf8 == nullptr) return nullptr;
    std::string_view html_view(html_utf8);
    if (html_view.empty()) return nullptr;

    std::string extracted = extract_streamtape_token_fast(html_view);
    if (extracted.empty()) return nullptr;

    char* result = static_cast<char*>(std::malloc(extracted.size() + 1));
    if (result != nullptr) {
        std::memcpy(result, extracted.c_str(), extracted.size() + 1);
    }
    return result;
}

// Exported for Dart FFI — extracts clean Streamtape File ID from any URL or ID string
__attribute__((visibility("default"))) __attribute__((used))
char* niooom_extract_file_id(const char* raw_input) {
    if (raw_input == nullptr) return nullptr;
    std::string_view view(raw_input);
    while (!view.empty() && (view.front() == ' ' || view.front() == '\t' || view.front() == '\n' || view.front() == '\r')) {
        view.remove_prefix(1);
    }
    while (!view.empty() && (view.back() == ' ' || view.back() == '\t' || view.back() == '\n' || view.back() == '\r')) {
        view.remove_suffix(1);
    }
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
                std::string id(view.substr(start, end - start));
                char* out = static_cast<char*>(std::malloc(id.size() + 1));
                if (out) std::memcpy(out, id.c_str(), id.size() + 1);
                return out;
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
    char* out = static_cast<char*>(std::malloc(cleaned.size() + 1));
    if (out) std::memcpy(out, cleaned.c_str(), cleaned.size() + 1);
    return out;
}

// Exported for Dart FFI — native C++ in-memory direct URL cache lookup
__attribute__((visibility("default"))) __attribute__((used))
char* niooom_get_cached_direct_url(const char* file_id) {
    if (file_id == nullptr) return nullptr;
    std::lock_guard<std::mutex> lock(g_cache_mutex);
    auto it = g_direct_url_cache.find(file_id);
    if (it == g_direct_url_cache.end() || it->second.empty()) {
        return nullptr;
    }
    const std::string& val = it->second;
    char* out = static_cast<char*>(std::malloc(val.size() + 1));
    if (out) std::memcpy(out, val.c_str(), val.size() + 1);
    return out;
}

// Exported for Dart FFI — store resolved direct URL in native C++ memory cache
__attribute__((visibility("default"))) __attribute__((used))
void niooom_set_cached_direct_url(const char* file_id, const char* direct_url) {
    if (file_id == nullptr || direct_url == nullptr) return;
    std::lock_guard<std::mutex> lock(g_cache_mutex);
    g_direct_url_cache[std::string(file_id)] = std::string(direct_url);
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
    LOGI("Niooo M C++ Playback Engine tuned (tid=%d, nice=%d)", static_cast<int>(tid), target_nice);
    return 1;
}

// JNI Bridge for MainActivity.kt to initialize and tune the C++ engine on app startup
JNIEXPORT jstring JNICALL
Java_com_niooo_m_flutter_1live_1app_MainActivity_initNativeCppEngine(JNIEnv* env, jobject /* this */) {
    niooom_boost_playback_engine(1);
    return env->NewStringUTF("NioooM C++17 Engine Active (-O3 Zero-Copy Extractor + 60FPS Booster)");
}

} // extern "C"
