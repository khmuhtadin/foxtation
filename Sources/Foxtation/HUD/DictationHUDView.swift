import AppKit
import SwiftUI

enum HUDState {
    /// `warning`: text was pasted, but without cloud cleanup (limit, offline, license).
    case hidden, listening, processing, success, warning, error, cancelled

    /// State color: the border and the state icons.
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

/// Fixed pill geometry.
enum PillMetrics {
    static let width: CGFloat = 380
    static let height: CGFloat = 52
    static let faceSize: CGFloat = 36
    static let leadingInset: CGFloat = 10
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Everything the pill renders. Mic level is deliberately not published: the
/// waveform reads it from its own frame clock, so audio never rebuilds the view tree.
final class HUDModel: ObservableObject {
    @Published var state: HUDState = .hidden
    @Published var label = ""
    /// Quieter text after the label: "Slack", "· 24 words", "· raw text pasted".
    @Published var detail = ""
    /// Set while listening; the pill shows the elapsed time.
    @Published var listeningSince: Date?
    /// A small button at the trailing end, e.g. "Undo".
    @Published var actionTitle: String?
    /// Fades the pill in and out.
    @Published var isShown = false
    /// Bars stay hidden until the first real audio buffer arrives.
    @Published var waveformStarted = false

    let meter = LevelMeter()
    var reduceMotion = false
    /// Snapshots can't host NSVisualEffectView; draw a flat fill instead.
    var isSnapshot = false
    var onHover: ((Bool) -> Void)?
    var onAction: (() -> Void)?
    /// The × while listening.
    var onClose: (() -> Void)?
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

/// The window's content: the pill with room for its shadow. It fades in with a
/// small lift and fades out; that's the only motion besides the level meter.
struct HUDContent: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        PillView(model: model)
            .opacity(model.isShown ? 1 : 0)
            .offset(y: model.isShown || model.reduceMotion ? 0 : 8)
            .frame(width: HUDWindowMetrics.size.width, height: HUDWindowMetrics.size.height)
    }
}

struct PillView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        let state = model.state
        HStack(spacing: 12) {
            FoxFace()
                .frame(width: PillMetrics.faceSize, height: PillMetrics.faceSize)

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

            ZStack {
                WaveformView(meter: model.meter, state: state, paused: !model.isShown)
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

            if let action = model.actionTitle {
                Button { model.onAction?() } label: {
                    Text(action)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                        .padding(.vertical, 2)  // a 28pt tall hit area
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button { model.onClose?() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .padding(4)  // a 28pt hit area around the 20pt circle
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel (esc)")
            .accessibilityLabel("Cancel dictation (esc)")
            .opacity(state.showsClose ? 1 : 0)
            .frame(width: state.showsClose ? nil : 0)
            .clipped()
        }
        .padding(.leading, PillMetrics.leadingInset)
        .padding(.trailing, state.showsClose ? 12 : 16)  // the × carries 4pt of hit area
        .frame(width: PillMetrics.width, height: PillMetrics.height)
        .background(background)
        // State border: one crisp line in the state color, no glow.
        .overlay(
            Capsule().strokeBorder(state.accent.opacity(0.85), lineWidth: 1.5)
                .animation(.easeOut(duration: 0.15), value: state)
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

/// The fox's face, still.
struct FoxFace: View {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "face", withExtension: "png", subdirectory: "Fox") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().interpolation(.high)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        } else {
            Color.clear
        }
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
