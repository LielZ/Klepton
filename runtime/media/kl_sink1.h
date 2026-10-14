// The names of the audio path that has shipped so far, as the linker sees them.
//
// Two implementations of the audio path are built into the runtime — this one
// (kl_audio.c, kl_opensl.c, kl_aaudio.c) and rebelancap's (kl_sink2_*.c) — and
// kl_audio_switch.c owns the public kl_audio_* / kl_opensl_* / kl_aaudio_*
// names and hands each call to the one KL_AUDIO_SINK2 chose. So that both can
// be linked, each side's three files include its list FIRST, before any other
// header: every function they define or call among themselves becomes kl1_*
// here and kl2_* there. Nothing else includes this.
//
// A function added to one of the three files' headers needs a line here and a
// forwarder in kl_audio_switch.c; `make check` links both and fails on a name
// that is missing (a duplicate symbol, or an undefined kl_audio_*).
#ifndef KL_SINK1_NAMES_H
#define KL_SINK1_NAMES_H
#define kl_aaudio_claims             kl1_aaudio_claims
#define kl_aaudio_dlopen             kl1_aaudio_dlopen
#define kl_aaudio_is_handle          kl1_aaudio_is_handle
#define kl_aaudio_lookup             kl1_aaudio_lookup
#define kl_aaudio_output_rate        kl1_aaudio_output_rate
#define kl_aaudio_report             kl1_aaudio_report
#define kl_aaudio_sym                kl1_aaudio_sym
#define kl_audio_active              kl1_audio_active
#define kl_audio_close               kl1_audio_close
#define kl_audio_flush               kl1_audio_flush
#define kl_audio_interrupted         kl1_audio_interrupted
#define kl_audio_mic_channels        kl1_audio_mic_channels
#define kl_audio_mic_close           kl1_audio_mic_close
#define kl_audio_mic_enabled         kl1_audio_mic_enabled
#define kl_audio_mic_open            kl1_audio_mic_open
#define kl_audio_mic_rate            kl1_audio_mic_rate
#define kl_audio_mic_read_i16        kl1_audio_mic_read_i16
#define kl_audio_mic_set_enabled     kl1_audio_mic_set_enabled
#define kl_audio_open                kl1_audio_open
#define kl_audio_pause               kl1_audio_pause
#define kl_audio_peak                kl1_audio_peak
#define kl_audio_play                kl1_audio_play
#define kl_audio_report              kl1_audio_report
#define kl_audio_restart             kl1_audio_restart
#define kl_audio_resume              kl1_audio_resume
#define kl_audio_session_ready       kl1_audio_session_ready
#define kl_audio_set_latency_ms      kl1_audio_set_latency_ms
#define kl_audio_set_silenced        kl1_audio_set_silenced
#define kl_audio_src_release         kl1_audio_src_release
#define kl_audio_underruns           kl1_audio_underruns
#define kl_audio_write               kl1_audio_write
#define kl_audio_write_src           kl1_audio_write_src
#define kl_opensl_audio_users        kl1_opensl_audio_users
#define kl_opensl_claims             kl1_opensl_claims
#define kl_opensl_dlopen             kl1_opensl_dlopen
#define kl_opensl_heartbeat          kl1_opensl_heartbeat
#define kl_opensl_is_handle          kl1_opensl_is_handle
#define kl_opensl_report             kl1_opensl_report
#define kl_opensl_sym                kl1_opensl_sym
#define kl_opensl_yield_device       kl1_opensl_yield_device
#endif
