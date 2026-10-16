import AppKit
import SwiftUI

enum HUDState {
    /// `warning`: text was pasted, but without cloud cleanup (limit, offline, license).
    case hidden, listening, processing, success, warning, error, cancelled

    var foxState: FoxState {
        switch self {
        case .listening: return .listen
        case .processing: return .think
        case .success: return .success
        case .error: return .error
        case .hidden, .cancelled, .warning: return .idle
        }
    }

    /// State color: the glowing border, its halo and the waveform.
    var accent: Color {
        switch self {
        case .listening:  return Color(hex: 0x6C7DF2)
        case .processing: return Color(hex: 0xFF9F0A)
        case .success:    return Color(hex: 0x30D158)
        case .warning:    return Color(hex: 0xFF9F0A)
        case .error:      return Color(hex: 0xFF453A)
        case .hidden, .cancelled: return Color.white.opacity(0.2)
        }
    }

    /// Waveform bars run left to right across this pair.
    var waveColors: [Color] {
        switch self {
        case .processing: return [Color(hex: 0xFF8A00), Color(hex: 0xFFB340)]
        default:          return [Color(hex: 0x5B6FE0), Color(hex: 0x7F8CFF)]
        }
    }

    var labelColor: Color {
        switch self {
        case .success: return Color(hex: 0x30D158)
        case .error:   return Color(hex: 0xFF8A80)
        default:       return Color.white
        }
    }

    var showsWaveform: Bool { self == .listening || self == .processing }
    var showsClose: Bool { self == .listening }
}

/// Where things sit inside the pill, measured from its leading edge. The entry
/// choreography lands the flying fox on `faceCenterX` (vertically centered).
enum PillMetrics {
    static var width: CGFloat { HUDMetrics.pillSize.width }
    static var height: CGFloat { HUDMetrics.pillSize.height }
    static let faceSize: CGFloat = 36
    static let leadingInset: CGFloat = 10
    static let faceCenterX: CGFloat = leadingInset + faceSize / 2
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Everything the pill renders. Mic level is deliberately not published: the
/// waveform and fox read it from their own frame clocks, so audio never
/// rebuilds the view tree.
final class HUDModel: ObservableObject {
    @Published var state: HUDState = .hidden
    @Published var label = ""
    /// Quieter text after the label: "Slack", "· 24 words", "· raw text pasted".
    @Published var detail = ""
    /// Set while listening; the pill shows the elapsed time.
    @Published var listeningSince: Date?
    /// A small button at the trailing end, e.g. "Undo".
    @Published var actionTitle: String?
    var onAction: (() -> Void)?
    /// The × while listening.
    var onClose: (() -> Void)?
    @Published var placement: HUDPlacement = .rightEdge

    @Published var pillOffset: CGSize = .zero
    @Published var pillScale: CGFloat = 1
    @Published var pillOpacity: Double = 0
    @Published var contentOpacity: Double = 0
    @Published var runnerProgress: Double = 0
    @Published var runnerOpacity: Double = 0
    @Published var slotOpacity: Double = 0
    @Published var slotScale: CGFloat = 1
    /// Bars stay hidden until the first real audio buffer arrives.
    @Published var waveformStarted = false
    @Published var isVisible = false

    let meter = LevelMeter()
    let fox = VectorFoxAnimator()
    var reduceMotion = false { didSet { fox.reduceMotion = reduceMotion } }
    /// Snapshots can't host NSVisualEffectView; draw a flat fill instead.
    var isSnapshot = false
    var onHover: ((Bool) -> Void)?

    // Entry bookkeeping (see FoxOrbitEntry.swift).
    var entryTask: Task<Void, Never>?
    var generation = 0
    var measuredSlotCenter: CGPoint?
}

/// Smoothed mic level: 0.15s attack, 0.35s release, advanced once per frame.
final class LevelMeter {
    var target: Double = 0
    private var value: Double = 0
    private var lastTick: Double = 0

    func value(at time: Double) -> Double {
        let dt = lastTick == 0 ? 0 : min(0.1, max(0, time - lastTick))
        lastTick = time
        let tau = target > value ? 0.15 : 0.35
        value += (target - value) * (1 - exp(-dt / tau))
        return value
    }

    /// Jumps straight to a level; used by previews and snapshots.
    func set(_ level: Double) {
        target = level
        value = level
    }
}

// MARK: - Window content

struct DictationHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        ZStack {
            PillView(model: model)
                .scaleEffect(model.pillScale)
                .offset(model.pillOffset)
                .opacity(model.pillOpacity)
                .position(x: HUDMetrics.pillRect.midX, y: HUDMetrics.pillRect.midY)

            model.fox.makeView(size: HUDMetrics.foxSlotSize)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                .modifier(OrbitRunner(progress: model.runnerProgress))
                .opacity(model.runnerOpacity)
                .allowsHitTesting(false)
        }
        .frame(width: HUDMetrics.windowSize.width, height: HUDMetrics.windowSize.height)
        .coordinateSpace(name: "hud")
    }
}

struct PillView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        let state = model.state
        HStack(spacing: 12) {
            FoxFaceView(fox: model.fox, paused: !model.isVisible)
                .frame(width: PillMetrics.faceSize, height: PillMetrics.faceSize)
                .background(GeometryReader { proxy in
                    let frame = proxy.frame(in: .named("hud"))
                    let _ = (model.measuredSlotCenter = CGPoint(x: frame.midX, y: frame.midY))
                    Color.clear
                })
                .scaleEffect(model.slotScale)
                .opacity(model.slotOpacity)

            HStack(spacing: 6) {
                Text(model.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(state.labelColor)
                    .layoutPriority(1)
                if let since = model.listeningSince, state == .listening {
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text(Self.elapsed(since, context.date))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                } else if !model.detail.isEmpty {
                    Text(model.detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(model.contentOpacity)

            ZStack {
                WaveformView(meter: model.meter, state: state, paused: !model.isVisible)
                    .frame(width: WaveformView.width, height: WaveformView.maxHeight)
                    .opacity(state.showsWaveform && model.waveformStarted ? 1 : 0)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, HUDState.success.accent)
                    .opacity(state == .success && model.actionTitle == nil ? 1 : 0)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(HUDState.warning.accent)
                    .opacity(state == .warning ? 1 : 0)
            }
            .frame(width: model.actionTitle == nil ? WaveformView.width : 0)
            .clipped()
            .opacity(model.contentOpacity)

            if let action = model.actionTitle {
                Button { model.onAction?() } label: {
                    Text(action)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .opacity(model.contentOpacity)
            }

            Button { model.onClose?() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel dictation (esc)")
            .opacity(model.contentOpacity * (state.showsClose ? 1 : 0))
            .frame(width: state.showsClose ? nil : 0)
            .clipped()
        }
        .padding(.leading, PillMetrics.leadingInset)
        .padding(.trailing, 16)
        .frame(width: PillMetrics.width, height: PillMetrics.height)
        .background(background)
        .overlay(
            // Glowing state border: a crisp stroke plus a blurred copy as the halo.
            ZStack {
                Capsule().strokeBorder(state.accent.opacity(0.55), lineWidth: 3).blur(radius: 5)
                Capsule().strokeBorder(state.accent.opacity(0.95), lineWidth: 1.5)
            }
            .animation(.easeInOut(duration: 0.25), value: state)
        )
        .onHover { model.onHover?($0) }
    }

    private static let navy = Color(hex: 0x0E1433)

    /// "0:07"
    static func elapsed(_ since: Date, _ now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(since)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder private var background: some View {
        if model.isSnapshot {
            Capsule().fill(Self.navy.opacity(0.96))
                .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
        } else {
            VisualEffectBackground()
                .overlay(Self.navy.opacity(0.9))
                .clipShape(Capsule())
                .background(Capsule().fill(Color.black.opacity(0.2))
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 5))
        }
    }
}

/// The seated fox: the face bitmap with a little state motion on top.
/// Listening bobs, processing tilts slowly, success hops once, error droops.
struct FoxFaceView: View {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "face", withExtension: "png", subdirectory: "Fox") else { return nil }
        return NSImage(contentsOf: url)
    }()

    let fox: VectorFoxAnimator
    var paused: Bool

    var body: some View {
        TimelineView(.animation(paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let since = context.date.timeIntervalSince(fox.changedAt)
            let motion = Self.motion(fox.state, time: t, since: since, still: fox.reduceMotion)
            Group {
                if let image = Self.image {
                    Image(nsImage: image).resizable().interpolation(.high)
                } else {
                    Color.clear
                }
            }
            .scaleEffect(x: motion.scaleX, y: motion.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(motion.rotation), anchor: .bottom)
            .offset(y: motion.dy)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
    }

    struct Motion {
        var dy: CGFloat = 0
        var rotation: Double = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
    }

    static func motion(_ state: FoxState, time t: Double, since: Double, still: Bool) -> Motion {
        if still { return Motion() }
        var m = Motion()
        switch state {
        case .listen:
            let phase = sin(2 * .pi * t / 1.2)
            m.dy = CGFloat(-1.2 * phase)
            m.rotation = 2 * sin(2 * .pi * t / 2.4)
            m.scaleY = 1 + CGFloat(0.02 * phase)
        case .think:
            m.rotation = 6 * sin(2 * .pi * t / 3)
        case .success:
            // One 620ms hop with squash and stretch, then rest.
            let p = min(1, max(0, since / 0.62))
            if p < 1 {
                m.dy = CGFloat(-7 * sin(.pi * p))
                let stretch = sin(.pi * p) * (p < 0.5 ? 0.07 : -0.06)
                m.scaleY = 1 + CGFloat(stretch)
                m.scaleX = 1 - CGFloat(stretch * 0.6)
            }
        case .error:
            m.dy = 1.5
            m.rotation = -4
        case .idle:
            m.dy = CGFloat(-0.6 * sin(2 * .pi * t / 3.4))
        }
        return m
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Five bars on a Canvas, redrawn by the frame clock. Nothing is allocated
/// per frame beyond the bar paths.
struct WaveformView: View {
    static let barWidth: CGFloat = 4
    static let gap: CGFloat = 4
    static let minHeight: CGFloat = 5
    static let maxHeight: CGFloat = 24
    static let width = barWidth * 5 + gap * 4

    private static let weights: [Double] = [0.55, 0.8, 1, 0.8, 0.55]
    private static let rates: [Double] = [0.9, 1.1, 0.7, 1.0, 0.8]

    let meter: LevelMeter
    var state: HUDState
    var paused: Bool

    var body: some View {
        TimelineView(.animation(paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let processing = state == .processing
            let level = processing ? 0.3 : meter.value(at: t)
            let colors = state.waveColors
            Canvas { ctx, size in
                for i in 0..<5 {
                    let wobble = processing
                        ? 0.5 + 0.5 * sin(2 * .pi * 1.4 * t - Double(i) * 0.9)  // slow travelling wiggle
                        : 0.7 + 0.3 * sin(2 * .pi * Self.rates[i] * t + Double(i) * 1.3)
                    let amount = min(1, level * Self.weights[i] * wobble * 1.6)
                    let h = Self.minHeight + (Self.maxHeight - Self.minHeight) * CGFloat(amount)
                    let rect = CGRect(x: CGFloat(i) * (Self.barWidth + Self.gap),
                                      y: (size.height - h) / 2,
                                      width: Self.barWidth, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: Self.barWidth / 2),
                             with: .color(i < 2 ? colors[0] : colors[1]))
                }
            }
        }
    }
}
