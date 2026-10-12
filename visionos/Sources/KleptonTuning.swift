// Live controller-alignment tuning — the values in DEBUG_ENV_VARS.md's
// KL_SENSE_* and KL_XR_GRIP_* entries, made adjustable while wearing the
// headset instead of only at launch.
//
// **This exists because these numbers cannot be derived, only judged.** They
// are the gap between Apple's grip convention and the pose each guest was built
// against, and every guest applies its own controller-model transform on top —
// so the residual differs per title and the only instrument is a person looking
// at their hand. At a relaunch per candidate that is two minutes an iteration,
// which is why three targets were tuned by eye and none of them converged.
//
// The environment still sets the starting values, so a run that never opens the
// panel behaves exactly as it did before this file existed.
import SwiftUI
import simd

/// One complete set. Value semantics on purpose: the render thread reads a
/// whole snapshot, so it can never see one slider's new value beside another's
/// old one.
struct KLTune: Equatable {
    var sensePitch: Float = -37
    var sensePos   = SIMD3<Float>(-0.004, 0.02, -0.02)
    var sensePivot = SIMD3<Float>(0, 0, 0)
    var gripPitch: Float = 37
    var aimPitch:  Float = 0
    var gripPivot  = SIMD3<Float>(0, 0, 0)
    var gripPos    = SIMD3<Float>(0, 0, 0)
}

final class KleptonTuning: ObservableObject {
    static let shared = KleptonTuning()

    /// What the UI edits. Main thread only — SwiftUI requires it, and the
    /// render thread never touches it.
    @Published var ui = KLTune() { didSet { publish() } }

    /// ...and what the render thread reads, behind a lock. Two copies rather
    /// than one atomic because a tune is seven values and a controller drawn
    /// from half of one set and half of another is exactly the incoherence this
    /// whole area is about.
    private let lock = NSLock()
    private var live = KLTune()

    private init() {
        // Seeded from whatever is actually in force, not from these defaults:
        // a panel showing its own idea of the numbers while the runtime uses
        // the environment's is an instrument that lies on the first frame.
        var t = KLTune()
        t.sensePitch = KLSenseTune.hiltPitch
        t.sensePos   = KLSenseTune.shared[1].pos
        t.sensePivot = KLSenseTune.shared[1].pivot
        var gp: Float = 0, ap: Float = 0
        var pivot = [Float](repeating: 0, count: 3)
        var pos   = [Float](repeating: 0, count: 3)
        kl_openxr_grip_tune(&gp, &ap, &pivot, &pos)
        t.gripPitch = gp
        t.aimPitch  = ap
        t.gripPivot = SIMD3<Float>(pivot[0], pivot[1], pivot[2])
        t.gripPos   = SIMD3<Float>(pos[0], pos[1], pos[2])
        ui = t
        live = t
    }

    /// The snapshot the pose path uses. Called once per controller pose.
    func snapshot() -> KLTune {
        lock.lock(); defer { lock.unlock() }
        return live
    }

    private func publish() {
        lock.lock(); live = ui; lock.unlock()
        var pivot = [ui.gripPivot.x, ui.gripPivot.y, ui.gripPivot.z]
        var pos   = [ui.gripPos.x,   ui.gripPos.y,   ui.gripPos.z]
        kl_openxr_set_grip_tune(ui.gripPitch, ui.aimPitch, &pivot, &pos)
    }

    /// The current set as the environment lines that would reproduce it —
    /// which is the whole point of tuning live. A value found by dragging and
    /// not written down is a value found twice.
    func asEnvironment() -> String {
        func v(_ s: SIMD3<Float>) -> String {
            String(format: "%.3f,%.3f,%.3f", s.x, s.y, s.z)
        }
        return """
        KL_SENSE_PITCH=\(String(format: "%.3f", ui.sensePitch)) \
        KL_SENSE_POS="\(v(ui.sensePos))" \
        KL_SENSE_PIVOT="\(v(ui.sensePivot))" \
        KL_XR_GRIP_PITCH=\(String(format: "%.3f", ui.gripPitch)) \
        KL_XR_AIM_PITCH=\(String(format: "%.3f", ui.aimPitch)) \
        KL_XR_GRIP_PIVOT="\(v(ui.gripPivot))" \
        KL_XR_GRIP_POS="\(v(ui.gripPos))"
        """
    }
}

/// The panel. Lives in the boot window, which stays open beside the immersive
/// space — so the guest keeps rendering while these move.
struct TuningView: View {
    @ObservedObject private var tune = KleptonTuning.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controller alignment").font(.headline)
            Text("The X term is mirrored for the left hand. Grip-frame axes: "
                 + "−Z points, +Y up, +X right.")
                .font(.caption).foregroundStyle(.secondary)

            Group {
                deg("Sense pitch", $tune.ui.sensePitch, -90 ... 90)
                vec("Sense pivot", $tune.ui.sensePivot)
                vec("Sense offset", $tune.ui.sensePos)
            }
            Divider()
            Group {
                deg("OpenXR grip pitch", $tune.ui.gripPitch, -90 ... 90)
                deg("OpenXR aim pitch",  $tune.ui.aimPitch,  -90 ... 90)
                vec("OpenXR grip pivot", $tune.ui.gripPivot)
                vec("OpenXR grip offset", $tune.ui.gripPos)
            }
            Divider()
            HStack {
                Button("Log as environment") { NSLog("[tune] \(tune.asEnvironment())") }
                Button("Reset") { tune.ui = KLTune() }
            }
            // Shown as well as logged: reading a value off the panel beats
            // going to find the log for it, and this is what gets pasted.
            Text(tune.asEnvironment())
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func deg(_ label: String, _ value: Binding<Float>,
                     _ range: ClosedRange<Float>) -> some View {
        HStack {
            Text(label).frame(width: 170, alignment: .leading)
            Slider(value: value, in: range, step: 0.5)
            Text(String(format: "%6.1f°", value.wrappedValue))
                .font(.system(.body, design: .monospaced)).frame(width: 70)
        }
    }

    private func vec(_ label: String, _ value: Binding<SIMD3<Float>>) -> some View {
        HStack {
            Text(label).frame(width: 170, alignment: .leading)
            // ±12 cm covers every offset measured so far (the largest was 8 cm
            // on BONELAB) with room to find out it is not enough.
            axis("x", value.x); axis("y", value.y); axis("z", value.z)
        }
    }

    private func axis(_ name: String, _ value: Binding<Float>) -> some View {
        VStack(spacing: 2) {
            Slider(value: value, in: -0.12 ... 0.12, step: 0.005)
            Text("\(name) \(String(format: "%+.3f", value.wrappedValue))")
                .font(.system(.caption2, design: .monospaced))
        }
    }
}

// ---- Rendering: foveated guest rendering as a setting ----------------------
//
// KL_VRR, with a memory. Off by default on a headset: the guest's rate map is
// built once, before the guest boots, from wherever the display's own curve
// happened to be dense at that moment, and then it stays there — a fixed sharp
// patch that does not follow the eyes. Cheaper (about a third of the fragments)
// and visibly so. A person who wants the frame time back turns it on here.
//
// Applied at boot, because that is when the map is built; flipping the toggle
// in a running session is recorded for the next one.
final class KleptonRendering: ObservableObject {
    static let shared = KleptonRendering()
    private static let key = "klepton.foveation"
    private static let resetKey = "klepton.foveation.reset"

    private static let scaleKey = "klepton.renderScale"
    private static let videoKey = "klepton.video"

    /// Try in-game video even where the runtime would refuse it (a Vulkan
    /// guest — see klm_extractor_enabled). Starts at the target's own default.
    @Published var video: Bool {
        didSet { UserDefaults.standard.set(video, forKey: Self.videoKey) }
    }

    static let targetFoveation: Bool =
        (Bundle.main.object(forInfoDictionaryKey: "KLFoveationDefault") as? String) == "1"

    /// The target's default (targets.py "video", baked into Info.plist as
    /// KLVideoDefault). Off for a bundle without the key.
    static let targetVideo: Bool =
        (Bundle.main.object(forInfoDictionaryKey: "KLVideoDefault") as? String) == "1"

    /// The number a target raises to call a stored choice back once (targets.py
    /// "foveation_reset", KLFoveationReset in Info.plist). 0 for a bundle
    /// without the key: nothing is ever called back.
    static let targetFoveationReset: Int =
        (Bundle.main.object(forInfoDictionaryKey: "KLFoveationReset") as? String).flatMap(Int.init) ?? 0

    @Published var foveation: Bool {
        didSet { UserDefaults.standard.set(foveation, forKey: Self.key) }
    }

    /// Edge smoothing for a guest that draws its eyes into a multisampled
    /// multiview target (kl_glfb_multiview_ms): 0 is off, 2 and 4 are the
    /// sample counts. Beat Saber from 1.45 on is the one such guest; the two
    /// rows it comes under are named here because the version is only known
    /// once the game's files are read, after this page has been shown.
    private static let msaaKey = "klepton.msaa"
    static let targetHasMSAA: Bool = {
        let t = String(cString: kl_app_target_name_or_default())
        // Beat Saber (from 1.45 on) and Maestro: the guests kl_glfb.c's
        // klfb_msaa_guest names. Doom 3 was one of them for a release.
        return t == "beatsaber140" || t == "beatsaber" || t == "x6963344583787383"
    }()
    static let targetIsBeatSaber: Bool = {
        let t = String(cString: kl_app_target_name_or_default())
        return t == "beatsaber140" || t == "beatsaber"
    }()
    @Published var msaa: Int {
        didSet { UserDefaults.standard.set(msaa, forKey: Self.msaaKey) }
    }

    /// The frame rate a game is shown at, by way of the kind of immersive
    /// space it opens (Immersive.mixed): 100 is the mixed space, where this
    /// headset's panel runs at up to 100 Hz, and what every game starts from;
    /// 120 is the fully immersive one, at up to 120 Hz. visionOS halves either
    /// when a game cannot keep up (to 50 and to 60). The owner first had the
    /// switch taken out when the mixed space became the rule (1.1.7) and then
    /// asked for it back for all games: "den optionalen Switch zwischen 100hz
    /// (standard in mixed) und 120hz".
    ///
    /// Not for a mixed-reality game ("Nur für Mixed reality spiele will ich
    /// das nicht"): its room shows through a mixed space only. Those are the
    /// games passthrough is offered to (kl_ovrp.c, KL_OVRP_PASSTHROUGH) —
    /// TRIANGLE STRATEGY and Demeo.
    private static let rateKey = "klepton.maxRate"
    static let targetIsMixedReality: Bool = {
        let t = String(cString: kl_app_target_name_or_default())
        return t == "x5340130476095884" || t == "x3634830803298285"
            || klEnvOn("KL_OVRP_PASSTHROUGH", default: false)
    }()
    @Published var maxRate: Int {
        didSet { UserDefaults.standard.set(maxRate, forKey: Self.rateKey) }
    }
    /// The full space, as the person chose it. Never for a mixed-reality game.
    var wantsFullSpace: Bool { !Self.targetIsMixedReality && maxRate == 120 }

    /// The same for a Vulkan guest, which multisamples by itself and with a
    /// count of its own choosing: 0 leaves that, 4 raises it to four
    /// (kl_vulkan_set_force_samples_default). Which API a game renders with,
    /// and with how many samples, is only known once it has run — so a run
    /// leaves that number behind (`rememberRun`), and the picker is offered
    /// from the next start on, to a game that was seen with fewer than four.
    private static let vkMsaaKey = "klepton.vk.msaa"
    private static let vkGuestSamplesKey = "klepton.vk.guestSamples"
    static var vkGuestSamples: Int { UserDefaults.standard.integer(forKey: vkGuestSamplesKey) }
    /// What it starts at (targets.py "vk_msaa", KLVkMsaaDefault in Info.plist):
    /// 4 for a game that has been played that way, else the game's own count.
    static let targetVkMsaa: Int =
        (Bundle.main.object(forInfoDictionaryKey: "KLVkMsaaDefault") as? String) == "4" ? 4 : 0
    @Published var vkMsaa: Int {
        didSet { UserDefaults.standard.set(vkMsaa, forKey: Self.vkMsaaKey) }
    }
    /// Only where the setting does something: the game was seen multisampling
    /// with fewer than four samples (and is not one that is held at two).
    var offersVkMsaa: Bool { (2...3).contains(Self.vkGuestSamples) }

    /// How finely the compositor puts the finished picture on the display
    /// (KL_CP_QUALITY; `AlyxOutput` has the values and what was measured).
    /// Starts at the target's own (targets.py "output", KLOutputDefault): light
    /// for nearly every game. Alyx has its own in its panel.
    private static let outputKey = "klepton.output"
    static let targetOutput: AlyxOutput = {
        switch Bundle.main.object(forInfoDictionaryKey: "KLOutputDefault") as? String {
        case "light": return .light
        case "standard": return .standard
        default: return .full          // also a bundle without the key
        }
    }()
    @Published var output: Int {
        didSet { UserDefaults.standard.set(output, forKey: Self.outputKey) }
    }

    /// Raised when the two settings above get new defaults that copies with a
    /// stored choice should take once (the owner's wish for the first ones:
    /// "einmal beim ersten Installieren mit dem neuen Toolchain auf diese
    /// Einstellung setzen"). A choice made after that start stays.
    private static let pictureEpoch = 1
    private static let pictureEpochKey = "klepton.picture.epoch"

    /// Fraction of the eye-texture size the guest is told, 0.5...1.0. See
    /// kl_ovrp_set_render_scale_default for why this and not foveation is the
    /// lever for a Vulkan guest.
    @Published var renderScale: Double {
        didSet { UserDefaults.standard.set(renderScale, forKey: Self.scaleKey) }
    }

    /// How far down "Resolution" goes. Half for everything but Beat Saber from
    /// 1.45 on: with foveated rendering that game starts from the display's own
    /// size (5740 instead of 4000 across), where half is still a fine picture,
    /// and with edge smoothing a coarser one is worth trying.
    static var minRenderScale: Double { targetIsBeatSaber ? 0.25 : 0.5 }

    /// The target's own default (targets.py "render_scale", baked into
    /// Info.plist as KLRenderScaleDefault). 1.0 for a bundle without the key.
    static let targetRenderScale: Double = {
        let s = Bundle.main.object(forInfoDictionaryKey: "KLRenderScaleDefault") as? String
        let v = s.flatMap(Double.init) ?? 1.0
        return (0.5...1.0).contains(v) ? v : 1.0
    }()

    private init() {
        // A target whose default changed drops what this copy stored, once:
        // the number is remembered, so a choice made after that stays. A copy
        // that never stored one gets the new default without this.
        let applied = UserDefaults.standard.integer(forKey: Self.resetKey)
        if Self.targetFoveationReset > applied {
            let had = UserDefaults.standard.object(forKey: Self.key) as? Bool
            UserDefaults.standard.removeObject(forKey: Self.key)
            UserDefaults.standard.set(Self.targetFoveationReset, forKey: Self.resetKey)
            NSLog("[cp] foveated rendering: stored choice "
                  + (had.map { $0 ? "on" : "off" } ?? "none")
                  + " dropped once for this target's new default "
                  + (Self.targetFoveation ? "on" : "off")
                  + " (reset \(Self.targetFoveationReset), was \(applied))")
        }
        // Never chosen means the target's default (targets.py "foveation",
        // KLFoveationDefault in Info.plist), which is off unless the target
        // says otherwise.
        foveation = (UserDefaults.standard.object(forKey: Self.key) as? Bool)
            ?? Self.targetFoveation
        // Never chosen is 100; so is anything a test build stored besides 120.
        maxRate = (UserDefaults.standard.object(forKey: Self.rateKey) as? Int) == 120 ? 120 : 100
        // Never chosen is off (see kl_glfb_multiview_ms for why).
        msaa = (UserDefaults.standard.object(forKey: Self.msaaKey) as? Int)
            .flatMap { [0, 2, 4].contains($0) ? $0 : nil } ?? 0
        if UserDefaults.standard.integer(forKey: Self.pictureEpochKey) < Self.pictureEpoch {
            let had = (UserDefaults.standard.object(forKey: Self.vkMsaaKey) as? Int,
                       UserDefaults.standard.object(forKey: Self.outputKey) as? Int)
            UserDefaults.standard.removeObject(forKey: Self.vkMsaaKey)
            UserDefaults.standard.removeObject(forKey: Self.outputKey)
            UserDefaults.standard.set(Self.pictureEpoch, forKey: Self.pictureEpochKey)
            if had.0 != nil || had.1 != nil {
                NSLog("[cp] edge smoothing and display output: stored choices dropped once for "
                      + "this target's defaults (\(Self.targetVkMsaa == 0 ? "the game's own" : "4x"), "
                      + "\(Self.targetOutput.title))")
            }
        }
        vkMsaa = (UserDefaults.standard.object(forKey: Self.vkMsaaKey) as? Int)
            .map { $0 == 4 ? 4 : 0 } ?? Self.targetVkMsaa
        output = (UserDefaults.standard.object(forKey: Self.outputKey) as? Int)
            .flatMap { AlyxOutput(rawValue: $0)?.rawValue } ?? Self.targetOutput.rawValue
        // object(forKey:), so that "never chosen" is the target's default
        // rather than off.
        video = (UserDefaults.standard.object(forKey: Self.videoKey) as? Bool)
            ?? Self.targetVideo
        // object(forKey:) rather than double(forKey:): 0 is "never set" there,
        // and never set has to mean the target's default, not the minimum.
        let stored = UserDefaults.standard.object(forKey: Self.scaleKey) as? Double
        renderScale = stored.map { min(max($0, Self.minRenderScale), 1.0) } ?? Self.targetRenderScale
    }

    /// Hand the stored choice to the runtime. Before kl_app_boot, so every
    /// reader of kl_glfb_foveation_wanted sees one answer for the whole run.
    func apply() {
        kl_glfb_set_foveation_default(foveation ? 1 : 0)
        let env = ProcessInfo.processInfo.environment["KL_VRR"]
        NSLog("[cp] foveated rendering: setting \(foveation ? "on" : "off")"
              + (env.map { " — overridden by KL_VRR=\($0)" } ?? ""))
        if Self.targetHasMSAA {
            kl_glfb_set_msaa_default(Int32(msaa))
            let envAA = ProcessInfo.processInfo.environment["KL_GL_MSAA_MV"]
            NSLog("[cp] edge smoothing: setting " + (msaa == 0 ? "off" : "\(msaa)x")
                  + (envAA.map { " — overridden by KL_GL_MSAA_MV=\($0)" } ?? ""))
        }
        kl_vulkan_set_force_samples_default(Int32(vkMsaa))
        let envVk = ProcessInfo.processInfo.environment["KL_VK_FORCE_SAMPLES"]
        NSLog("[cp] edge smoothing (Vulkan): setting " + (vkMsaa == 0 ? "as the game makes it" : "\(vkMsaa)x")
              + " (target default " + (Self.targetVkMsaa == 0 ? "as the game makes it" : "\(Self.targetVkMsaa)x")
              + (Self.vkGuestSamples > 0 ? "; the game was last seen with \(Self.vkGuestSamples)x)" : ")")
              + (envVk.map { " — overridden by KL_VK_FORCE_SAMPLES=\($0)" } ?? ""))
        kl_ovrp_set_render_scale_default(Float(renderScale))
        kl_mediandk_set_video_default(video ? 1 : -1)
        NSLog("[cp] in-game video: \(video ? "on" : "runtime default") (target default \(Self.targetVideo ? "on" : "off"))")
        let envScale = ProcessInfo.processInfo.environment["KL_OVRP_RENDER_SCALE"]
        NSLog(String(format: "[cp] render resolution: setting %.0f%% (target default %.0f%%)",
                     renderScale * 100, Self.targetRenderScale * 100)
              + (envScale.map { " — overridden by KL_OVRP_RENDER_SCALE=\($0)" } ?? ""))
    }
}

/// "Record what the game waits for": the runtime's account of blocked threads
/// (KL_TRACE_CONDDUMP — kl_pthread_stuck_diag has what it writes), as a switch
/// a player can turn on for a game that stops in a loading screen. Off unless
/// chosen, and the choice stays with the game across updates of it.
enum KleptonDiagnostics {
    static let waitersKey = "klepton.diag.waiters"

    /// Into the environment, before kl_app_configure (see
    /// KleptonRendering.applyEnvironment). Never over the launch line's value.
    static func applyEnvironment() {
        guard UserDefaults.standard.bool(forKey: waitersKey) else { return }
        setenv("KL_TRACE_CONDDUMP", "1", 0)
        NSLog("[app] diagnostics: recording what the game waits for (KL_TRACE_CONDDUMP)")
    }
}

extension KleptonRendering {
    /// The part of the settings the runtime reads from its environment, which
    /// it starts doing in kl_app_configure — so this runs before that, where
    /// `apply` runs after. Never over a value given on the launch line.
    func applyEnvironment() {
        guard !klIsAlyx(), let o = AlyxOutput(rawValue: output), o != .full else { return }
        setenv("KL_CP_QUALITY", o.quality, 0)
        NSLog("[cp] display output: setting \(o.title) (render quality \(o.quality))")
    }

    /// As the app leaves: what this run learned that the next start window
    /// needs. Written through at once, because the process ends right after.
    func rememberRun() {
        let seen = Int(kl_vulkan_guest_samples())
        guard seen > 0, seen != Self.vkGuestSamples else { return }
        UserDefaults.standard.set(seen, forKey: Self.vkGuestSamplesKey)
        UserDefaults.standard.synchronize()
    }
}

struct RenderingView: View {
    @ObservedObject private var rendering = KleptonRendering.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Foveated rendering (sharp centre, cheaper edges)",
                   isOn: $rendering.foveation)
            Text("Fixed, not eye-tracked: the sharp region stays in place. Off "
                 + "renders the whole picture at full rate. Takes effect the "
                 + "next time the app starts.")
                .font(.caption).foregroundStyle(.secondary)
            if KleptonRendering.targetHasMSAA {
                Picker("Edge smoothing (MSAA)", selection: $rendering.msaa) {
                    Text("Off").tag(0); Text("2x").tag(2); Text("4x").tag(4)
                }
                .pickerStyle(.segmented)
            }
            if !klIsAlyx() {
                Picker(klT("Display output", "Ausgabe aufs Display"), selection: $rendering.output) {
                    ForEach(AlyxOutput.ordered) { Text($0.name).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Text(AlyxOutput.note + " "
                     + klT("Takes effect the next time the app starts.", "Wirkt beim nächsten Start der App."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("In-game videos", isOn: $rendering.video)
            Text("Tutorial and cutscene clips in Vulkan games. On by default "
                 + "where it has been confirmed to work; turn it off if a game "
                 + "crashes at a clip. Takes effect the next time the app "
                 + "starts.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Render resolution")
                Slider(value: $rendering.renderScale, in: KleptonRendering.minRenderScale...1.0, step: 0.05)
                Text(String(format: "%.0f%%", rendering.renderScale * 100))
                    .monospacedDigit().frame(width: 52, alignment: .trailing)
            }
            Text("Size of the picture the game renders, per axis. Lower it if "
                 + "looking around stutters: a game that saturates the GPU "
                 + "halves the rate head movement is corrected at. Takes "
                 + "effect the next time the app starts.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// The language the game is told the device speaks.
//
// A Quest game reads the device's language and many decide everything from it:
// Asgard's Wrath 2 has no language menu at all, text and voices follow the
// device. Here nothing sets a language for the guest, so every game was told
// en_US — and a player with a German headset and the German voice pack on it
// heard English. The device's own language is passed along (KleptonApp.init,
// KL_DEVICE_LANG) and this says whether the guest hears about it
// (KL_LOCALE_DEVICE, read in kl_jni_services.c).
//
// The default is the target's: the device's language where a game is known to
// depend on it (wrath2), English — what every game got so far — elsewhere, so
// that nothing changes language unasked. Read once, at boot.
final class KleptonLanguage: ObservableObject {
    static let shared = KleptonLanguage()
    private static let key = "klepton.gameLanguage"      // "device" | "en"

    static let targetDefault: String =
        String(cString: kl_app_target_name_or_default()) == "wrath2" ? "device" : "en"

    /// The device's first language in its own words ("Deutsch"), for the picker.
    static let deviceLanguageName: String = {
        guard let first = Locale.preferredLanguages.first else { return "English" }
        let loc = Locale(identifier: first)
        let code = loc.language.languageCode?.identifier ?? "en"
        return (loc.localizedString(forLanguageCode: code) ?? code).capitalized(with: loc)
    }()
    static let deviceIsEnglish: Bool =
        Locale.preferredLanguages.first?.lowercased().hasPrefix("en") ?? true

    @Published var choice: String {
        didSet { UserDefaults.standard.set(choice, forKey: Self.key) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.key)
        choice = (stored == "device" || stored == "en") ? stored! : Self.targetDefault
    }

    /// Before kl_app_boot. An explicit KL_LOCALE_DEVICE on a launch line wins.
    func apply() {
        setenv("KL_LOCALE_DEVICE", choice == "device" ? "1" : "0", 0)
        NSLog("[app] game language: \(choice == "device" ? "the device's (\(Self.deviceLanguageName))" : "English")"
              + " (target default \(Self.targetDefault))")
    }
}

struct GameLanguageView: View {
    @ObservedObject private var language = KleptonLanguage.shared

    var body: some View {
        // A device set to English has nothing to choose between.
        if !KleptonLanguage.deviceIsEnglish {
            VStack(alignment: .leading, spacing: 8) {
                Picker(klT("Game language", "Sprache des Spiels"), selection: $language.choice) {
                    Text(KleptonLanguage.deviceLanguageName).tag("device")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
                Text(klT("What the game is told this headset is set to. Games that offer the "
                         + "language use it for text and, where their voice pack is installed, "
                         + "for voices. Takes effect the next time the app starts.",
                         "Was dem Spiel als Sprache dieser Brille gemeldet wird. Spiele, die die "
                         + "Sprache anbieten, nutzen sie für Texte und – wenn ihr Sprachpaket "
                         + "installiert ist – für die Stimmen. Gilt ab dem nächsten Start der App."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// The name the game is told its player has.
//
// A Quest game takes the player's name from the Meta account and offers no way
// to change it — it is not the game's to change. Here the account is the
// offline user of kl_ovrplat.c, whose name was "kleptonplayer" for everybody.
// Demeo shows it as the player's name, and its owner asked for a way to set it
// (2026-10-13). Read once, at boot (KL_PLAT_USER_NAME).
//
// For a game that keeps an account of its own under the user's id (Demeo), the
// id is made here as well: one random number per installation instead of the
// same number for every player (KL_PLAT_USER_ID, kl_ovrplat_user_id_per_install).
final class KleptonPlayer: ObservableObject {
    static let shared = KleptonPlayer()
    private static let nameKey = "klepton.playerName"
    private static let idKey = "klepton.playerId"

    /// Only where a name goes anywhere: the games that get the offline user.
    static let offered: Bool = kl_ovrplat_offline_user_for(kl_app_target_name_or_default()) != 0
    static let ownId: Bool = kl_ovrplat_user_id_per_install(kl_app_target_name_or_default()) != 0

    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Self.nameKey) }
    }

    private init() {
        name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
    }

    /// Before kl_app_boot. A value on a launch line wins.
    func apply() {
        guard Self.offered else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { setenv("KL_PLAT_USER_NAME", n, 0) }
        if Self.ownId {
            var id = UInt64(UserDefaults.standard.string(forKey: Self.idKey) ?? "") ?? 0
            if id == 0 {
                id = UInt64.random(in: 1_000_000_000_001_000...8_999_999_999_999_999)
                UserDefaults.standard.set(String(id), forKey: Self.idKey)
            }
            setenv("KL_PLAT_USER_ID", String(id), 0)
        }
        NSLog("[app] player name: " + (n.isEmpty ? "not set (the runtime's own)" : "\"\(n)\"")
              + (Self.ownId ? "; the player id is this installation's own" : ""))
    }
}

struct PlayerNameView: View {
    @ObservedObject private var player = KleptonPlayer.shared

    var body: some View {
        if KleptonPlayer.offered {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(klT("Player name", "Spielername"))
                    TextField("kleptonplayer", text: $player.name)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(maxWidth: 320)
                }
                Text(klT("The name the game is told you have. Games that show a player name use it; "
                         + "where a game wants a name without spaces, letters, digits, '.', '_' "
                         + "and '-' are kept. Takes effect the next time the app starts.",
                         "Der Name, der dem Spiel für dich gemeldet wird. Spiele, die einen "
                         + "Spielernamen anzeigen, nutzen ihn; wo ein Spiel einen Namen ohne "
                         + "Leerzeichen erwartet, bleiben Buchstaben, Ziffern, '.', '_' und '-'. "
                         + "Gilt ab dem nächsten Start der App."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// Caches of LINKED GL programs that a game keeps in its own files.
//
// Unreal on GLES stores the driver's program binaries
// (android-files/ProgramBinaryCache/GLSL_ES3_1_ANDROID_<hash>) and at the next
// start hands them back with glProgramBinary instead of compiling its shaders.
// It names the cache after the GL strings, which here are ours and never change
// — while what answers glProgramBinary is ANGLE, and ANGLE refuses a binary made
// by another build of itself (its ANGLE_PROGRAM_VERSION is a hash over its own
// sources). Unreal treats that refusal as fatal: it asks to quit and then runs
// into its own missing programs. That is how Maestro stopped at start after
// toolchain 344 brought the first new ANGLE build since the game was installed
// (seen on the owner's headset, 2026-10-12: no shader compiled before the first
// draw, GL_INVALID_OPERATION on every glUseProgram, a burst of ForceQuit).
// Unity keeps such a cache too and compiles again when one is refused.
//
// So the cache does not outlive the build of the app that made it: when the
// bundle's build (version code and toolchain) differs from the one remembered,
// every ProgramBinaryCache folder in the game's files is removed before the
// guest boots, and the game compiles its programs once more.
enum KleptonProgramCaches {
    private static let key = "klepton.programCacheBuild"

    static func dropIfBuildChanged() {
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
        let defaults = UserDefaults.standard
        guard !build.isEmpty, defaults.string(forKey: key) != build else { return }
        let fm = FileManager.default
        var dropped: [String] = []
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let root = docs.appendingPathComponent("android-files")
            if let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                        options: [.skipsHiddenFiles]) {
                for case let url as URL in walk {
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    guard isDir else { continue }
                    if url.lastPathComponent == "ProgramBinaryCache" {
                        walk.skipDescendants()
                        if (try? fm.removeItem(at: url)) != nil {
                            dropped.append(url.path.replacingOccurrences(of: root.path + "/", with: ""))
                        }
                    } else if walk.level >= 5 {
                        // Unreal puts it at the top of the files or under
                        // UE4Game/<project>/<project>/Saved; no need to walk a
                        // game's whole content for it.
                        walk.skipDescendants()
                    }
                }
            }
        }
        defaults.set(build, forKey: key)
        NSLog("[app] program caches: build \(build) is new to this copy — "
              + (dropped.isEmpty ? "no ProgramBinaryCache found"
                                 : "removed \(dropped.joined(separator: ", "))"))
    }
}
