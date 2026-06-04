// Copied from third_party/tim2tox/example/echo_bot_server.cpp
//   - submodule HEAD at copy time: b7af201b9ff2fb066731a97df7a33715850c0a22
//   - file last touched upstream:  ad29ab6a6f2f4ca312551e1514a51e98b6d273c0
// (toxee-local copy, decoupled from submodule bumps)
// toxee-local modifications:
//   - ECHO_PEER_STATE_DIR env support (default: $(cwd)/build/echo_peer_state)
//   - ECHO_PEER_TOX_ID: dedicated flushed-stdout emission
//   - SIGTERM clean teardown
// Drift check: tool/mcp_test/echo_peer_drift_check.sh
//
// All friend-accept + echo logic is preserved byte-for-byte from upstream
// (only main() differs to thread state-dir + signal handling).

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <atomic>
#include <chrono>
#include <csignal>
#include <filesystem>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

#include <V2TIMManager.h>
#include <V2TIMListener.h>
#include <V2TIMMessage.h>
#include <V2TIMCallback.h>
#include <V2TIMFriendship.h>
#include <V2TIMFriendshipManager.h>

// toxee-local: pull in the FFI C surface so we can call
// `tim2tox_ffi_get_self_tox_id` (returns the underlying Tox hex address, the
// 76-char NoSpam-bearing form). The public V2TIMManager interface only
// exposes `GetLoginUser()`, which is the V2TIM-style userID alias
// ("EchoBotServer") — that's useless to a Tox peer that needs to AddFriend
// by hex address. The FFI helper bridges into
// V2TIMManagerImpl::GetSelfToxAddress() under the hood.
//
// We ALSO use `tim2tox_ffi_init_with_path` + `tim2tox_ffi_login` instead of
// `V2TIMManager::GetInstance()->InitSDK/Login` because the FFI helpers flip
// an internal `MarkInstanceInited(0)` flag that `tim2tox_ffi_get_self_tox_id`
// gates on. Calling InitSDK/Login directly via V2TIMManager works for the
// echo logic but leaves the FFI helper short-circuiting to 0 and we get back
// "EchoBotServer" instead of the real Tox hex. Both paths share the same
// V2TIMManagerImpl singleton, so our listener registration on
// `V2TIMManager::GetInstance()` still wires up correctly.
extern "C" int  tim2tox_ffi_init_with_path(const char* init_path);
extern "C" int  tim2tox_ffi_login(const char* user_id, const char* user_sig);
extern "C" int  tim2tox_ffi_get_self_tox_id(char* buffer, int buffer_len);
extern "C" void tim2tox_ffi_uninit(void);

// --- toxee-local: shutdown signaling ----------------------------------------
static std::atomic<bool> g_should_exit{false};

static void HandleSigterm(int /*sig*/) {
    // Async-signal-safe: just flip the flag. The main loop wakes up at the
    // sleep interval and does the actual SDK teardown on the main thread.
    g_should_exit.store(true);
}
// ---------------------------------------------------------------------------

class SDKListener : public V2TIMSDKListener {
public:
    void OnConnectSuccess() override {
        printf("Server: Online\n");
        fflush(stdout);
    }
    void OnConnectFailed(int error_code, const V2TIMString &error_message) override {
        printf("Server: Connect failed %d: %s\n", error_code, error_message.CString());
        fflush(stdout);
    }
    void OnUserStatusChanged(const V2TIMUserStatusVector &userStatusList) override {
        for (size_t i = 0; i < userStatusList.Size(); ++i) {
            const auto &s = userStatusList[i];
            printf("Server: User %s status changed to %d\n", s.userID.CString(), (int)s.statusType);
        }
        fflush(stdout);
    }
};

class SimpleMsgListener : public V2TIMSimpleMsgListener {
public:
    void OnRecvC2CTextMessage(const V2TIMString &msgID, const V2TIMUserFullInfo &sender,
                              const V2TIMString &text) override {
        // Echo back
        struct NoopSendCb : public V2TIMSendCallback {
            void OnSuccess(const V2TIMMessage&) override {}
            void OnError(int, const V2TIMString&) override {}
            void OnProgress(uint32_t) override {}
        } cb;
        V2TIMManager::GetInstance()->SendC2CTextMessage(text, sender.userID, &cb);
        static unsigned long long counter = 0;
        counter++;
        printf("Message echoed back to friend %s (total echoes: %llu)\n", sender.userID.CString(), counter);
        fflush(stdout);
    }
    void OnRecvC2CCustomMessage(const V2TIMString &msgID, const V2TIMUserFullInfo &sender,
                                const V2TIMBuffer &customData) override {
        // Echo back custom as text-friendly fallback
        struct NoopSendCb : public V2TIMSendCallback {
            void OnSuccess(const V2TIMMessage&) override {}
            void OnError(int, const V2TIMString&) override {}
            void OnProgress(uint32_t) override {}
        } cb;
        V2TIMManager::GetInstance()->SendC2CCustomMessage(customData, sender.userID, &cb);
    }
};

class FriendListener : public V2TIMFriendshipListener {
public:
    void OnFriendApplicationListAdded(const V2TIMFriendApplicationVector &applicationList) override {
        auto *fm = V2TIMManager::GetInstance()->GetFriendshipManager();
        for (size_t i = 0; i < applicationList.Size(); ++i) {
            const auto &app = applicationList[i];
            printf("Server: Received friend application from %s, accepting...\n", app.userID.CString());
            struct AcceptCb : public V2TIMValueCallback<V2TIMFriendOperationResult> {
                void OnSuccess(const V2TIMFriendOperationResult& r) override {
                    printf("Server: Accepted friend %s (code=%d info=%s)\n", r.userID.CString(), r.resultCode, r.resultInfo.CString());
                    fflush(stdout);
                }
                void OnError(int code, const V2TIMString& msg) override {
                    printf("Server: Accept friend error %d: %s\n", code, msg.CString());
                    fflush(stdout);
                }
            } cb;
            fm->AcceptFriendApplication(app, V2TIM_FRIEND_ACCEPT_AGREE_AND_ADD, &cb);
        }
    }
};

// --- toxee-local: resolve the state directory -------------------------------
// Honors ECHO_PEER_STATE_DIR. Defaults to "$(cwd)/build/echo_peer_state".
// Creates the directory if missing. Returns absolute path string.
static std::string ResolveStateDir() {
    const char *env = std::getenv("ECHO_PEER_STATE_DIR");
    std::filesystem::path dir;
    if (env && env[0] != '\0') {
        dir = std::filesystem::path(env);
    } else {
        dir = std::filesystem::current_path() / "build" / "echo_peer_state";
    }
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    if (ec) {
        fprintf(stderr, "echo_peer: failed to create state dir '%s': %s\n",
                dir.string().c_str(), ec.message().c_str());
        // fall through; V2TIM init will fail loudly if dir is unusable
    }
    auto canonical = std::filesystem::weakly_canonical(dir, ec);
    if (ec) {
        return dir.string();
    }
    return canonical.string();
}
// ---------------------------------------------------------------------------

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    // --- toxee-local: SIGTERM/SIGINT handlers -------------------------------
    struct sigaction sa{};
    sa.sa_handler = HandleSigterm;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;  // no SA_RESTART; we want sleeps to be interrupted
    sigaction(SIGTERM, &sa, nullptr);
    sigaction(SIGINT,  &sa, nullptr);
    // ------------------------------------------------------------------------

    SDKListener sdkListener;
    SimpleMsgListener simpleListener;
    FriendListener friendListener;

    // --- toxee-local: resolve state dir + emit it for log forensics ---------
    const std::string state_dir = ResolveStateDir();
    printf("echo_peer: state dir: %s\n", state_dir.c_str());
    fflush(stdout);
    // ------------------------------------------------------------------------

    // --- toxee-local: SDK init via the FFI helper ---------------------------
    // The FFI helper does what `V2TIMManager::GetInstance()->InitSDK(0, cfg)`
    // does PLUS flips an FFI-internal instance-init flag that
    // `tim2tox_ffi_get_self_tox_id` gates on. The Tencent SDK and Tox layer
    // are the same singleton either way, so registering our own listeners on
    // `V2TIMManager::GetInstance()` afterwards still works.
    // initPath = state_dir keeps persistent storage under our scratch dir
    // so multiple peer runs and the surrounding contract smoke don't stomp
    // on any production tim2tox profile under
    // ~/Library/Application Support/tim2tox.
    printf("server: before AddSDKListener\n");
    V2TIMManager::GetInstance()->AddSDKListener(&sdkListener);
    printf("server: after AddSDKListener\n");
    // Register friendship listener to auto-accept friend requests
    V2TIMManager::GetInstance()->GetFriendshipManager()->AddFriendListener(&friendListener);
    int init_ok = tim2tox_ffi_init_with_path(state_dir.c_str());
    printf("server: after tim2tox_ffi_init_with_path=%d\n", init_ok);
    if (!init_ok) {
        fprintf(stderr, "tim2tox_ffi_init_with_path failed\n");
        return 1;
    }

    // Login via the FFI helper (same singleton, but marks the FFI's
    // instance-init bit so `tim2tox_ffi_get_self_tox_id` works below).
    printf("server: before Login\n");
    int login_ok = tim2tox_ffi_login("EchoBotServer", "dummy_sig");
    printf("server: after Login=%d\n", login_ok);
    // ------------------------------------------------------------------------

    // Print user ID (mapped underlying address via V2TIM)
    std::string user_id = V2TIMManager::GetInstance()->GetLoginUser().CString();
    printf("=== Echo Bot Server ===\n");
    printf("User ID: %s\n", user_id.c_str());
    printf("Status: Echoing your messages\n");
    printf("=======================\n");

    // --- toxee-local: dedicated flushed Tox-ID line ------------------------
    // Format: exactly one line `ECHO_PEER_TOX_ID: <hex>\n` followed by an
    // unconditional flush. Consumers (contract smoke, daemon wrapper) match
    // this prefix via `grep -m1 '^ECHO_PEER_TOX_ID:'`.
    //
    // We emit `tim2tox_ffi_get_self_tox_id` (the underlying Tox hex address),
    // NOT `GetLoginUser()` — the latter is the V2TIM userID alias
    // ("EchoBotServer") which a Tox peer can't use to AddFriend. The hex
    // address is the 76-char NoSpam-bearing form for production
    // V2TIMManagerImpl::GetSelfToxAddress(). Phase 1 contract smoke records
    // the observed length so future code can rely on it.
    char tox_id_buf[256] = {0};
    int tox_id_len = tim2tox_ffi_get_self_tox_id(tox_id_buf, (int)sizeof(tox_id_buf));
    if (tox_id_len > 0) {
        printf("ECHO_PEER_TOX_ID: %s\n", tox_id_buf);
    } else {
        // Fallback to the V2TIM userID if the FFI helper isn't available for
        // some reason. The contract smoke will detect this mismatch and fail.
        fprintf(stderr, "echo_peer: WARN tim2tox_ffi_get_self_tox_id returned 0; falling back to GetLoginUser()\n");
        printf("ECHO_PEER_TOX_ID: %s\n", user_id.c_str());
    }
    fflush(stdout);
    // ------------------------------------------------------------------------

    // Register simple message listener
    V2TIMManager::GetInstance()->AddSimpleMsgListener(&simpleListener);

    printf("Server starting...\n");
    printf("Press Ctrl+C to stop\n\n");
    fflush(stdout);

    // Run until SIGTERM/SIGINT flips the flag.
    while (!g_should_exit.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    // --- toxee-local: graceful teardown -------------------------------------
    printf("echo_peer: SIGTERM/SIGINT received, shutting down...\n");
    fflush(stdout);
    // Best-effort Logout (synchronous wait is overkill — UnInitSDK below
    // also flushes persistence). NoopCb is fine; we don't gate exit on it
    // because cfprefsd-style hangs would deadlock the smoke harness.
    struct LogoutCb : public V2TIMCallback {
        void OnSuccess() override {}
        void OnError(int, const V2TIMString&) override {}
    } logoutCb;
    V2TIMManager::GetInstance()->Logout(&logoutCb);
    // tim2tox_ffi_uninit calls UnInitSDK() under the hood and also flips the
    // FFI's MarkInstanceUninited(0) bit, so a future re-init in the same
    // process (the contract smoke does this for the restart-stability check)
    // doesn't see stale "already inited" state.
    tim2tox_ffi_uninit();
    fflush(stdout);
    fflush(stderr);
    return 0;
    // ------------------------------------------------------------------------
}
