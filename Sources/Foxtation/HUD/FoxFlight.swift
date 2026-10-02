import AppKit
import SwiftUI

/// The entry choreography from docs/hud/storyboard.png, scenes 1–7:
/// face → orb → pill expands → fox emerges and waves → flies out toward the
/// viewer → loops back down-left → swings in and lands on the pill's face slot.
///
/// Everything is a pure function of one clock (seconds since `start`), so a
/// frame can be rendered at any time, interrupted at any time, and nothing is
/// allocated per frame beyond paths.
final class FoxFlight: ObservableObject {

    /// When the fox sits exactly on the face slot (story time).
    static let landing: Double = 1.8
    /// The sprite has faded into the slot fox by now (story time).
    static let end: Double = 1.95

    /// The orb holds and bounces this long before it stretches into the pill.
    /// Story time pauses at `orbAt` meanwhile; everything after shifts by it.
    static let orbHold: Double = 0.4
    static let orbAt: Double = 0.3
    static let landingReal = landing + orbHold
    static let endReal = end + orbHold

    /// Real seconds since start → story time used by every keyframe below.
    static func story(_ real: Double) -> Double {
        real < orbAt ? real : max(orbAt, real - orbHold)
    }

    /// While the orb waits it drops in and bounces like a ball: height above
    /// its resting spot (points), plus a squash on each impact.
    static func orbHop(_ real: Double) -> (lift: CGFloat, squash: CGFloat) {
        let tau = max(0, real - 0.15)
        let decay = exp(-4 * tau)
        let swing = abs(cos(.pi * tau / 0.2))  // impacts at 0.1, 0.3, 0.5s
        let lift = 22 * decay * swing
        let squash = decay * max(0, 1 - swing * 3)  // only right around an impact
        return (CGFloat(lift), CGFloat(squash))
    }

    @Published private(set) var isFlying = false
    private(set) var startDate = Date()
    /// Flies to the left instead of the right (pill on the right screen edge).
    private(set) var mirrored = false
    /// Snapshots render a fixed moment instead of the live clock.
    private(set) var fixedTime: Double?

    func start(mirrored: Bool) {
        self.mirrored = mirrored
        startDate = Date()
        fixedTime = nil
        isFlying = true
    }

    func stop() {
        isFlying = false
    }

    func freeze(at time: Double, mirrored: Bool) {
        self.mirrored = mirrored
        fixedTime = time
        isFlying = true
    }

    func time(at date: Date) -> Double {
        fixedTime ?? date.timeIntervalSince(startDate)
    }

    // MARK: - Sprites

    enum Pose: String, CaseIterable {
        case face, emergeWave = "emerge-wave", flyOut = "fly-out", flyBack = "fly-back", swingIn = "swing-in"
    }

    /// Loaded once; Resources/Fox is copied into the bundle by build.sh.
    static let images: [Pose: NSImage] = {
        var images: [Pose: NSImage] = [:]
        for pose in Pose.allCases {
            if let url = Bundle.main.url(forResource: pose.rawValue, withExtension: "png", subdirectory: "Fox"),
               let image = NSImage(contentsOf: url) {
                images[pose] = image
            }
        }
        return images
    }()

    /// Full-body poses are drawn at this size (points) times the keyframe scale.
    static let spriteSize: CGFloat = 92

    // MARK: - Path

    /// Pill-relative: origin at the pill's center, y grows down.
    private struct Key {
        var t: Double
        var x: CGFloat
        var y: CGFloat
        var scale: CGFloat
        var rotation: Double
        /// Flipped to the other side when the flight is mirrored.
        var mirrors = false
    }

    private static let slot = HUDMetrics.foxSlotOffset
    private static let landingScale = HUDMetrics.foxSlotSize / spriteSize

    private static let keys: [Key] = [
        // 4 · emerge from the pill's left side and wave
        Key(t: 0.55, x: -112, y: 6, scale: 0.35, rotation: -8),
        Key(t: 0.68, x: -118, y: -10, scale: 1.0, rotation: 0),
        Key(t: 0.86, x: -110, y: -14, scale: 1.0, rotation: 0),
        // 5 · fly out up-right, growing toward the viewer
        Key(t: 1.03, x: 30, y: -30, scale: 1.2, rotation: 8, mirrors: true),
        Key(t: 1.22, x: 172, y: -20, scale: 1.35, rotation: 4, mirrors: true),
        // 6 · loop back down-left, shrinking away
        Key(t: 1.38, x: 112, y: 50, scale: 1.1, rotation: -6, mirrors: true),
        Key(t: 1.54, x: -60, y: 76, scale: 0.9, rotation: -10),
        // 7 · swing in and settle into the face slot
        Key(t: 1.65, x: -140, y: 42, scale: 0.78, rotation: 4),
        Key(t: 1.74, x: -138, y: 8, scale: 0.5, rotation: 0),
        Key(t: landing, x: slot.x, y: slot.y, scale: landingScale, rotation: 0),
    ]

    /// Which bitmap shows when; neighbours cross-fade over 100ms.
    private static let poses: [(pose: Pose, from: Double, to: Double)] = [
        (.emergeWave, 0.55, 0.86), (.flyOut, 0.86, 1.24), (.flyBack, 1.24, 1.54),
        (.swingIn, 1.54, 1.70), (.face, 1.70, .infinity),
    ]

    /// Position, scale and banking at time `t` (pill-relative).
    private static func sample(_ t: Double, mirrored: Bool) -> (point: CGPoint, scale: CGFloat, rotation: Double) {
        let points = keys.map { CGPoint(x: mirrored && $0.mirrors ? -$0.x : $0.x, y: $0.y) }
        let t = min(max(t, keys[0].t), landing)
        var i = 0
        while i < keys.count - 2 && t > keys[i + 1].t { i += 1 }
        let a = keys[i], b = keys[i + 1]
        let u = (t - a.t) / (b.t - a.t)

        // Catmull-Rom through the keyframes, so the path stays smooth.
        let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
        let u1 = CGFloat(u), u2 = u1 * u1, u3 = u2 * u1
        func axis(_ v0: CGFloat, _ v1: CGFloat, _ v2: CGFloat, _ v3: CGFloat) -> CGFloat {
            0.5 * (2 * v1 + (v2 - v0) * u1 + (2 * v0 - 5 * v1 + 4 * v2 - v3) * u2 + (3 * v1 - v0 - 3 * v2 + v3) * u3)
        }
        let point = CGPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y))

        let s = smooth(u)
        let scale = a.scale + (b.scale - a.scale) * CGFloat(s)
        var rotation = a.rotation + (b.rotation - a.rotation) * s
        if mirrored && a.mirrors && b.mirrors { rotation = -rotation }
        // The paw wave: two small wiggles while emerging.
        if t > 0.62 && t < 0.86 { rotation += 6 * sin(4 * .pi * (t - 0.62) / 0.24) }
        return (point, scale, rotation)
    }

    struct Sprite {
        var pose: Pose
        var center: CGPoint   // window coordinates
        var size: CGFloat
        var rotation: Double
        var opacity: Double
        var flipped: Bool
    }

    static func sprites(at t: Double, mirrored: Bool) -> [Sprite] {
        let pill = CGPoint(x: HUDMetrics.pillRect.midX, y: HUDMetrics.pillRect.midY)
        var sprites: [Sprite] = []

        // 1 · the face pops in where the pill will be, then becomes the orb.
        if t < 0.3 {
            let pop = 0.6 + 0.4 * easeOutBack(clamp(t / 0.15), overshoot: 1.2)
            let opacity = ramp(t, 0, 0.08) * (1 - ramp(t, 0.15, 0.27))
            sprites.append(Sprite(pose: .face, center: pill, size: 28 * pop, rotation: 0, opacity: opacity, flipped: false))
        }

        // 4–7 · the flight.
        guard t >= keys[0].t && t < end else { return sprites }
        let (point, scale, rotation) = sample(t, mirrored: mirrored)
        let center = CGPoint(x: pill.x + point.x, y: pill.y + point.y)
        let fadeIntoSlot = 1 - ramp(t, landing, end)
        for (index, entry) in poses.enumerated() {
            let fadeIn = index == 0 ? ramp(t, entry.from, entry.from + 0.07) : ramp(t, entry.from - 0.05, entry.from + 0.05)
            let fadeOut = 1 - ramp(t, entry.to - 0.05, entry.to + 0.05)
            let opacity = fadeIn * fadeOut * fadeIntoSlot
            guard opacity > 0.001 else { continue }
            let flipped = mirrored && (entry.pose == .flyOut || entry.pose == .flyBack)
            sprites.append(Sprite(pose: entry.pose, center: center, size: spriteSize * scale,
                                  rotation: rotation, opacity: opacity, flipped: flipped))
        }
        return sprites
    }

    /// Where the flight ends, in window coordinates.
    static var landingPoint: CGPoint {
        let point = sample(landing, mirrored: false).point
        return CGPoint(x: HUDMetrics.pillRect.midX + point.x, y: HUDMetrics.pillRect.midY + point.y)
    }

    // MARK: - Pill and trails

    /// The real pill fades in over the expanding orb.
    static func pillReveal(_ t: Double) -> Double { ramp(t, 0.5, 0.62) }

    static let orbSize: CGFloat = 26

    /// 2–3 · the orb, and the orb stretching into the pill.
    static func morph(_ t: Double) -> (size: CGSize, progress: Double, opacity: Double) {
        let u = clamp((t - 0.3) / 0.25)
        let width = orbSize + (HUDMetrics.pillSize.width - orbSize) * CGFloat(easeOutBack(u, overshoot: 0.6))
        let height = orbSize + (HUDMetrics.pillSize.height - orbSize) * CGFloat(1 - pow(1 - u, 3))
        return (CGSize(width: width, height: height), u, ramp(t, 0.15, 0.25) * (1 - ramp(t, 0.55, 0.66)))
    }

    /// Sparkles around the fly-out: (pill-relative point, radius, opacity).
    static func sparkles(_ t: Double, mirrored: Bool) -> [(CGPoint, CGFloat, Double)] {
        let angles: [Double] = [0.4, 1.5, 2.7, 3.9, 5.1]
        let cx: CGFloat = mirrored ? -95 : 95
        return angles.enumerated().map { index, angle in
            let start = 0.92 + Double(index) * 0.06
            let life = ramp(t, start, start + 0.08) * (1 - ramp(t, start + 0.22, start + 0.34))
            let point = CGPoint(x: cx + 128 * CGFloat(cos(angle)), y: -24 + 30 * CGFloat(sin(angle)))
            return (point, CGFloat(1.4 + Double(index % 3) * 0.5), life)
        }
    }

    // MARK: - Window margins

    /// Everything the flight can reach, pill-relative, in both directions.
    static let margins: NSEdgeInsets = {
        let half = CGSize(width: HUDMetrics.pillSize.width / 2, height: HUDMetrics.pillSize.height / 2)
        var bounds = CGRect(x: -half.width, y: -half.height, width: half.width * 2, height: half.height * 2)
        for mirrored in [false, true] {
            var t = keys[0].t
            while t <= landing {
                let (point, scale, _) = sample(t, mirrored: mirrored)
                let r = spriteSize * scale / 2 + 14  // + glow
                bounds = bounds.union(CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
                t += 0.01
            }
            for (point, _, _) in sparkles(1, mirrored: mirrored) {
                bounds = bounds.union(CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
            }
        }
        return NSEdgeInsets(top: ceil(-half.height - bounds.minY), left: ceil(-half.width - bounds.minX),
                            bottom: ceil(bounds.maxY - half.height), right: ceil(bounds.maxX - half.width))
    }()

    // MARK: - Easing

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    static func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double { smooth(clamp((t - a) / (b - a))) }
    static func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
    static func easeOutBack(_ x: Double, overshoot s: Double) -> Double {
        let v = x - 1
        return 1 + (s + 1) * v * v * v + s * v * v
    }
}

// MARK: - Window content

/// The window's root view: the pill, plus the flight around it while it runs.
struct HUDStage: View {
    @ObservedObject var model: HUDModel
    @ObservedObject var flight: FoxFlight

    private static let glow = Color(red: 0.62, green: 0.70, blue: 1.0)

    var body: some View {
        TimelineView(.animation(paused: !flight.isFlying)) { context in
            let raw = flight.isFlying ? flight.time(at: context.date) : FoxFlight.endReal
            let t = FoxFlight.story(raw)
            let pill = CGPoint(x: HUDMetrics.pillRect.midX, y: HUDMetrics.pillRect.midY)
            ZStack {
                if flight.isFlying { trails(t, pill: pill) }

                PillView(model: model)
                    .scaleEffect(model.pillScale)
                    .offset(model.pillOffset)
                    .opacity(model.pillOpacity * (flight.isFlying ? FoxFlight.pillReveal(t) : 1))
                    .position(pill)

                if flight.isFlying {
                    orb(t, raw: raw).position(pill)
                    ForEach(FoxFlight.sprites(at: t, mirrored: flight.mirrored), id: \.pose) { sprite in
                        if let image = FoxFlight.images[sprite.pose] {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: sprite.size, height: sprite.size)
                                .scaleEffect(x: sprite.flipped ? -1 : 1, y: 1)
                                .rotationEffect(.degrees(sprite.rotation), anchor: .bottom)
                                .shadow(color: Self.glow.opacity(0.7), radius: sprite.size * 0.1)
                                .opacity(sprite.opacity)
                                .position(sprite.center)
                        }
                    }
                }
            }
            .frame(width: HUDMetrics.windowSize.width, height: HUDMetrics.windowSize.height)
        }
        .coordinateSpace(name: "hud")
    }

    /// 2–3 · a glowing orb that stretches into a dark capsule under the pill.
    @ViewBuilder private func orb(_ t: Double, raw: Double) -> some View {
        let morph = FoxFlight.morph(t)
        // The bounce fades out as the orb starts stretching, so there's no jump.
        let hop = FoxFlight.orbHop(raw)
        let still = CGFloat(1 - morph.progress)
        let squash = 0.28 * hop.squash * still
        if morph.opacity > 0 {
            ZStack {
                Capsule().fill(RadialGradient(colors: [Color.white, Color(red: 0.93, green: 0.94, blue: 1),
                                                       Color(red: 0.80, green: 0.82, blue: 0.97)],
                                              center: .center, startRadius: 0, endRadius: morph.size.width / 2))
                    .opacity(1 - morph.progress)
                Capsule().fill(Color(red: 0.055, green: 0.08, blue: 0.2).opacity(0.94))
                    .opacity(morph.progress)
                Capsule().strokeBorder(Self.glow.opacity(0.8), lineWidth: 1.5)
                    .opacity(morph.progress)
            }
            .frame(width: morph.size.width, height: morph.size.height)
            .shadow(color: Color(red: 0.86, green: 0.87, blue: 1).opacity(0.85), radius: 16 - 10 * morph.progress)
            .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .bottom)
            .offset(y: -hop.lift * still)
            .opacity(morph.opacity)
        }
    }

    /// 5 · a few sparkles around the fly-out.
    @ViewBuilder private func trails(_ t: Double, pill: CGPoint) -> some View {
        ZStack {
            ForEach(Array(FoxFlight.sparkles(t, mirrored: flight.mirrored).enumerated()), id: \.offset) { _, sparkle in
                let (point, radius, opacity) = sparkle
                if opacity > 0 {
                    Circle().fill(Color.white)
                        .frame(width: radius * 2, height: radius * 2)
                        .shadow(color: Self.glow, radius: 3)
                        .opacity(opacity)
                        .position(x: pill.x + point.x, y: pill.y + point.y)
                }
            }
        }
    }
}
