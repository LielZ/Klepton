// Half-Life: Alyx's launch-time choices: how large a picture it draws, how many
// samples a pixel of it has, how wide a cone each eye is drawn with, and whether
// the edge of that cone is shaded as densely as its middle.
//
// The engine has a ladder of fidelity levels, each a picture size, and a
// controller that walks it to fit the frame time. On this hardware that
// controller sat at the bottom of the ladder whatever it was told — a frame costs
// more than any budget at the larger sizes — and the result was a picture its
// player called pixelated at 50 frames a second, with no way to choose otherwise.
// So the controller is switched off and the level is chosen here:
//
//   +vr_fidelity_level_auto 0 +vr_fidelity_level <n>
//
// handed to the game through KL_LX_ARGS_EXTRA. Measured sizes, as a fraction of
// the eye texture the display is offered at: level 0 = 0.75, 3 = 0.875,
// 5 = 0.97, 8 = 1.19 (the largest; higher numbers clamp to it).
//
// What the larger sizes cost is frame rate, not smoothness of the view: the
// compositor reprojects the last picture to the head's rotation at the panel's
// rate whatever the game manages. Hands, objects and walking move at the game's
// own rate.
//
// A launch that names KL_LX_ARGS_EXTRA itself (visionos/run.sh, lx_launch.sh)
// keeps what it named.
//
// The second choice is how many samples a pixel of that picture has. The eye
// targets are multisampled and on a GPU that is fill-bound, as this one is, the
// sample count is the largest single factor in a frame's cost. There is a convar
// for it, vr_msaa, and setting it does nothing useful: the ladder is a table,
// vr_fidelity_levels_deckard.csv inside the game's archive, and each of its rows
// names its own vr_msaa — 2 for level 0 and 4 for every other — which the engine
// applies with the level. (`+vr_msaa 2` on top of a level above 0 leaves targets
// of one shape and a viewport of another, and the compositor is handed bounds
// beyond 1.0: no picture at all.) What the engine does offer is a file of that
// shape named vr_fidelity_levels_override.csv in the game's own directory, read
// in preference to the archive's (libvr.so+0xb1df8). So the table is written
// here at every start, with the sample count chosen below in every row.
//
// Every row also carries the SAME scale, the chosen picture's. The engine
// allocates its eye targets — two multisampled and five resolved, all two layers
// deep — for the largest level its table holds, whichever level it draws: with
// Valve's ladder (0.78 to 1.2) a picture at scale 1.0 sat in targets 1.44 times
// its area, and the smallest picture in targets 2.4 times its area. On a device
// where the app is ended at 8.2 GB and a level reaches that, those are hundreds
// of megabytes of targets nothing is drawn into (Mac, first level, 2x: 3625 MB
// of GPU memory with the ladder, 3365 MB with one scale).
//
// The third is how wide a cone each eye is drawn with. A rendered picture is
// uniform in tangent, so its outermost degrees are its most expensive, and on
// this display they are also the least seen: the eight degrees from 52 to 60 on
// the temporal side are a sixth of the picture's width and land where the
// panel's own foveation shows an eighth of its central density. "Trimmed" caps
// the cone at 52 degrees (KL_OVRP_EYE_TAN_MAX=1.3, runtime/xr/kl_ovrp.c) and
// narrows the eye texture with it, so a sixth of the pixels are not drawn; the
// price is that the far edge of view is dark.
//
// The fourth is foveation proper: the scene is shaded at full density straight
// ahead and progressively coarser toward the edge of each eye's cone. The
// engine's own foveated rendering wants a fragment density map, which MoltenVK
// does not have; runtime/gfx/kl_mtl_foveate.m does it underneath MoltenVK
// instead, with a Metal rasterization rate map on the scene pass and an unwarp
// of its result before the engine's post-processing reads it. The fovea is
// fixed, not gaze-tracked — an app is not told where the eyes look — so the
// softness is at the edge of the picture, wherever one looks.
//
// The fifth is the language. The game takes it from Steam, and the Steam this
// process is given (runtime/linux/kl_lx_steam.c) says "english"; `-language
// <name>` on the command line comes before that answer, and with it the menus
// and the subtitles are the game's own in that language — they ship with it.
//
// Voices do not: Valve recorded the game in English only. What exists is fan
// work from the Steam Workshop, an archive of the same sound files under the
// same names, and on a PC it is an add-on that Steam's client mounts and that
// only a game started "with add-ons" hears. There is no Steam client here and
// no need for one: the engine has a search path of its own for exactly this,
//
//   Game_Language   hlvr_*LANGUAGE*
//
// in gameinfo.gi's SearchPaths (the way Dota 2 ships its voices), which puts
// game/hlvr_<language> in front of game/hlvr when that is the language — for
// every game, saved ones included. Valve's gameinfo.gi for Alyx has no such
// line, so it is added here at a start that wants it and taken out at one that
// does not; the archive itself is staged as game/hlvr_<language>/pak01_dir.vpk
// by whoever installed the game. Measured on a Mac (2026-10-09): without the
// line hlvr_german is never looked at; with it every lookup tries it first, and
// a sound file put into a one-part pak01_dir.vpk there was read from that
// archive and no longer from hlvr's.
//
// Taking the voices off the device again is the installer's to ask for and
// this app's to finish. Nothing can be deleted in an app's container from
// outside, only written: an installer that no longer wants the archive there
// overwrites it with an empty file, which gives the space back at once, and an
// archive too short to have a header is treated here as none — and removed,
// with its folder, at the next start.
import SwiftUI
import Foundation

func klIsAlyx() -> Bool { klTargetName() == "alyx" }

enum AlyxQuality: Int, CaseIterable, Identifiable {
    case smooth, balanced, sharp, maximum

    static let storageKey = "alyx.quality"
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .smooth:   return "Smooth"
        case .balanced: return "Balanced"
        case .sharp:    return "Sharp"
        case .maximum:  return "Maximum"
        }
    }

    /// What the settings window calls it.
    var name: String {
        switch self {
        case .smooth:   return klT("Small", "Klein")
        case .balanced: return klT("Medium", "Mittel")
        case .sharp:    return klT("Large", "Groß")
        case .maximum:  return klT("Maximum", "Maximal")
        }
    }
    static var note: String {
        klT("How many pixels the game draws. Larger is sharper and slower; “Maximum” can run out of memory in big scenes.",
            "Wie viele Bildpunkte das Spiel zeichnet. Größer ist schärfer und langsamer; „Maximal“ kann in großen Szenen den Speicher sprengen.")
    }

    /// The render target scale for this choice, as the table spells it: the
    /// scales of Valve's levels 0, 3, 5 and 8. 1 is the size the runtime
    /// recommends for the display.
    var scale: String {
        switch self {
        case .smooth:   return "0.78"
        case .balanced: return "0.9"
        case .sharp:    return "1"
        case .maximum:  return "1.2"
        }
    }

    /// The engine's texture pool for this choice, in MB (+r_texture_pool_size).
    ///
    /// The pool is what the texture streamer may fill, and it fills it: left at
    /// the engine's default (2816 MB) a level's textures grew from 0.5 GB to
    /// 2.2 GB within a minute and a half and were still growing when the app
    /// reached the 8.19 GB at which the system ends it (2026-10-06, twice). The
    /// eye targets take the more memory the larger the picture — about 0.5 GB
    /// at the smallest and 1.2 GB at the largest — so the pool is what is left
    /// of a fixed sum: a larger picture is paid for with coarser distant
    /// textures rather than with the session.
    var texturePoolMB: Int {
        switch self {
        case .smooth:   return 1536
        case .balanced: return 1408
        case .sharp:    return 1152
        case .maximum:  return 768
        }
    }

    /// The engine's fidelity level for this choice — what selects the size when
    /// the table below could not be written and Valve's own applies.
    var fidelityLevel: Int {
        switch self {
        case .smooth:   return 0
        case .balanced: return 3
        case .sharp:    return 5
        case .maximum:  return 8
        }
    }

    static var stored: AlyxQuality {
        // `object(forKey:)` rather than `integer(forKey:)`: a key that was never
        // written reads as 0, which is Smooth, not the default.
        guard let n = UserDefaults.standard.object(forKey: storageKey) as? Int,
              let q = AlyxQuality(rawValue: n) else { return .balanced }
        return q
    }
}

enum AlyxEdges: Int, CaseIterable, Identifiable {
    case two = 2, four = 4

    static let storageKey = "alyx.msaa"
    /// Four, as the game ships and as the pipeline list that is compiled
    /// before the game starts was recorded: of its 3,030 graphics pipelines
    /// 1,585 are for four samples and 552 for two.
    static let standard = AlyxEdges.four
    var id: Int { rawValue }

    var title: String { self == .two ? "2x" : "4x" }

    var name: String { self == .two ? "2×" : "4×" }
    static var note: String {
        klT("How slanted edges are smoothed. 4× is cleaner, 2× is faster.",
            "Wie schräge Kanten geglättet werden. 4× ist sauberer, 2× ist schneller.")
    }

    static var stored: AlyxEdges {
        // A launch can name it (KL_ALYX_MSAA=2|4), which is how the two are
        // measured against each other without touching the window.
        if let e = getenv("KL_ALYX_MSAA"), let v = AlyxEdges(rawValue: Int(atoi(e))) { return v }
        guard let n = UserDefaults.standard.object(forKey: storageKey) as? Int,
              let v = AlyxEdges(rawValue: n) else { return standard }
        return v
    }
}

enum AlyxView: Int, CaseIterable, Identifiable {
    case full, trimmed

    static let storageKey = "alyx.view"
    static let standard = AlyxView.trimmed
    /// As the settings window lists them: the lightest first, the costliest last.
    static let ordered: [AlyxView] = [.trimmed, .full]
    var id: Int { rawValue }

    var title: String { self == .full ? "Full" : "Trimmed" }

    var name: String { self == .full ? klT("Full", "Voll") : klT("Trimmed", "Beschnitten") }
    static var note: String {
        klT("“Trimmed” leaves the outermost edge of view dark and saves about a sixth of the work.",
            "„Beschnitten“ lässt den äußersten Rand des Sichtfelds dunkel und spart etwa ein Sechstel der Arbeit.")
    }

    static var stored: AlyxView {
        guard let n = UserDefaults.standard.object(forKey: storageKey) as? Int,
              let v = AlyxView(rawValue: n) else { return standard }
        return v
    }
}

enum AlyxFoveation: Int, CaseIterable, Identifiable {
    case off, on, strong

    static let storageKey = "alyx.foveation"
    /// What a fresh install runs with: the Balanced preset's (AlyxPreset),
    /// about half the pixels shaded.
    static let standard = AlyxFoveation.strong
    /// As the settings window lists them: the lightest first, the costliest last.
    static let ordered: [AlyxFoveation] = [.strong, .on, .off]
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off:    return "Off"
        case .on:     return "Mild"
        case .strong: return "Strong"
        }
    }

    var name: String {
        switch self {
        case .off:    return klT("Off", "Aus")
        case .on:     return klT("Mild", "Leicht")
        case .strong: return klT("Strong", "Stark")
        }
    }
    static var note: String {
        klT("Keeps the middle of the picture sharp and draws its edge more coarsely. “Strong” saves the most; the edge then looks softer when you look at it.",
            "Hält die Bildmitte scharf und zeichnet den Rand gröber. „Stark“ spart am meisten; der Rand wirkt dann weicher, wenn man hinsieht.")
    }

    /// KL_VK_FOVEATE and KL_VK_FOVEATE_INNER: the rate at the widest edge of
    /// the cone, and the tangent out to which the rate stays 1.
    var knobs: (edge: String, inner: String)? {
        switch self {
        case .off:    return nil
        case .on:     return ("0.3", "0.30")
        case .strong: return ("0.15", "0.20")
        }
    }

    static var stored: AlyxFoveation {
        guard let n = UserDefaults.standard.object(forKey: storageKey) as? Int,
              let v = AlyxFoveation(rawValue: n) else { return .standard }
        return v
    }
}

/// How finely the compositor draws the game's picture onto the display
/// (KL_CP_QUALITY, Compositor Services' render quality). The game's picture is
/// about 2,500 pixels wide an eye; at full quality the compositor draws it into
/// a much finer target than that, and its pass was measured at 5-6 ms of GPU
/// time per display frame beside a game that needs 20-30 ms for its own
/// (Vision Pro M5, 2026-10-11). Glovebox runs at 0.40; the device's own
/// default is 0.52.
enum AlyxOutput: Int, CaseIterable, Identifiable {
    case full, standard, light

    static let storageKey = "alyx.output"
    /// What a fresh install runs with (`standard` is one of the cases here).
    static let initial = AlyxOutput.light
    /// As the settings window lists them: the lightest first, the costliest last.
    static let ordered: [AlyxOutput] = [.light, .standard, .full]
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .full:     return "Full"
        case .standard: return "Standard"
        case .light:    return "Light"
        }
    }

    var name: String {
        switch self {
        case .full:     return klT("Full", "Voll")
        case .standard: return "Standard"
        case .light:    return klT("Light", "Leicht")
        }
    }
    static var note: String {
        klT("How finely the finished picture is put on the display. Lower leaves the graphics chip more time for the game; fine text may look softer.",
            "Wie fein das fertige Bild aufs Display kommt. Niedriger lässt dem Grafikchip mehr Zeit fürs Spiel; feine Schrift kann weicher wirken.")
    }

    var quality: String {
        switch self {
        case .full:     return "1.0"
        case .standard: return "0.52"
        case .light:    return "0.40"
        }
    }

    static var stored: AlyxOutput {
        guard let n = UserDefaults.standard.object(forKey: storageKey) as? Int,
              let v = AlyxOutput(rawValue: n) else { return initial }
        return v
    }
}

/// How fast the player moves with the stick ("continuous" movement): the
/// game's two speeds, walking and in a fight, both set to one value
/// (+hlvr_continuous_normal_speed, +hlvr_continuous_combat_speed) — what
/// players of the game on a PC put into its launch options when the stick
/// feels like wading (katwalk.fandom.com, "Half Life Alyx Workaround: Walking
/// Speed": 175, or 150 or 200 to taste). "Game" passes neither and leaves the
/// game its own two speeds. Teleport and shift movement are not affected.
enum AlyxPace: Int, CaseIterable, Identifiable {
    case game = 0, brisk = 150, fast = 175, faster = 200

    static let storageKey = "alyx.pace"
    var id: Int { rawValue }

    var name: String {
        switch self {
        case .game:   return klT("Game's own", "Wie im Spiel")
        case .brisk:  return "150"
        case .fast:   return "175"
        case .faster: return "200"
        }
    }

    /// The arguments for the game's command line; empty for the game's own.
    var arguments: String {
        self == .game ? "" : " +hlvr_continuous_normal_speed \(rawValue) +hlvr_continuous_combat_speed \(rawValue)"
    }

    static var stored: AlyxPace {
        guard let n = UserDefaults.standard.object(forKey: storageKey) as? Int,
              let v = AlyxPace(rawValue: n) else { return .game }
        return v
    }
}

enum AlyxLanguage: Int, CaseIterable, Identifiable {
    case english, german

    static let storageKey = "alyx.language"
    static let voicesKey = "alyx.voices"
    var id: Int { rawValue }

    var title: String { self == .english ? "English" : "Deutsch" }

    /// The engine's name for it: `-language <name>`, closecaption_<name>.dat,
    /// and the folder hlvr_<name> a voice archive is staged into.
    var engineName: String { self == .english ? "english" : "german" }

    /// Where a voice archive for this language is staged. English is the
    /// game's own recording and has no such place.
    private var voiceArchivePlace: URL? {
        guard self != .english,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        return docs.appendingPathComponent("lx/game/hlvr_\(engineName)/pak01_dir.vpk")
    }

    /// The staged voice archive for this language, if there is one. A file
    /// shorter than an archive's header (28 bytes) is not one: it is what an
    /// installer leaves when the voices are no longer wanted.
    var voiceArchive: URL? {
        guard let url = voiceArchivePlace,
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
              size.int64Value >= 28 else { return nil }
        return url
    }

    /// Remove what an installer left of voices it took back: the emptied
    /// archive, and its folder if nothing else is in it.
    static func clearWithdrawnVoices() {
        let fm = FileManager.default
        for language in allCases {
            guard let url = language.voiceArchivePlace, language.voiceArchive == nil,
                  fm.fileExists(atPath: url.path) else { continue }
            try? fm.removeItem(at: url)
            let folder = url.deletingLastPathComponent()
            if (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? fm.removeItem(at: folder) }
            NSLog("[app] Alyx: \(language.title) voices were withdrawn — the emptied archive is removed")
        }
    }

    /// What a device runs with before anyone has chosen: English, as before —
    /// unless German voices were put on it, which is somebody asking for German.
    static var standard: AlyxLanguage {
        AlyxLanguage.german.voiceArchive != nil ? .german : .english
    }

    static var stored: AlyxLanguage {
        // A launch can name it (KL_ALYX_LANGUAGE=english|german).
        if let e = getenv("KL_ALYX_LANGUAGE"),
           let v = allCases.first(where: { $0.engineName == String(cString: e) }) { return v }
        guard let n = UserDefaults.standard.object(forKey: storageKey) as? Int,
              let v = AlyxLanguage(rawValue: n) else { return standard }
        return v
    }

    /// Whether staged voices are to be heard. On unless switched off: they are
    /// on the device because somebody wanted them.
    static var voicesWanted: Bool {
        UserDefaults.standard.object(forKey: voicesKey) as? Bool ?? true
    }
}

/// Put the language search path into the game's gameinfo.gi, or take it out —
/// the header has the story. Only the one line is touched and the file keeps
/// its line endings; a file that does not look as expected is left alone, which
/// is a start with English voices and not a failed one. Staging the game again
/// brings Valve's file back, and the next start does this again.
@discardableResult
private func klAlyxSetVoicePath(_ wanted: Bool) -> Bool {
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return false }
    let file = docs.appendingPathComponent("lx/game/hlvr/gameinfo.gi")
    guard let data = try? Data(contentsOf: file),
          let text = String(data: data, encoding: .utf8) else { return false }
    var lines = text.components(separatedBy: "\n")
    let have = lines.contains { $0.contains("hlvr_*LANGUAGE*") }
    if have == wanted { return true }
    if wanted {
        // "SearchPaths", then its opening brace on a line of its own.
        guard let at = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "SearchPaths" }),
              at + 1 < lines.count,
              lines[at + 1].trimmingCharacters(in: .whitespacesAndNewlines) == "{" else {
            NSLog("[app] Alyx: gameinfo.gi has no SearchPaths block where one is expected — voices stay English")
            return false
        }
        lines.insert("\t\t\tGame_Language\t\thlvr_*LANGUAGE*" + (lines[at + 1].hasSuffix("\r") ? "\r" : ""), at: at + 2)
    } else {
        lines.removeAll { $0.contains("hlvr_*LANGUAGE*") }
    }
    do {
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return true
    } catch {
        NSLog("[app] Alyx: could not write gameinfo.gi: \(error)")
        return false
    }
}

/// Write the fidelity table the game reads in preference to its own: nine
/// levels, all of them the chosen scale and sample count. Returns false when the
/// game's directory is not there yet (nothing staged), which is a start that
/// fails for that reason and not this one.
@discardableResult
private func klAlyxWriteLadder(scale: String, samples: Int) -> Bool {
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return false }
    let dir = docs.appendingPathComponent("lx/game/hlvr")
    guard FileManager.default.fileExists(atPath: dir.path) else { return false }
    // The columns after the seventh are Glovebox's (github.com/glovebox-vr/
    // glovebox, packages/alyx/defaults/vr_fidelity_fixed_1.0.csv): ambient
    // occlusion and bloom on, the plain shadow filter and one sun cascade.
    // Which shaders a frame needs follows from these, and the pipeline list
    // that is compiled before the game starts (kl_fossilize.cpp) was recorded
    // with them.
    //
    // One of Glovebox's is left out: sc_disable_spotlight_shadows 1. With it
    // the flashlight was switched on and lit nothing (Vision Pro, 2026-10-11) —
    // it is a spotlight that casts shadows, and the engine seems to drop such a
    // light rather than draw it unshadowed. The pipelines its shadows need are
    // not in the list; the game compiles them at their first use and they are
    // recorded for the next start. KL_ALYX_SPOT_SHADOWS=0 puts the column back.
    var spot = true
    if let e = getenv("KL_ALYX_SPOT_SHADOWS"), atoi(e) == 0 { spot = false }
    var t = "hlvr,default,vr_msaa,vr_render_target_scale,min_gpu_memory,min_width,min_height,"
          + "r_ssao,r_post_bloom,r_high_quality_shadows,"
          + "vr_single_light_fast_path_sun_cascade_0_texels_per_world,"
          + "vr_single_light_fast_path_sun_cascade_1_texels_per_world,"
          + (spot ? "" : "sc_disable_spotlight_shadows,") + "\n"
    for level in 0...8 {
        t += "\(level),\(level == 5 ? "1" : ""),\(samples),\(scale),,,,1,1,0,3,0,\(spot ? "" : "1,")\n"
    }
    t += "end,,,,,,,,,,,,\(spot ? "" : ",")\n"
    do {
        try t.write(to: dir.appendingPathComponent("vr_fidelity_levels_override.csv"),
                    atomically: true, encoding: .utf8)
        return true
    } catch {
        NSLog("[app] Alyx: could not write the fidelity table: \(error)")
        return false
    }
}

/// The game's detail settings, once: what the game's own "video settings" file
/// (hlvr/cfg/deckard/video2.txt) says about particles, cached lights,
/// characters, eye occlusion, volumetric fog and texture filtering.
///
/// Left to itself the game measures the device at its first start and writes
/// the lowest of everything. The values here are Glovebox's (github.com/
/// glovebox-vr/glovebox, packages/alyx/defaults/video2-visionpro-demo.txt), and
/// they are here for the same reason as the last columns of the table above:
/// they decide which shaders a frame needs, and the pipeline list was recorded
/// with them. The picture's size, the sample count and the texture budget are
/// not among them and stay this app's.
///
/// Once, because the file is the game's and so are the player's later changes
/// in its Options: the values go into an existing file line by line and a
/// mark is left that it was done. Where the game has not written the file yet
/// it is written whole, without the mark — the game may replace it at that
/// first start, and the next one then finds a file to put the values into.
/// KL_ALYX_DETAIL=0 leaves the file alone.
private let klAlyxDetailKey = "alyx.detailSettings"
private let klAlyxDetail: [(String, String)] = [
    ("r_particle_max_detail_level", "1"), ("r_particle_max_draw_distance", "10000"),
    ("cl_particle_fallback_base", "1"), ("vr_enable_cached_lights", "1"),
    ("vr_character_level_placeholder", "2"), ("cl_enable_eye_occlusion", "1"),
    ("volume_fog_width", "128"), ("volume_fog_height", "128"), ("volume_fog_depth", "64"),
    ("g_ragdoll_maxcount", "5"), ("r_texturefilteringquality", "4"),
]
private let klAlyxVideoFile = """
"video.cfg"
{
\t"Version"\t\t"18"
\t"VendorID"\t\t"4203"
\t"DeviceID"\t\t"453115914"
\t"setting.cpu_level"\t\t"0"
\t"setting.mem_level"\t\t"1"
\t"setting.gpu_mem_level"\t\t"1"
\t"setting.knowndevice"\t\t"0"
\t"setting.defaultres"\t\t"16"
\t"setting.defaultresheight"\t\t"16"
\t"setting.refreshrate_numerator"\t\t"0"
\t"setting.refreshrate_denominator"\t\t"0"
\t"setting.fullscreen"\t\t"0"
\t"setting.coop_fullscreen"\t\t"0"
\t"setting.nowindowborder"\t\t"1"
\t"setting.mat_vsync"\t\t"0"
\t"setting.fullscreen_min_on_focus_loss"\t\t"1"
\t"setting.high_dpi"\t\t"0"
\t"setting.r_particle_max_detail_level"\t\t"1"
\t"setting.r_particle_max_draw_distance"\t\t"10000"
\t"setting.cl_particle_fallback_base"\t\t"1"
\t"setting.cl_particle_fallback_multiplier"\t\t"2"
\t"setting.r_high_quality_shadows"\t\t"0"
\t"setting.vr_single_light_fast_path_sun_cascade_0_texels_per_world"\t\t"3.000000"
\t"setting.vr_single_light_fast_path_sun_cascade_1_texels_per_world"\t\t"0.000000"
\t"setting.vr_shadow_level_placeholder"\t\t"0"
\t"setting.vr_enable_cached_lights"\t\t"1"
\t"setting.vr_aoproxy_enable"\t\t"0"
\t"setting.vr_character_level_placeholder"\t\t"2"
\t"setting.cl_enable_eye_occlusion"\t\t"1"
\t"setting.volume_fog_width"\t\t"128"
\t"setting.volume_fog_height"\t\t"128"
\t"setting.volume_fog_depth"\t\t"64"
\t"setting.r_light_flickering_enabled"\t\t"1"
\t"setting.vr_fast_hologram"\t\t"1"
\t"setting.cloth_rigid_update"\t\t"1"
\t"setting.g_ragdoll_maxcount"\t\t"5"
\t"setting.snd_steamaudio_reverb_order"\t\t"0"
\t"setting.snd_steamaudio_hybrid_reverb_transition_time"\t\t"0.300000"
\t"setting.snd_steamaudio_reverb_update_rate"\t\t"5"
\t"setting.snd_opvar_set_point_update_interval"\t\t"0.400000"
\t"setting.snd_steamaudio_dynamicpathing_max_samples"\t\t"1"
\t"setting.vr_depth_prepass"\t\t"0"
\t"setting.vr_stencil_hidden_pixels"\t\t"1"
\t"setting.vr_hidden_pixels_use_depth"\t\t"1"
\t"setting.r_texturefilteringquality"\t\t"4"
\t"setting.r_texture_stream_max_resolution"\t\t"2048"
\t"setting.r_texture_stream_resolution_bias_min"\t\t"0.8"
\t"setting.vr_perf_mode_override2"\t\t"2"
}

"""
private func klAlyxApplyDetail() -> String {
    if let e = getenv("KL_ALYX_DETAIL"), atoi(e) == 0 { return "left alone (KL_ALYX_DETAIL=0)" }
    if UserDefaults.standard.bool(forKey: klAlyxDetailKey) { return "the game's own (set once before)" }
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return "not set (no Documents)" }
    let game = docs.appendingPathComponent("lx/game/hlvr")
    guard FileManager.default.fileExists(atPath: game.path) else { return "not set (no game yet)" }
    let file = game.appendingPathComponent("cfg/deckard/video2.txt")
    guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) else {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try klAlyxVideoFile.write(to: file, atomically: true, encoding: .utf8)
            return "written whole (the game had no file yet)"
        } catch { return "NOT written: \(error.localizedDescription)" }
    }
    var lines = text.components(separatedBy: "\n")
    var set = 0, missing: [String] = []
    for (key, value) in klAlyxDetail {
        guard let at = lines.firstIndex(where: { $0.contains("\"setting.\(key)\"") }) else { missing.append(key); continue }
        let cr = lines[at].hasSuffix("\r") ? "\r" : ""
        let new = "\t\"setting.\(key)\"\t\t\"\(value)\"" + cr
        if lines[at] != new { lines[at] = new; set += 1 }
    }
    // A setting the game's file does not name goes in before the closing brace.
    if !missing.isEmpty, let close = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "}" }) {
        let cr = lines[close].hasSuffix("\r") ? "\r" : ""
        for key in missing.reversed() {
            let value = klAlyxDetail.first { $0.0 == key }!.1
            lines.insert("\t\"setting.\(key)\"\t\t\"\(value)\"" + cr, at: close)
            set += 1
        }
    }
    do {
        if set > 0 { try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8) }
        UserDefaults.standard.set(true, forKey: klAlyxDetailKey)
        return "\(set) of \(klAlyxDetail.count) value(s) put into the game's file"
    } catch { return "NOT written: \(error.localizedDescription)" }
}

/// The pipeline recorder's folder was Documents/klfz for two test builds (235,
/// 236) and is Documents/lx/klfz, where the installer puts the list. What a
/// device recorded in the old place goes along, and the old place goes away.
private func klAlyxMovePipelineFolder() {
    let fm = FileManager.default
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let old = docs.appendingPathComponent("klfz"), new = docs.appendingPathComponent("lx/klfz")
    guard fm.fileExists(atPath: old.path), fm.fileExists(atPath: docs.appendingPathComponent("lx").path) else { return }
    try? fm.createDirectory(at: new, withIntermediateDirectories: true)
    for name in ["recorded.foz", "device-info.json"] {
        let to = new.appendingPathComponent(name)
        if !fm.fileExists(atPath: to.path) { try? fm.moveItem(at: old.appendingPathComponent(name), to: to) }
    }
    try? fm.removeItem(at: old)
    NSLog("[app] Alyx: the pipeline folder moved to lx/klfz")
}

/// Say what the system thinks of the device's temperature, now and whenever it
/// changes. In a level every render pass of a frame — the compositor's and a
/// fixed post-processing pass among them — was measured getting slower together
/// by 40-50% over ninety seconds (KL_MTL_PROFILE, 2026-10-06), which is the GPU
/// being slowed and not the scene getting heavier; this is the line that says
/// whether heat is why.
private var klThermalObserver: NSObjectProtocol?
private func klThermalName(_ s: ProcessInfo.ThermalState) -> String {
    switch s {
    case .nominal:  return "nominal"
    case .fair:     return "fair"
    case .serious:  return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
}
func klWatchThermalState() {
    guard klThermalObserver == nil else { return }
    NSLog("[app] thermal state: \(klThermalName(ProcessInfo.processInfo.thermalState))")
    klThermalObserver = NotificationCenter.default.addObserver(
        forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { _ in
        NSLog("[app] thermal state -> \(klThermalName(ProcessInfo.processInfo.thermalState))")
    }
}

/// Put the chosen preset where the runtime reads it. Called at the start of a
/// boot, before kl_app_configure — the values are read once, later.
///
/// Overwrite 0: a variable the launch itself carried wins, so a scripted run
/// measures what it asked for whatever the window last showed. It also means
/// this is ahead of Documents/lx/env.txt, which is applied the same way after it:
/// a switch in the window that a file silently overrode would be a switch that
/// does nothing.
let klAlyxLoadingKey = "klepton.alyx.loadingScreens"
func klAlyxLoadingScreens() -> Bool {
    UserDefaults.standard.object(forKey: klAlyxLoadingKey) as? Bool ?? true
}

func klAlyxApply() {
    guard klIsAlyx() else { return }
    klWatchThermalState()
    let q = AlyxQuality.stored
    // The game's loading screen, where it waits for the trigger once a level
    // is ready. Off, the game is told to go on by itself.
    let loading = klAlyxLoadingScreens()
    // The language, and whether its voices come from a staged archive.
    AlyxLanguage.clearWithdrawnVoices()
    let language = AlyxLanguage.stored
    let voices = language.voiceArchive != nil && AlyxLanguage.voicesWanted
    let voicePath = klAlyxSetVoicePath(voices)
    setenv("KL_LX_ARGS_EXTRA",
           "+vr_fidelity_level_auto 0 +vr_fidelity_level \(q.fidelityLevel) "
           + "+r_texture_pool_size \(q.texturePoolMB)"
           // Textures come in at twice the engine's pace, as in Glovebox's
           // settings: fewer moments in which a surface is still coarse.
           + " +r_texture_stream_throttle_count 6 +r_texture_stream_throttle_amount 20"
           + AlyxPace.stored.arguments
           + (loading ? "" : " +hlvr_auto_dismiss_loading 1")
           + (language == .english ? "" : " -language \(language.engineName)"), 0)
    // The ceiling on the eye texture the game is offered. With the level fixed
    // the game allocates only what the level draws, so this no longer has to be
    // held down to protect memory at the small sizes.
    setenv("KL_OVRP_EYE_MAX", "3072", 0)
    let view = AlyxView.stored
    if view == .trimmed { setenv("KL_OVRP_EYE_TAN_MAX", "1.3", 0) }
    let fov = AlyxFoveation.stored
    if let k = fov.knobs {
        setenv("KL_VK_FOVEATE", k.edge, 0)
        setenv("KL_VK_FOVEATE_INNER", k.inner, 0)
    }
    let output = AlyxOutput.stored
    setenv("KL_CP_QUALITY", output.quality, 0)
    // The game's picture keeps its size: that is the Picture setting's.
    setenv("KL_CP_EYE_AT_FULL", "1", 0)
    NSLog("[app] Alyx output: \(output.title) (compositor quality \(output.quality))")
    let edges = AlyxEdges.stored
    let wrote = klAlyxWriteLadder(scale: q.scale, samples: edges.rawValue)
    NSLog("[app] Alyx detail settings: \(klAlyxApplyDetail())")
    klAlyxMovePipelineFolder()
    NSLog("[app] Alyx picture: \(q.title), edges \(edges.title), view \(view.title), foveation \(fov.title)\(wrote ? "" : " (table NOT written)"), language \(language.title) with \(voices ? "staged" : "the game's own") voices\(voicePath ? "" : " (gameinfo.gi NOT written)") — KL_LX_ARGS_EXTRA=\(String(cString: getenv("KL_LX_ARGS_EXTRA")))")
}

/// The three ways to play that most people choose between, each a set of the
/// five dials below. A set of dials that is none of them is "Custom".
enum AlyxPreset: Int, CaseIterable, Identifiable {
    case smooth, balanced, sharp
    var id: Int { rawValue }

    var name: String {
        switch self {
        case .smooth:   return klT("Smooth", "Flüssig")
        case .balanced: return klT("Balanced", "Ausgewogen")
        case .sharp:    return klT("Sharp", "Scharf")
        }
    }

    var note: String {
        switch self {
        case .smooth:
            return klT("The highest frame rate: the smallest picture and simpler edge smoothing.",
                       "Die höchste Bildrate: das kleinste Bild und einfachere Kantenglättung.")
        case .balanced:
            return klT("A sharp centre at a steady frame rate. What a new installation starts with.",
                       "Scharfe Bildmitte bei ruhiger Bildrate. Damit startet eine neue Installation.")
        case .sharp:
            return klT("A large picture, sharp to its edge and across the whole field of view. Hands and objects move less smoothly; looking around stays smooth.",
                       "Ein großes Bild, scharf bis zum Rand und über das ganze Sichtfeld. Hände und Gegenstände bewegen sich weniger flüssig; das Umsehen bleibt flüssig.")
        }
    }

    var dials: (quality: AlyxQuality, edges: AlyxEdges, view: AlyxView, foveation: AlyxFoveation, output: AlyxOutput) {
        switch self {
        // Balanced is what its first player settled on after trying the rest
        // (Vision Pro M5, 2026-10-11: the game held the compositor's 16.7 ms
        // a frame with it), and what every dial's own default is.
        case .smooth:   return (.smooth, .two, .trimmed, .strong, .light)
        case .balanced: return (.balanced, .four, .trimmed, .strong, .light)
        case .sharp:    return (.sharp, .four, .full, .on, .full)
        }
    }
}

struct AlyxPanel: View {
    @AppStorage(AlyxQuality.storageKey) private var quality = AlyxQuality.balanced.rawValue
    @AppStorage(AlyxEdges.storageKey) private var edges = AlyxEdges.standard.rawValue
    @AppStorage(AlyxView.storageKey) private var view = AlyxView.standard.rawValue
    @AppStorage(AlyxFoveation.storageKey) private var foveation = AlyxFoveation.standard.rawValue
    @AppStorage(AlyxOutput.storageKey) private var output = AlyxOutput.initial.rawValue
    /// "Custom" was chosen: the dials are shown even while they happen to be a preset's.
    @AppStorage("alyx.custom") private var customChosen = false
    @AppStorage(klAlyxLoadingKey) private var loadingScreens = true
    @AppStorage(AlyxPace.storageKey) private var pace = AlyxPace.game.rawValue
    @AppStorage(AlyxLanguage.storageKey) private var language = AlyxLanguage.standard.rawValue
    @AppStorage(AlyxLanguage.voicesKey) private var voices = true
    /// True once a run has started: the values were read at its start, so the
    /// controls then describe the NEXT launch and say so.
    let started: Bool

    private static let customTag = -1

    /// The preset the dials are set to, if they are one's.
    private var matching: AlyxPreset? {
        AlyxPreset.allCases.first {
            let d = $0.dials
            return d.quality.rawValue == quality && d.edges.rawValue == edges && d.view.rawValue == view
                && d.foveation.rawValue == foveation && d.output.rawValue == output
        }
    }

    private var preset: Binding<Int> {
        Binding(
            get: { customChosen ? Self.customTag : (matching?.rawValue ?? Self.customTag) },
            set: { tag in
                guard let p = AlyxPreset(rawValue: tag) else { customChosen = true; return }
                let d = p.dials
                quality = d.quality.rawValue; edges = d.edges.rawValue; view = d.view.rawValue
                foveation = d.foveation.rawValue; output = d.output.rawValue
                customChosen = false
            })
    }

    /// One dial of "Custom": its name, its choices, and a sentence on what it does.
    private func dial<T: Identifiable>(_ title: String, _ selection: Binding<Int>, _ cases: [T],
                                       name: @escaping (T) -> String, tag: @escaping (T) -> Int,
                                       note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Picker(title, selection: selection) {
                ForEach(cases) { c in Text(name(c)).tag(tag(c)) }
            }
            .pickerStyle(.segmented)
            Text(note).font(.footnote).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            KLSteamCloudPanel()
            GroupBox(klT("Walking speed", "Laufgeschwindigkeit")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(klT("Walking speed", "Laufgeschwindigkeit"), selection: $pace) {
                        ForEach(AlyxPace.allCases) { p in Text(p.name).tag(p.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text(klT("How fast you move with the stick, walking and in a fight. Higher is faster; “Game's own” leaves the game its two speeds. Teleporting is not affected.",
                             "Wie schnell du dich mit dem Stick bewegst, beim Gehen und im Kampf. Höher ist schneller; „Wie im Spiel“ lässt dem Spiel seine beiden Geschwindigkeiten. Teleportieren ist davon nicht betroffen."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(klT("Graphics", "Grafik")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(klT("Graphics", "Grafik"), selection: preset) {
                        ForEach(AlyxPreset.allCases) { p in Text(p.name).tag(p.rawValue) }
                        Text(klT("Custom", "Eigene")).tag(Self.customTag)
                    }
                    .pickerStyle(.segmented)
                    if preset.wrappedValue == Self.customTag {
                        Text(klT("Your own combination. In every row the choice on the left is the lightest and the one on the right the most demanding.",
                                 "Deine eigene Kombination. In jeder Zeile ist die Wahl links die leichteste und die rechts die aufwendigste."))
                            .font(.callout).foregroundStyle(.secondary)
                        dial(klT("Picture size", "Bildgröße"), $quality, AlyxQuality.allCases,
                             name: { $0.name }, tag: { $0.rawValue }, note: AlyxQuality.note)
                        dial(klT("Edge smoothing", "Kantenglättung"), $edges, AlyxEdges.allCases,
                             name: { $0.name }, tag: { $0.rawValue }, note: AlyxEdges.note)
                        dial(klT("Field of view", "Sichtfeld"), $view, AlyxView.ordered,
                             name: { $0.name }, tag: { $0.rawValue }, note: AlyxView.note)
                        dial("Foveated Rendering", $foveation, AlyxFoveation.ordered,
                             name: { $0.name }, tag: { $0.rawValue }, note: AlyxFoveation.note)
                        dial(klT("Display output", "Ausgabe aufs Display"), $output, AlyxOutput.ordered,
                             name: { $0.name }, tag: { $0.rawValue }, note: AlyxOutput.note)
                    } else if let p = matching {
                        Text(p.note).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(klT("Language", "Sprache")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(klT("Language", "Sprache"), selection: $language) {
                        ForEach(AlyxLanguage.allCases) { l in Text(l.title).tag(l.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    let chosen = AlyxLanguage(rawValue: language) ?? .english
                    let staged = chosen.voiceArchive != nil
                    if staged {
                        Toggle(klT("\(chosen.title) voices", "Stimmen auf \(chosen.title)"), isOn: $voices)
                    }
                    Text(chosen == .english
                         ? klT("Menus, subtitles and voices are English, as the game was recorded.",
                               "Menüs, Untertitel und Stimmen sind englisch, wie das Spiel aufgenommen wurde.")
                         : staged
                           ? (voices ? klT("Menus and subtitles are the game's own \(chosen.title); the voices are the fan-made voice-over that was installed with the game.",
                                           "Menüs und Untertitel bringt das Spiel selbst mit; die Stimmen sind die Fan-Vertonung, die mit dem Spiel installiert wurde.")
                                     : klT("Menus and subtitles are the game's own \(chosen.title); the voices stay English.",
                                           "Menüs und Untertitel bringt das Spiel selbst mit; die Stimmen bleiben englisch."))
                           : klT("Menus and subtitles are the game's own \(chosen.title); the voices stay English. A fan-made voice-over can be added when the game is installed from the Mac.",
                                 "Menüs und Untertitel bringt das Spiel selbst mit; die Stimmen bleiben englisch. Eine Fan-Vertonung lässt sich bei der Installation vom Mac aus hinzufügen."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(klT("After loading", "Nach dem Laden")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(klT("Wait for the trigger", "Auf den Trigger warten"), isOn: $loadingScreens)
                    Text(loadingScreens
                         ? klT("When a level is ready the game shows a card and starts when you pull the trigger.",
                               "Ist ein Level fertig geladen, zeigt das Spiel eine Karte und beginnt, wenn du den Trigger ziehst.")
                         : klT("The game continues by itself as soon as a level is ready.",
                               "Das Spiel geht von selbst weiter, sobald ein Level fertig geladen ist."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if started {
                Label(klT("The game is running: these apply the next time it is started.",
                          "Das Spiel läuft: Das gilt ab dem nächsten Start."),
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
