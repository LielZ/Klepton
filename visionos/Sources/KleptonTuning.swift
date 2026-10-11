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

    @Published var foveation: Bool {
        didSet { UserDefaults.standard.set(foveation, forKey: Self.key) }
    }

    /// Fraction of the eye-texture size the guest is told, 0.5...1.0. See
    /// kl_ovrp_set_render_scale_default for why this and not foveation is the
    /// lever for a Vulkan guest.
    @Published var renderScale: Double {
        didSet { UserDefaults.standard.set(renderScale, forKey: Self.scaleKey) }
    }

    /// The target's own default (targets.py "render_scale", baked into
    /// Info.plist as KLRenderScaleDefault). 1.0 for a bundle without the key.
    static let targetRenderScale: Double = {
        let s = Bundle.main.object(forInfoDictionaryKey: "KLRenderScaleDefault") as? String
        let v = s.flatMap(Double.init) ?? 1.0
        return (0.5...1.0).contains(v) ? v : 1.0
    }()

    private init() {
        // Never chosen means the target's default (targets.py "foveation",
        // KLFoveationDefault in Info.plist), which is off unless the target
        // says otherwise.
        foveation = (UserDefaults.standard.object(forKey: Self.key) as? Bool)
            ?? Self.targetFoveation
        // object(forKey:), so that "never chosen" is the target's default
        // rather than off.
        video = (UserDefaults.standard.object(forKey: Self.videoKey) as? Bool)
            ?? Self.targetVideo
        // object(forKey:) rather than double(forKey:): 0 is "never set" there,
        // and never set has to mean the target's default, not the minimum.
        let stored = UserDefaults.standard.object(forKey: Self.scaleKey) as? Double
        renderScale = stored.map { min(max($0, 0.5), 1.0) } ?? Self.targetRenderScale
    }

    /// Hand the stored choice to the runtime. Before kl_app_boot, so every
    /// reader of kl_glfb_foveation_wanted sees one answer for the whole run.
    func apply() {
        kl_glfb_set_foveation_default(foveation ? 1 : 0)
        let env = ProcessInfo.processInfo.environment["KL_VRR"]
        NSLog("[cp] foveated rendering: setting \(foveation ? "on" : "off")"
              + (env.map { " — overridden by KL_VRR=\($0)" } ?? ""))
        kl_ovrp_set_render_scale_default(Float(renderScale))
        kl_mediandk_set_video_default(video ? 1 : -1)
        NSLog("[cp] in-game video: \(video ? "on" : "runtime default") (target default \(Self.targetVideo ? "on" : "off"))")
        let envScale = ProcessInfo.processInfo.environment["KL_OVRP_RENDER_SCALE"]
        NSLog(String(format: "[cp] render resolution: setting %.0f%% (target default %.0f%%)",
                     renderScale * 100, Self.targetRenderScale * 100)
              + (envScale.map { " — overridden by KL_OVRP_RENDER_SCALE=\($0)" } ?? ""))
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
            Toggle("In-game videos", isOn: $rendering.video)
            Text("Tutorial and cutscene clips in Vulkan games. On by default "
                 + "where it has been confirmed to work; turn it off if a game "
                 + "crashes at a clip. Takes effect the next time the app "
                 + "starts.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Render resolution")
                Slider(value: $rendering.renderScale, in: 0.5...1.0, step: 0.05)
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
