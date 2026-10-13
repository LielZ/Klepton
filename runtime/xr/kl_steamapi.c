// libsteam_api.so for an Android guest — see kl_steamapi.h for why this is a
// replacement and where its answers come from.
#include <limits.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "kl_steamapi.h"
#include "klepton.h"
#include "kl_env.h"
#include "kl_jni.h"
#include "kl_driver.h"

#define STEAM_LOG(...) fprintf(stderr, "  [steam] " __VA_ARGS__)

// The offline user. Without anything else it is the one kl_lx_steam.c answers
// with: universe public, individual account, account number 1.
//
// KL_STEAM_ID=<64-bit id> - this installation's own. A game that keys an account
// of its own on the Steam id needs one: Walkabout Mini Golf signs in to its
// backend with "<steam id>Steam" and nothing else, so one id for everybody
// would be one account, and one set of cloud profiles, for every player of this
// runtime. The start window makes a number per installation and hands it over
// (KleptonPlayer, as KL_PLAT_USER_ID for the Meta build of the same game). It
// is an id of this runtime's making, not the player's Steam account: nothing
// here could prove that one to anybody.
#define KLS_STEAM_ID_FIXED  0x0110000100000001ull
static uint64_t kls_steam_id(void) {
    static uint64_t id;
    if (!id) {
        const char *e = kl_env_str("KL_STEAM_ID", NULL);
        uint64_t v = e && *e ? strtoull(e, NULL, 10) : 0;
        // Only an individual account in the public universe, with an account number.
        if ((v >> 32) == 0x01100001u && (uint32_t)v != 0) {
            id = v;
            STEAM_LOG("offline user has this installation's own id (KL_STEAM_ID)\n");
        } else {
            id = KLS_STEAM_ID_FIXED;
        }
    }
    return id;
}
#define KLS_STEAM_ID  (kls_steam_id())

// ---- which functions the guest reached for ----
enum { KLS_MAX = 1024 };
static struct { const char *name; unsigned calls; int served; } g_fn[KLS_MAX];
static unsigned g_nfn;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

static int kls_slot(const char *name) {
    pthread_mutex_lock(&g_lock);
    int found = -1;
    for (unsigned i = 0; i < g_nfn; i++)
        if (strcmp(g_fn[i].name, name) == 0) { found = (int)i; break; }
    if (found < 0 && g_nfn < KLS_MAX) {
        g_fn[g_nfn].name = strdup(name);
        found = (int)g_nfn++;
    }
    pthread_mutex_unlock(&g_lock);
    return found;
}

// ---- the app, and what Steam confirmed for it ----
// The app id is the game's own, by target: there is no steam_appid.txt in an
// Android depot, the Steam on the headset knows which app it started.
static uint32_t kls_appid(void) {
    static uint32_t id;
    if (!id) {
        const char *t = kl_driver_target_name();
        id = kl_env_uint("KL_STEAM_APPID", t && strcmp(t, "walkabout") == 0 ? 1408230u : 0u);
        STEAM_LOG("app id %u\n", id);
    }
    return id;
}

// klepton-entitlements.txt, as the Mac app writes it for a game bought on Steam:
//   app_id 1408230
//   verified 2026-10-13T00:12:00Z
//   sku 1791210          <- one line per add-on (a Steam app id) the account holds
// The same file and format the Meta stand-in reads (klplat_load_entitlements);
// a list written for another app id is not ours and counts as no list.
enum { KLS_DLC_MAX = 512 };
static uint32_t g_dlc[KLS_DLC_MAX];
static int g_ndlc;

static void kls_load_entitlements(void) {
    static long long seen_mtime = -1, seen_size = -1;
    const char *root = kl_jni_files_dir();
    char path[PATH_MAX];
    struct stat st;
    if (!root || !root[0] ||
        snprintf(path, sizeof path, "%s/klepton-entitlements.txt", root) >= (int)sizeof path ||
        stat(path, &st) != 0 || !S_ISREG(st.st_mode)) {
        if (seen_mtime != 0 || seen_size != 0)
            STEAM_LOG("no klepton-entitlements.txt in %s — no add-ons reported\n", root ? root : "(no files dir)");
        seen_mtime = 0; seen_size = 0;
        g_ndlc = 0;
        return;
    }
    if ((long long)st.st_mtime == seen_mtime && (long long)st.st_size == seen_size) return;
    FILE *f = fopen(path, "r");
    if (!f) return;
    g_ndlc = 0;
    char line[256], verified[64] = "";
    unsigned long app = 0;
    while (fgets(line, sizeof line, f)) {
        size_t n = strlen(line);
        while (n && (line[n - 1] == '\n' || line[n - 1] == '\r' || line[n - 1] == ' ')) line[--n] = 0;
        if (strncmp(line, "app_id ", 7) == 0) app = strtoul(line + 7, NULL, 10);
        if (strncmp(line, "verified ", 9) == 0) snprintf(verified, sizeof verified, "%s", line + 9);
        if (strncmp(line, "sku ", 4) != 0 || !line[4]) continue;
        char *end = NULL;
        unsigned long id = strtoul(line + 4, &end, 10);
        if (!id || (end && *end) || id > 0xfffffffful || g_ndlc >= KLS_DLC_MAX) continue;
        g_dlc[g_ndlc++] = (uint32_t)id;
    }
    fclose(f);
    seen_mtime = (long long)st.st_mtime; seen_size = (long long)st.st_size;
    if (app != kls_appid()) {
        STEAM_LOG("klepton-entitlements.txt is for app %lu, not %u — no add-ons reported\n", app, kls_appid());
        g_ndlc = 0;
        return;
    }
    STEAM_LOG("add-ons confirmed by Steam: %d (verified %s)\n", g_ndlc, verified[0] ? verified : "at an unknown time");
}

static int kls_owns(uint32_t app) {
    kls_load_entitlements();
    for (int i = 0; i < g_ndlc; i++) if (g_dlc[i] == app) return 1;
    return 0;
}

// ---- answers ----
// Flat functions take the interface pointer first; it is one of our tokens and
// carries nothing. Narrow results are returned in full registers.
static char g_token[16];   // every interface "object": never dereferenced by Steamworks.NET
static void *kls_iface(void) { return g_token; }

static uint64_t kls_true(void)  { return 1; }
static uint64_t kls_one(void)   { return 1; }
static uint64_t kls_zero(void)  { return 0; }
static void    *kls_token(void) { return kls_iface(); }
static void     kls_void(void)  { }

static uint64_t kls_Init(void) {
    STEAM_LOG("SteamAPI_Init -> true: Steam stands in as one offline user (see kl_steamapi.h)\n");
    kls_load_entitlements();
    return 1;
}
// ESteamAPIInitResult: 0 is k_ESteamAPIInitResult_OK.
static uint64_t kls_InitEx(const char *versions, char *err) {
    (void)versions;
    if (err) err[0] = 0;
    STEAM_LOG("SteamInternal_SteamAPI_Init -> OK: Steam stands in as one offline user (see kl_steamapi.h)\n");
    kls_load_entitlements();
    return 0;
}

static uint32_t kls_Utils_GetAppID(void *s)          { (void)s; return kls_appid(); }
static uint32_t kls_Utils_GetServerRealTime(void *s) { (void)s; return (uint32_t)time(NULL); }
static const char *kls_Utils_GetIPCountry(void *s) {
    (void)s;
    static char lang[16], country[16];
    kl_jni_locale_parts(lang, sizeof lang, country, sizeof country);
    return country[0] ? country : "US";
}
// Steam's names for the languages it knows; a game compares these as text.
static const char *kls_language(void *s) {
    (void)s;
    static const char *answer;
    if (answer) return answer;
    static const struct { const char *iso, *steam; } map[] = {
        {"de", "german"}, {"fr", "french"}, {"ja", "japanese"}, {"ko", "koreana"}, {"zh", "schinese"},
        {"es", "spanish"}, {"it", "italian"}, {"pt", "portuguese"}, {"ru", "russian"}, {"nl", "dutch"},
        {"pl", "polish"}, {"sv", "swedish"}, {"da", "danish"}, {"fi", "finnish"}, {"no", "norwegian"},
        {"tr", "turkish"}, {"cs", "czech"}, {"hu", "hungarian"}, {"uk", "ukrainian"},
    };
    char lang[16] = "", country[16] = "";
    kl_jni_locale_parts(lang, sizeof lang, country, sizeof country);
    answer = "english";
    for (size_t i = 0; i < sizeof map / sizeof map[0]; i++)
        if (strncasecmp(lang, map[i].iso, 2) == 0) { answer = map[i].steam; break; }
    answer = kl_env_str("KL_STEAM_LANGUAGE", answer);
    STEAM_LOG("language -> %s\n", answer);
    return answer;
}

static uint64_t kls_User_GetSteamID(void *s) { (void)s; return KLS_STEAM_ID; }
static const char *kls_Friends_GetPersonaName(void *s) { (void)s; return kl_env_str("KL_STEAM_NAME", "Player"); }

// ISteamApps — the ownership half. The game itself was delivered by Steam to the
// account that owns it; add-ons are what the list says.
static uint64_t kls_Apps_BIsSubscribedApp(void *s, uint32_t app) {
    (void)s;
    int yes = app == kls_appid() || kls_owns(app);
    static uint32_t said[KLS_DLC_MAX]; static int nsaid;
    int known = 0;
    for (int i = 0; i < nsaid; i++) if (said[i] == app) { known = 1; break; }
    if (!known && nsaid < KLS_DLC_MAX) {
        said[nsaid++] = app;
        STEAM_LOG("add-on %u -> %s\n", app, yes ? "owned (confirmed by Steam)" : "not owned");
    }
    return (uint64_t)yes;
}
static int32_t kls_Apps_GetDLCCount(void *s) { (void)s; kls_load_entitlements(); return g_ndlc; }
static uint64_t kls_Apps_BGetDLCDataByIndex(void *s, int32_t i, uint32_t *app, uint8_t *available, char *name, int32_t cap) {
    (void)s;
    kls_load_entitlements();
    if (i < 0 || i >= g_ndlc) return 0;
    if (app) *app = g_dlc[i];
    if (available) *available = 1;
    if (name && cap > 0) snprintf(name, (size_t)cap, "%u", g_dlc[i]);
    return 1;
}
static uint64_t kls_Apps_GetAppOwner(void *s) { (void)s; return KLS_STEAM_ID; }

// bool GetNextCallback / GetAPICallResult: there is never one.
static uint64_t kls_GetAPICallResult(int32_t pipe, uint64_t call, void *cb, int32_t size, int32_t expected, uint8_t *failed) {
    (void)pipe; (void)call; (void)cb; (void)size; (void)expected;
    if (failed) *failed = 1;
    return 0;
}

static const struct { const char *name; void *fn; } g_impl[] = {
    {"SteamAPI_Init",                         (void *)kls_Init},
    {"SteamAPI_InitSafe",                     (void *)kls_Init},
    {"SteamInternal_SteamAPI_Init",           (void *)kls_InitEx},
    {"SteamAPI_RestartAppIfNecessary",        (void *)kls_zero},
    {"SteamAPI_IsSteamRunning",               (void *)kls_true},
    {"SteamAPI_GetHSteamPipe",                (void *)kls_one},
    {"SteamAPI_GetHSteamUser",                (void *)kls_one},
    {"SteamInternal_CreateInterface",         (void *)kls_token},
    {"SteamInternal_FindOrCreateUserInterface", (void *)kls_token},
    // The callback pump: nothing is ever queued, so running it is nothing.
    {"SteamAPI_ManualDispatch_Init",          (void *)kls_void},
    {"SteamAPI_ManualDispatch_RunFrame",      (void *)kls_void},
    {"SteamAPI_ManualDispatch_FreeLastCallback", (void *)kls_void},
    {"SteamAPI_RunCallbacks",                 (void *)kls_void},
    {"SteamAPI_ReleaseCurrentThreadMemory",   (void *)kls_void},
    {"SteamAPI_Shutdown",                     (void *)kls_void},
    {"SteamAPI_ISteamClient_SetWarningMessageHook", (void *)kls_void},
    {"SteamAPI_ManualDispatch_GetNextCallback", (void *)kls_zero},
    {"SteamAPI_ManualDispatch_GetAPICallResult", (void *)kls_GetAPICallResult},
    {"SteamAPI_ISteamClient_GetISteamGenericInterface", (void *)kls_token},
    {"SteamAPI_ISteamUtils_GetAppID",         (void *)kls_Utils_GetAppID},
    {"SteamAPI_ISteamUtils_GetServerRealTime", (void *)kls_Utils_GetServerRealTime},
    {"SteamAPI_ISteamUtils_GetIPCountry",     (void *)kls_Utils_GetIPCountry},
    {"SteamAPI_ISteamUtils_GetConnectedUniverse", (void *)kls_one},        // k_EUniversePublic
    {"SteamAPI_ISteamUtils_GetSteamUILanguage", (void *)kls_language},
    {"SteamAPI_ISteamUser_GetSteamID",        (void *)kls_User_GetSteamID},
    {"SteamAPI_ISteamUser_GetHSteamUser",     (void *)kls_one},
    {"SteamAPI_ISteamUser_BLoggedOn",         (void *)kls_true},
    {"SteamAPI_ISteamFriends_GetPersonaName", (void *)kls_Friends_GetPersonaName},
    {"SteamAPI_ISteamApps_BIsSubscribed",     (void *)kls_true},
    {"SteamAPI_ISteamApps_BIsSubscribedApp",  (void *)kls_Apps_BIsSubscribedApp},
    {"SteamAPI_ISteamApps_BIsDlcInstalled",   (void *)kls_Apps_BIsSubscribedApp},
    {"SteamAPI_ISteamApps_BIsAppInstalled",   (void *)kls_Apps_BIsSubscribedApp},
    {"SteamAPI_ISteamApps_GetDLCCount",       (void *)kls_Apps_GetDLCCount},
    {"SteamAPI_ISteamApps_BGetDLCDataByIndex", (void *)kls_Apps_BGetDLCDataByIndex},
    {"SteamAPI_ISteamApps_GetAppOwner",       (void *)kls_Apps_GetAppOwner},
    {"SteamAPI_ISteamApps_GetCurrentGameLanguage", (void *)kls_language},
    {"SteamAPI_ISteamApps_GetAvailableGameLanguages", (void *)kls_language},
};

// Everything else: named once, answered 0 — "false", "no handle", "invalid call"
// and an empty count all at once, which is the offline answer to most of the API.
static uint64_t kls_unserved(const char *name) {
    int s = kls_slot(name);
    if (s >= 0 && g_fn[s].calls++ == 0) STEAM_LOG("%s: not implemented — answering 0\n", name);
    return 0;
}

static const char g_handle[] = "klepton-steam-api";
static int g_in_use;

int kl_steamapi_in_use(void) { return __atomic_load_n(&g_in_use, __ATOMIC_ACQUIRE); }

// Does this copy of the game carry Steam's library? Asked of the files, because
// it has to be answerable before the guest has loaded anything: the start
// window's controller panel reads its numbers when the app opens.
int kl_steamapi_shipped(void) {
    static int known = -1;
    if (known >= 0) return known;
    char exe[PATH_MAX], path[PATH_MAX + 64];
    uint32_t n = sizeof exe;
    // An app bundle carries the guest's libraries as frameworks beside the
    // executable; this one is there although nothing loads it.
    if (_NSGetExecutablePath(exe, &n) == 0) {
        char *slash = strrchr(exe, '/');
        if (slash) {
            *slash = 0;
            snprintf(path, sizeof path, "%s/Frameworks", exe);
            if (access(path, F_OK) == 0) {
                snprintf(path, sizeof path, "%s/Frameworks/libsteam_api.framework", exe);
                return known = access(path, F_OK) == 0;
            }
        }
    }
    // On the Mac the guest's own tree is read, and it is known only once the
    // target has been set up.
    const char *dir = kl_library_path();
    if (!dir || !dir[0] || strcmp(dir, ".") == 0) return 0;
    snprintf(path, sizeof path, "%s/libsteam_api.so", dir);
    return known = access(path, F_OK) == 0;
}

int kl_steamapi_claims(const char *soname) {
    if (!soname) return 0;
    const char *b = strrchr(soname, '/');
    b = b ? b + 1 : soname;
    return strcmp(b, "libsteam_api.so") == 0 || strcmp(b, "steam_api") == 0 || strcmp(b, "libsteam_api") == 0;
}

void *kl_steamapi_dlopen(const char *soname) {
    if (!kl_steamapi_claims(soname)) return NULL;
    const char *b = strrchr(soname, '/');
    b = b ? b + 1 : soname;
    __atomic_store_n(&g_in_use, 1, __ATOMIC_RELEASE);
    // Steamworks.NET opens the library again for every function it binds.
    static int said;
    if (!said) {
        said = 1;
        STEAM_LOG("guest dlopen(\"%s\") -> synthetic Steam API (the real one looks for the Steam client "
                  "on the headset, which is not here; see kl_steamapi.h)\n", b);
    }
    return (void *)g_handle;
}

int kl_steamapi_is_handle(const void *h) { return h == (const void *)g_handle; }

void *kl_steamapi_sym(const char *name) {
    // Only the library's own names: it exports no JNI_OnLoad, and a stub that
    // answers 0 to one would be read as a JNI version.
    if (!name || strncmp(name, "Steam", 5) != 0) return NULL;
    int s = kls_slot(name);
    for (size_t i = 0; i < sizeof g_impl / sizeof g_impl[0]; i++)
        if (strcmp(g_impl[i].name, name) == 0) {
            if (s >= 0) g_fn[s].served = 1;
            return g_impl[i].fn;
        }
    // ISteamClient hands out the other interfaces; Steamworks.NET treats a NULL
    // from any of them as "Steam is not there".
    if (strncmp(name, "SteamAPI_ISteamClient_GetISteam", 31) == 0 ||
        (strncmp(name, "SteamAPI_Steam", 14) == 0 && strstr(name, "_v0"))) {
        if (s >= 0) g_fn[s].served = 1;
        return (void *)kls_token;
    }
    return kl_named_stub(name, (void *)kls_unserved);
}

void kl_steamapi_report(FILE *f) {
    static int done;
    if (done || !g_nfn) return;
    done = 1;
    unsigned unserved = 0;
    for (unsigned i = 0; i < g_nfn; i++) if (!g_fn[i].served && g_fn[i].calls) unserved++;
    fprintf(f, "\n=== Steam API surface ===\n  resolved: %u, of which answered 0 by default and called: %u\n", g_nfn, unserved);
    for (unsigned i = 0; i < g_nfn; i++)
        if (!g_fn[i].served && g_fn[i].calls) fprintf(f, "    %-52s x%u\n", g_fn[i].name, g_fn[i].calls);
}
