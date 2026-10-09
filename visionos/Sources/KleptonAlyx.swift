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

    var detail: String {
        switch self {
        case .smooth:
            return "The smallest picture and the highest frame rate (about 50 a second)."
        case .balanced:
            return "A larger picture at a lower frame rate."
        case .sharp:
            return "Close to the display's own size. Hands and objects move visibly "
                 + "less smoothly; looking around stays smooth."
        case .maximum:
            return "The largest picture the game draws, at the lowest frame rate. "
                 + "Distant textures are coarser to make room for it, and the system "
                 + "may still close the app in big scenes."
        }
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
    var id: Int { rawValue }

    var title: String { self == .two ? "2x" : "4x" }

    var detail: String {
        switch self {
        case .two:
            return "Edges are smoothed with two samples a pixel: faster, and what "
                 + "the larger pictures need to stay playable."
        case .four:
            return "Edges are smoothed with four samples a pixel, as the game "
                 + "ships: the cleanest edges at the highest cost."
        }
    }

    static var stored: AlyxEdges {
        // A launch can name it (KL_ALYX_MSAA=2|4), which is how the two are
        // measured against each other without touching the window.
        if let e = getenv("KL_ALYX_MSAA"), let v = AlyxEdges(rawValue: Int(atoi(e))) { return v }
        guard let n = UserDefaults.standard.object(forKey: storageKey) as? Int,
              let v = AlyxEdges(rawValue: n) else { return .two }
        return v
    }
}

enum AlyxView: Int, CaseIterable, Identifiable {
    case full, trimmed

    static let storageKey = "alyx.view"
    var id: Int { rawValue }

    var title: String { self == .full ? "Full" : "Trimmed" }

    var detail: String {
        switch self {
        case .full:
            return "Each eye is drawn as wide as the display reaches."
        case .trimmed:
            return "The outermost edge of view is left dark and not drawn — a "
                 + "sixth fewer pixels a frame at the same sharpness."
        }
    }

    static var stored: AlyxView {
        guard let n = UserDefaults.standard.object(forKey: storageKey) as? Int,
              let v = AlyxView(rawValue: n) else { return .full }
        return v
    }
}

enum AlyxFoveation: Int, CaseIterable, Identifiable {
    case off, on, strong

    static let storageKey = "alyx.foveation"
    /// What a fresh install runs with: the level that was not visible in play
    /// and saves about a third of the shading.
    static let standard = AlyxFoveation.on
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off:    return "Off"
        case .on:     return "Mild"
        case .strong: return "Strong"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "The whole picture is drawn at one density."
        case .on:
            return "Full density straight ahead, coarser toward the edge of view "
                 + "(about a third fewer pixels shaded). Not visible in a first test."
        case .strong:
            return "The same with a smaller sharp centre and a coarser edge (about "
                 + "half the pixels shaded). The edge is softer when looked at."
        }
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
    var t = "hlvr,default,vr_msaa,vr_render_target_scale,min_gpu_memory,min_width,min_height,\n"
    for level in 0...8 {
        t += "\(level),\(level == 5 ? "1" : ""),\(samples),\(scale),,,,\n"
    }
    t += "end,,,,,,,\n"
    do {
        try t.write(to: dir.appendingPathComponent("vr_fidelity_levels_override.csv"),
                    atomically: true, encoding: .utf8)
        return true
    } catch {
        NSLog("[app] Alyx: could not write the fidelity table: \(error)")
        return false
    }
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
    let edges = AlyxEdges.stored
    let wrote = klAlyxWriteLadder(scale: q.scale, samples: edges.rawValue)
    NSLog("[app] Alyx picture: \(q.title), edges \(edges.title), view \(view.title), foveation \(fov.title)\(wrote ? "" : " (table NOT written)"), language \(language.title) with \(voices ? "staged" : "the game's own") voices\(voicePath ? "" : " (gameinfo.gi NOT written)") — KL_LX_ARGS_EXTRA=\(String(cString: getenv("KL_LX_ARGS_EXTRA")))")
}

struct AlyxPanel: View {
    @AppStorage(AlyxQuality.storageKey) private var quality = AlyxQuality.balanced.rawValue
    @AppStorage(AlyxEdges.storageKey) private var edges = AlyxEdges.two.rawValue
    @AppStorage(AlyxView.storageKey) private var view = AlyxView.full.rawValue
    @AppStorage(AlyxFoveation.storageKey) private var foveation = AlyxFoveation.standard.rawValue
    @AppStorage(klAlyxLoadingKey) private var loadingScreens = true
    @AppStorage(AlyxLanguage.storageKey) private var language = AlyxLanguage.standard.rawValue
    @AppStorage(AlyxLanguage.voicesKey) private var voices = true
    /// True once a run has started: the values were read at its start, so the
    /// control then describes the NEXT launch and says so.
    let started: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Picture", selection: $quality) {
                ForEach(AlyxQuality.allCases) { q in
                    Text(q.title).tag(q.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text((AlyxQuality(rawValue: quality) ?? .balanced).detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Edges", selection: $edges) {
                ForEach(AlyxEdges.allCases) { e in
                    Text(e.title).tag(e.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text((AlyxEdges(rawValue: edges) ?? .two).detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("View", selection: $view) {
                ForEach(AlyxView.allCases) { v in
                    Text(v.title).tag(v.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text((AlyxView(rawValue: view) ?? .full).detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Foveation", selection: $foveation) {
                ForEach(AlyxFoveation.allCases) { f in
                    Text(f.title).tag(f.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text((AlyxFoveation(rawValue: foveation) ?? .standard).detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Language", selection: $language) {
                ForEach(AlyxLanguage.allCases) { l in
                    Text(l.title).tag(l.rawValue)
                }
            }
            .pickerStyle(.segmented)
            let chosen = AlyxLanguage(rawValue: language) ?? .english
            let staged = chosen.voiceArchive != nil
            if staged {
                Toggle("\(chosen.title) voices", isOn: $voices)
            }
            Text(chosen == .english
                 ? "Menus, subtitles and voices are English, as the game was recorded."
                 : staged
                   ? (voices ? "Menus and subtitles are the game's own \(chosen.title); the voices are the fan-made voice-over that was installed with the game."
                             : "Menus and subtitles are the game's own \(chosen.title); the voices stay English.")
                   : "Menus and subtitles are the game's own \(chosen.title); the voices stay English. "
                     + "A fan-made voice-over can be added when the game is installed from the Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Toggle("Loading screens", isOn: $loadingScreens)
            Text((loadingScreens
                  ? "The game shows its loading card and waits for a trigger pull when a level is ready."
                  : "The game continues by itself as soon as a level is ready.")
                 + (started ? "  All of these take effect the next time the game is started." : ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
