// The audio path's switch (runtime/media/kl_audio_switch.c). `make audioswitch`,
// in `make check`, run once with KL_AUDIO_SINK2 unset and once with it on.
//
// What it holds:
//   - the choice is not made by what the app tells the sink early (rate, mic,
//     latency) nor by a report, and IS made by the first lookup;
//   - after it, every public name answers from the chosen path: the same
//     pointer that path's own lookup gives, and not the other's;
//   - what was told early reached the chosen path and only it.
//
// usage: t_audioswitch 0|1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "media/kl_audio.h"
#include "media/kl_opensl.h"
#include "media/kl_aaudio.h"

void *kl1_opensl_sym(const char *), *kl2_opensl_sym(const char *);
void *kl1_aaudio_sym(const char *), *kl2_aaudio_sym(const char *);
int   kl1_audio_mic_enabled(void),   kl2_audio_mic_enabled(void);

static int g_fail;
#define CHECK(cond, ...) do { \
    if (!(cond)) { g_fail++; printf("  FAIL: "); printf(__VA_ARGS__); printf("\n"); } \
} while (0)

int main(int argc, char **argv) {
    int want = argc > 1 && atoi(argv[1]);
    if (want) setenv("KL_AUDIO_SINK2", "1", 1); else unsetenv("KL_AUDIO_SINK2");
    setenv("KL_AUDIO", "0", 1);   // host test: never open a real output unit
    printf("=== audio path switch, KL_AUDIO_SINK2 %s ===\n", want ? "on" : "unset");

    CHECK(kl_audio_sink2_chosen() == -1, "chosen before anything asked");
    kl_audio_session_ready(48000.0);
    kl_audio_set_latency_ms(77);
    kl_audio_mic_set_enabled(1);
    CHECK(kl_audio_mic_enabled() == 1, "the microphone toggle is not read back before the choice");
    kl_audio_report(stderr);
    kl_opensl_report(stderr);
    kl_aaudio_report(stderr);
    kl_opensl_heartbeat(stderr);
    CHECK(kl_audio_sink2_chosen() == -1, "what the app tells the sink, or a report, made the choice");
    CHECK(!kl1_audio_mic_enabled() && !kl2_audio_mic_enabled(),
          "a path was told about the microphone before it was chosen");

    void *sl = kl_opensl_sym("slCreateEngine");
    CHECK(kl_audio_sink2_chosen() == want, "chosen %d, wanted %d", kl_audio_sink2_chosen(), want);
    void *sl1 = kl1_opensl_sym("slCreateEngine"), *sl2 = kl2_opensl_sym("slCreateEngine");
    CHECK(sl1 && sl2 && sl1 != sl2, "the two paths do not each have their own slCreateEngine");
    CHECK(sl == (want ? sl2 : sl1), "slCreateEngine is not the chosen path's");

    void *aa = kl_aaudio_sym("AAudio_createStreamBuilder");
    void *aa1 = kl1_aaudio_sym("AAudio_createStreamBuilder"), *aa2 = kl2_aaudio_sym("AAudio_createStreamBuilder");
    CHECK(aa1 && aa2 && aa1 != aa2, "the two paths do not each have their own AAudio_createStreamBuilder");
    CHECK(aa == (want ? aa2 : aa1), "AAudio_createStreamBuilder is not the chosen path's");

    CHECK((want ? kl2_audio_mic_enabled() : kl1_audio_mic_enabled()) == 1,
          "the microphone toggle did not reach the chosen path");
    CHECK((want ? kl1_audio_mic_enabled() : kl2_audio_mic_enabled()) == 0,
          "the microphone toggle reached the path that was not chosen");
    kl_audio_mic_set_enabled(0);
    CHECK(kl_audio_mic_enabled() == 0 && !kl1_audio_mic_enabled() && !kl2_audio_mic_enabled(),
          "the microphone toggle after the choice does not go to the chosen path");

    if (g_fail) printf("FAIL: %d check(s)\n", g_fail);
    else printf("PASS: the %s path answers every name\n", want ? "second" : "first");
    return g_fail != 0;
}
