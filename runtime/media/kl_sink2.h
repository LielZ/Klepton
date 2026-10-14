// The names of rebelancap's audio path (kl_sink2_audio.c, kl_sink2_opensl.c,
// kl_sink2_aaudio.c) as the linker sees them — see kl_sink1.h for why. His
// three files and his tests include this FIRST; with it they are his source
// from shinyquagsire23/Klepton pull request 12 (3fc48c9, 975cad6) unchanged
// but for the names of the headers they include.
#ifndef KL_SINK2_NAMES_H
#define KL_SINK2_NAMES_H
#define kl_aaudio_claims             kl2_aaudio_claims
#define kl_aaudio_dlopen             kl2_aaudio_dlopen
#define kl_aaudio_is_handle          kl2_aaudio_is_handle
#define kl_aaudio_lookup             kl2_aaudio_lookup
#define kl_aaudio_report             kl2_aaudio_report
#define kl_aaudio_sym                kl2_aaudio_sym
#define kl_audio_active              kl2_audio_active
#define kl_audio_close               kl2_audio_close
#define kl_audio_close_src           kl2_audio_close_src
#define kl_audio_dump_seconds        kl2_audio_dump_seconds
#define kl_audio_flush               kl2_audio_flush
#define kl_audio_flush_src           kl2_audio_flush_src
#define kl_audio_fmt_bytes           kl2_audio_fmt_bytes
#define kl_audio_fmt_from_bits       kl2_audio_fmt_from_bits
#define kl_audio_fmt_name            kl2_audio_fmt_name
#define kl_audio_heartbeat           kl2_audio_heartbeat
#define kl_audio_interrupted         kl2_audio_interrupted
#define kl_audio_lead_ms             kl2_audio_lead_ms
#define kl_audio_mic_channels        kl2_audio_mic_channels
#define kl_audio_mic_close           kl2_audio_mic_close
#define kl_audio_mic_enabled         kl2_audio_mic_enabled
#define kl_audio_mic_open            kl2_audio_mic_open
#define kl_audio_mic_rate            kl2_audio_mic_rate
#define kl_audio_mic_read_i16        kl2_audio_mic_read_i16
#define kl_audio_mic_set_enabled     kl2_audio_mic_set_enabled
#define kl_audio_open                kl2_audio_open
#define kl_audio_open_fmt            kl2_audio_open_fmt
#define kl_audio_open_src            kl2_audio_open_src
#define kl_audio_open_src_fmt        kl2_audio_open_src_fmt
#define kl_audio_pause               kl2_audio_pause
#define kl_audio_pause_src           kl2_audio_pause_src
#define kl_audio_play                kl2_audio_play
#define kl_audio_play_src            kl2_audio_play_src
#define kl_audio_report              kl2_audio_report
#define kl_audio_reporter            kl2_audio_reporter
#define kl_audio_restart             kl2_audio_restart
#define kl_audio_resume              kl2_audio_resume
#define kl_audio_session_ready       kl2_audio_session_ready
#define kl_audio_set_latency_ms      kl2_audio_set_latency_ms
#define kl_audio_set_silenced        kl2_audio_set_silenced
#define kl_audio_to_float            kl2_audio_to_float
#define kl_audio_underruns           kl2_audio_underruns
#define kl_audio_write               kl2_audio_write
#define kl_audio_write_src           kl2_audio_write_src
#define kl_opensl_claims             kl2_opensl_claims
#define kl_opensl_dlopen             kl2_opensl_dlopen
#define kl_opensl_heartbeat          kl2_opensl_heartbeat
#define kl_opensl_is_handle          kl2_opensl_is_handle
#define kl_opensl_report             kl2_opensl_report
#define kl_opensl_sym                kl2_opensl_sym
#define kl_wav_close                 kl2_wav_close
#define kl_wav_open                  kl2_wav_open
#define kl_wav_write_f32             kl2_wav_write_f32
#define kl_wav_write_s16             kl2_wav_write_s16
#endif
