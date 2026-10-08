// A SteamVR game's loading screen, when it is not the game that draws it.
//
// Half-Life: Alyx does not render its loading screen. It suspends rendering,
// leaves a small skybox with the compositor, and SAYS what the screen should
// show — over an undocumented OpenVR interface (IVRMailbox), to a web page of
// its own (hlvr/webui/interstitials.html) that SteamVR's web helper displays:
//
//   {"type": "begin_loading", "mapName": .., "chapter": .., "tipText": ..,
//    "description": .., "loadingText": "LOADING", "facingAngle": ..}
//   {"type": "show_message", "text": "Press Trigger To Start"}
//   {"type": "end_loading"}
//
// There is no web helper here, so those messages went nowhere and the wait for
// the trigger was a picture with nothing on it. xrizer (which serves the
// interface, patched by guestbuild/xrizer-interstitials.py) writes each message
// to /dev/klepton-interstitial, NUL-terminated; the open of that path is
// answered with one end of a socket pair, as the audio device's is
// (kl_lx_audio.c), and what arrives is kept here for a compositor to draw
// (kl_interstitial_get, kl_ovrp.h).
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include "kl_lx.h"
#include "../xr/kl_ovrp.h"

#define LXI_PATH "/dev/klepton-interstitial"

static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static kl_interstitial g_state;

int kl_lx_interstitial_is(const char *path) { return path && !strcmp(path, LXI_PATH); }

int kl_interstitial_get(kl_interstitial *out) {
    pthread_mutex_lock(&g_mu);
    if (out) *out = g_state;
    int gen = (int)g_state.generation;
    pthread_mutex_unlock(&g_mu);
    return gen;
}

// The guest is drawing again: whatever it said about its loading screen is over,
// whether or not it said so (Alyx sends no end_loading after the trigger).
void kl_interstitial_done(void) {
    if (!g_state.phase) return;
    pthread_mutex_lock(&g_mu);
    if (g_state.phase) { g_state.phase = 0; g_state.generation++; }
    pthread_mutex_unlock(&g_mu);
}

// The string value of "key" in a flat JSON object, unescaped. Enough for what
// the game sends, which is one object of string and number members.
static void json_string(const char *json, const char *key, char *out, size_t cap) {
    out[0] = 0;
    char pat[64];
    snprintf(pat, sizeof pat, "\"%s\"", key);
    const char *p = strstr(json, pat);
    if (!p) return;
    p += strlen(pat);
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    if (*p++ != ':') return;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    if (*p++ != '"') return;
    size_t n = 0;
    while (*p && *p != '"' && n + 4 < cap) {
        if (*p != '\\') { out[n++] = *p++; continue; }
        p++;
        switch (*p) {
        case 'n': out[n++] = '\n'; p++; break;
        case 't': out[n++] = ' ';  p++; break;
        case 'r': p++; break;
        case 'u': {
            unsigned cp = 0;
            if (sscanf(p + 1, "%4x", &cp) == 1) {
                if (cp < 0x80) out[n++] = (char)cp;
                else if (cp < 0x800) { out[n++] = (char)(0xc0 | (cp >> 6)); out[n++] = (char)(0x80 | (cp & 0x3f)); }
                else { out[n++] = (char)(0xe0 | (cp >> 12)); out[n++] = (char)(0x80 | ((cp >> 6) & 0x3f));
                       out[n++] = (char)(0x80 | (cp & 0x3f)); }
                p += 5;
            } else p++;
            break;
        }
        case 0: break;
        default: out[n++] = *p++; break;      // \" \\ \/
        }
    }
    out[n] = 0;
}

static void message(const char *json) {
    char type[32];
    json_string(json, "type", type, sizeof type);
    pthread_mutex_lock(&g_mu);
    if (!strcmp(type, "begin_loading")) {
        g_state.phase = 1;
        g_state.message[0] = 0;
        json_string(json, "loadingText", g_state.loading, sizeof g_state.loading);
        json_string(json, "chapter", g_state.chapter, sizeof g_state.chapter);
        json_string(json, "mapName", g_state.map, sizeof g_state.map);
        json_string(json, "tipText", g_state.tip, sizeof g_state.tip);
        json_string(json, "description", g_state.description, sizeof g_state.description);
        g_state.generation++;
    } else if (!strcmp(type, "show_message")) {
        if (!g_state.phase) g_state.phase = 1;
        json_string(json, "text", g_state.message, sizeof g_state.message);
        g_state.generation++;
    } else if (!strcmp(type, "end_loading")) {
        g_state.phase = 0;
        g_state.generation++;
    }
    int phase = g_state.phase;
    pthread_mutex_unlock(&g_mu);
    fprintf(stderr, "  [klepton] loading screen: %s%s%s (phase %d)\n", type[0] ? type : "an unreadable message",
            !strcmp(type, "show_message") ? " — " : "", !strcmp(type, "show_message") ? g_state.message : "", phase);
}

static void *reader(void *arg) {
    int fd = (int)(intptr_t)arg;
    pthread_setname_np("Klepton loading screen");
    char buf[4096];
    size_t have = 0;
    for (;;) {
        ssize_t n = read(fd, buf + have, sizeof buf - 1 - have);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        have += (size_t)n;
        for (;;) {
            char *end = memchr(buf, 0, have);
            if (!end) break;
            message(buf);
            size_t used = (size_t)(end - buf) + 1;
            memmove(buf, buf + used, have - used);
            have -= used;
        }
        if (have >= sizeof buf - 1) have = 0;       // a message longer than any the game sends
    }
    close(fd);
    return NULL;
}

int kl_lx_interstitial_open(void) {
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) return -1;
    pthread_t th;
    int rc = pthread_create(&th, NULL, reader, (void *)(intptr_t)sv[1]);
    if (rc != 0) { close(sv[0]); close(sv[1]); errno = rc; return -1; }
    pthread_detach(th);
    return sv[0];
}
