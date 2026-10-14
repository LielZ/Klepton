// The audio path's public names, and which of its two implementations answers.
//
// Two whole audio paths are linked in:
//
//   kl1_*   kl_audio.c, kl_opensl.c, kl_aaudio.c — what every released game has
//           played through. One int16 ring; an OpenSL player and an AAudio
//           stream settle the device between them by rate and by who is heard
//           (kl_opensl_yield_device, take_device, silent_yield).
//   kl2_*   kl_sink2_audio.c, kl_sink2_opensl.c, kl_sink2_aaudio.c —
//           rebelancap's (shinyquagsire23/Klepton pull request 12; 3fc48c9,
//           975cad6). Every guest encoding is widened to float before the
//           resampler, each backend is a tagged source and the first one that
//           is HEARD owns the output, AAudio waits out a mixer's block seam
//           instead of playing it, and a census is printed every 15 s.
//
// They replace each other file for file and share no state, so they are not
// merged: KL_AUDIO_SINK2=1 (Advanced > Test in a game's start window) picks
// the second for the whole run, anything else the first, and with the switch
// off not one line of the first path is different from before. kl_sink1.h and
// kl_sink2.h give the two sets their linker names.
//
// The choice is made ONCE, by the first call that would open, look up or play
// something, and logged. Three calls can arrive before the environment is
// final — the session's rate, the microphone toggle and the latency floor are
// all told to "the sink" by the app, whenever it knows them — so those are
// kept here until the choice is made and handed to the chosen side then. The
// reports and the heartbeat do not choose: they are reached from the fault
// handler too, and a path that has not been chosen has nothing to report.

#include <pthread.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "kl_env.h"
#include "kl_audio.h"
#include "kl_opensl.h"
#include "kl_aaudio.h"

#define KL_BOTH(ret, name, params) ret kl1_##name params; ret kl2_##name params;
KL_BOTH(int,      audio_open,            (unsigned, unsigned, unsigned))
KL_BOTH(void,     audio_close,           (void))
KL_BOTH(void,     audio_play,            (void))
KL_BOTH(void,     audio_pause,           (void))
KL_BOTH(void,     audio_flush,           (void))
KL_BOTH(size_t,   audio_write,           (const void *, size_t))
KL_BOTH(size_t,   audio_write_src,       (const void *, const void *, size_t))
KL_BOTH(int,      audio_active,          (void))
KL_BOTH(void,     audio_interrupted,     (int))
KL_BOTH(int,      audio_restart,         (void))
KL_BOTH(void,     audio_set_silenced,    (int))
KL_BOTH(void,     audio_resume,          (void))
KL_BOTH(void,     audio_session_ready,   (double))
KL_BOTH(unsigned, audio_underruns,       (void))
KL_BOTH(void,     audio_report,          (FILE *))
KL_BOTH(void,     audio_set_latency_ms,  (unsigned))
KL_BOTH(void,     audio_mic_set_enabled, (int))
KL_BOTH(int,      audio_mic_enabled,     (void))
KL_BOTH(int,      audio_mic_open,        (unsigned, unsigned))
KL_BOTH(void,     audio_mic_close,       (void))
KL_BOTH(unsigned, audio_mic_rate,        (void))
KL_BOTH(unsigned, audio_mic_channels,    (void))
KL_BOTH(int,      audio_mic_read_i16,    (int16_t *, int))
KL_BOTH(void *,   opensl_dlopen,         (const char *))
KL_BOTH(int,      opensl_claims,         (const char *))
KL_BOTH(int,      opensl_is_handle,      (const void *))
KL_BOTH(void *,   opensl_sym,            (const char *))
KL_BOTH(void,     opensl_report,         (FILE *))
KL_BOTH(void,     opensl_heartbeat,      (FILE *))
KL_BOTH(void *,   aaudio_lookup,         (const char *))
KL_BOTH(int,      aaudio_claims,         (const char *))
KL_BOTH(void *,   aaudio_dlopen,         (const char *))
KL_BOTH(int,      aaudio_is_handle,      (const void *))
KL_BOTH(void *,   aaudio_sym,            (const char *))
KL_BOTH(void,     aaudio_report,         (FILE *))
// Only the first path has these; nothing outside its three files calls them,
// and the second answers the same questions inside its own arbitration.
void     kl1_audio_src_release(const void *);
int      kl1_audio_peak(void);
int      kl1_opensl_audio_users(void);
void     kl1_opensl_yield_device(unsigned);
unsigned kl1_aaudio_output_rate(void);

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static atomic_int g_chosen;              // 0 until the choice is made
static int        g_two;                 // ...and then: the second path
// What the app said before then.
static struct {
    int have_rate, have_mic, have_latency;
    double rate; int mic; unsigned latency;
} g_early;

static int sink2(void) {
    if (atomic_load_explicit(&g_chosen, memory_order_acquire)) return g_two;
    pthread_mutex_lock(&g_lock);
    if (!atomic_load(&g_chosen)) {
        g_two = kl_env_on("KL_AUDIO_SINK2", 0);
        fprintf(stderr, g_two
            ? "  [au] audio path: the second sink (KL_AUDIO_SINK2=1) — float for "
              "every guest format, one owner of the output among the backends, "
              "AAudio block seams waited out\n"
            : "  [au] audio path: the first sink (KL_AUDIO_SINK2=1 selects the "
              "second)\n");
        // Under the lock: a setter that arrives now waits, and so cannot be
        // overtaken by the older value it replaces.
        if (g_early.have_latency)
            (g_two ? kl2_audio_set_latency_ms : kl1_audio_set_latency_ms)(g_early.latency);
        if (g_early.have_mic)
            (g_two ? kl2_audio_mic_set_enabled : kl1_audio_mic_set_enabled)(g_early.mic);
        if (g_early.have_rate)
            (g_two ? kl2_audio_session_ready : kl1_audio_session_ready)(g_early.rate);
        atomic_store_explicit(&g_chosen, 1, memory_order_release);
    }
    pthread_mutex_unlock(&g_lock);
    return g_two;
}

// 1 or 0 once chosen, -1 before. Never chooses.
int kl_audio_sink2_chosen(void) {
    return atomic_load_explicit(&g_chosen, memory_order_acquire) ? g_two : -1;
}

#define KL_SINK(name) (sink2() ? kl2_##name : kl1_##name)

// ---- told by the app, possibly before the choice ----

// Not chosen yet: returns 1 with g_lock HELD, for the caller to keep its value
// in g_early and unlock. 0 once the choice is made.
static int early_lock(void) {
    if (atomic_load_explicit(&g_chosen, memory_order_acquire)) return 0;
    pthread_mutex_lock(&g_lock);
    if (!atomic_load(&g_chosen)) return 1;
    pthread_mutex_unlock(&g_lock);
    return 0;
}

void kl_audio_session_ready(double sample_rate) {
    if (early_lock()) {
        g_early.rate = sample_rate; g_early.have_rate = 1;
        pthread_mutex_unlock(&g_lock);
        return;
    }
    KL_SINK(audio_session_ready)(sample_rate);
}
void kl_audio_mic_set_enabled(int on) {
    if (early_lock()) {
        g_early.mic = on; g_early.have_mic = 1;
        pthread_mutex_unlock(&g_lock);
        return;
    }
    KL_SINK(audio_mic_set_enabled)(on);
}
void kl_audio_set_latency_ms(unsigned ms) {
    if (early_lock()) {
        g_early.latency = ms; g_early.have_latency = 1;
        pthread_mutex_unlock(&g_lock);
        return;
    }
    KL_SINK(audio_set_latency_ms)(ms);
}
// Asked by the app's own microphone UI, which may come before the choice too.
int kl_audio_mic_enabled(void) {
    if (early_lock()) {
        int on = g_early.have_mic && g_early.mic;
        pthread_mutex_unlock(&g_lock);
        return on;
    }
    return KL_SINK(audio_mic_enabled)();
}

// ---- the sink ----

int    kl_audio_open(unsigned rate, unsigned channels, unsigned bits) { return KL_SINK(audio_open)(rate, channels, bits); }
void   kl_audio_close(void)  { KL_SINK(audio_close)(); }
void   kl_audio_play(void)   { KL_SINK(audio_play)(); }
void   kl_audio_pause(void)  { KL_SINK(audio_pause)(); }
void   kl_audio_flush(void)  { KL_SINK(audio_flush)(); }
size_t kl_audio_write(const void *pcm, size_t bytes) { return KL_SINK(audio_write)(pcm, bytes); }
size_t kl_audio_write_src(const void *src, const void *pcm, size_t bytes) { return KL_SINK(audio_write_src)(src, pcm, bytes); }
int    kl_audio_active(void) { return KL_SINK(audio_active)(); }
void   kl_audio_interrupted(int began)     { KL_SINK(audio_interrupted)(began); }
int    kl_audio_restart(void)              { return KL_SINK(audio_restart)(); }
void   kl_audio_set_silenced(int silenced) { KL_SINK(audio_set_silenced)(silenced); }
void   kl_audio_resume(void)               { KL_SINK(audio_resume)(); }
unsigned kl_audio_underruns(void)          { return KL_SINK(audio_underruns)(); }

int      kl_audio_mic_open(unsigned want_rate, unsigned want_channels) { return KL_SINK(audio_mic_open)(want_rate, want_channels); }
void     kl_audio_mic_close(void)    { KL_SINK(audio_mic_close)(); }
unsigned kl_audio_mic_rate(void)     { return KL_SINK(audio_mic_rate)(); }
unsigned kl_audio_mic_channels(void) { return KL_SINK(audio_mic_channels)(); }
int      kl_audio_mic_read_i16(int16_t *buf, int frames) { return KL_SINK(audio_mic_read_i16)(buf, frames); }

// ---- the two guest-facing libraries ----

void *kl_opensl_dlopen(const char *soname)  { return KL_SINK(opensl_dlopen)(soname); }
int   kl_opensl_claims(const char *soname)  { return KL_SINK(opensl_claims)(soname); }
int   kl_opensl_is_handle(const void *h)    { return KL_SINK(opensl_is_handle)(h); }
void *kl_opensl_sym(const char *name)       { return KL_SINK(opensl_sym)(name); }

void *kl_aaudio_lookup(const char *name)    { return KL_SINK(aaudio_lookup)(name); }
int   kl_aaudio_claims(const char *soname)  { return KL_SINK(aaudio_claims)(soname); }
void *kl_aaudio_dlopen(const char *soname)  { return KL_SINK(aaudio_dlopen)(soname); }
int   kl_aaudio_is_handle(const void *h)    { return KL_SINK(aaudio_is_handle)(h); }
void *kl_aaudio_sym(const char *name)       { return KL_SINK(aaudio_sym)(name); }

// ---- reports: whichever path ran, without choosing one ----

#define KL_RAN(name) (kl_audio_sink2_chosen() == 1 ? kl2_##name : kl1_##name)
void kl_audio_report(FILE *f)     { KL_RAN(audio_report)(f); }
void kl_opensl_report(FILE *f)    { KL_RAN(opensl_report)(f); }
void kl_aaudio_report(FILE *f)    { KL_RAN(aaudio_report)(f); }
void kl_opensl_heartbeat(FILE *f) { KL_RAN(opensl_heartbeat)(f); }

// ---- the first path's own: declared in the public headers, called by nothing
// outside its three files today ----

void kl_audio_src_release(const void *src) { if (!sink2()) kl1_audio_src_release(src); }
int  kl_audio_peak(void)                   { return kl_audio_sink2_chosen() == 0 ? kl1_audio_peak() : 0; }
int  kl_opensl_audio_users(void)           { return kl_audio_sink2_chosen() == 0 ? kl1_opensl_audio_users() : 0; }
void kl_opensl_yield_device(unsigned rate) { if (!sink2()) kl1_opensl_yield_device(rate); }
unsigned kl_aaudio_output_rate(void)       { return kl_audio_sink2_chosen() == 0 ? kl1_aaudio_output_rate() : 0; }
