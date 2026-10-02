import SwiftUI

/// Mascot states. Raw values match the Rive state machine's `state` input.
enum FoxState: Int {
    case idle = 0, listen = 1, think = 2, success = 3, error = 4
}

/// Anything that can drive the fox's state and pose timing. The seated face
/// in the pill is the bitmap in Resources/Fox/face.png.
protocol FoxAnimating: AnyObject {
    func setState(_ state: FoxState)
    /// 0...1, already smoothed by the caller.
    func setAmplitude(_ amplitude: Double)
    func makeView(size: CGFloat) -> AnyView
}

/// Code-drawn fox built from the mascot construction notes. All motion is a
/// pure function of time, so it needs no per-state springs and allocates
/// nothing per frame.
final class VectorFoxAnimator: ObservableObject, FoxAnimating {

    /// Stops the frame clock while the HUD is hidden.
    @Published var isPaused = true
    var reduceMotion = false

    private(set) var state: FoxState = .idle
    private(set) var previousState: FoxState = .idle
    private(set) var changedAt = Date.distantPast
    private(set) var amplitude: Double = 0

    func setState(_ newState: FoxState) {
        guard newState != state else { return }
        previousState = state
        state = newState
        changedAt = Date()
    }

    /// Skips the cross-fade and any one-shot in flight (previews, snapshots).
    func jumpToSettled() {
        previousState = state
        changedAt = .distantPast
    }

    func setAmplitude(_ value: Double) {
        amplitude = max(0, min(1, value))
    }

    func makeView(size: CGFloat) -> AnyView {
        AnyView(VectorFoxView(animator: self, size: size))
    }

    /// Pose at a given moment, cross-fading 150ms out of the previous state.
    func pose(at date: Date) -> FoxPose {
        let since = date.timeIntervalSince(changedAt)
        let t = date.timeIntervalSinceReferenceDate
        let target = FoxPose.make(state, time: t, since: since, amplitude: amplitude, reduceMotion: reduceMotion)
        let blend = min(1, max(0, since / 0.15))
        if blend >= 1 { return target }
        let from = FoxPose.make(previousState, time: t, since: since + 10, amplitude: amplitude, reduceMotion: reduceMotion)
        return from.mixed(with: target, amount: blend * blend * (3 - 2 * blend))
    }
}

enum FoxEyes { case open, happy, closed, droopy }

/// Everything the drawing needs. Angles in degrees; ear angles are positive
/// when the ear tips lean outward.
struct FoxPose {
    var earOut: Double = 0
    var earDrop: Double = 0
    var headRotation: Double = 0
    var headDrop: Double = 0
    var eyes: FoxEyes = .open
    var eyeScaleY: Double = 1
    var bodyScaleY: Double = 1
    var bodyOffsetY: Double = 0

    static func make(_ state: FoxState, time t: Double, since: Double, amplitude: Double, reduceMotion: Bool) -> FoxPose {
        var pose = FoxPose()
        let period = state == .listen ? 2.2 : 3.4
        let breath = sin(2 * .pi * t / period)
        pose.bodyScaleY = 1 + 0.015 * breath
        pose.bodyOffsetY = -0.4 * breath

        switch state {
        case .idle:
            break
        case .listen:
            pose.earOut = -8 + 3 * amplitude
            pose.headRotation = -3.5
            if t.truncatingRemainder(dividingBy: 4.4) < 0.06 { pose.eyeScaleY = 0.1 }
        case .think:
            pose.earOut = 7
            pose.headRotation = 7
            pose.eyes = .closed
        case .success:
            pose.earOut = -11
            pose.eyes = .happy
            if since < 0.62 {
                let p = since / 0.62
                pose.bodyOffsetY = (reduceMotion ? -3 : -8) * sin(.pi * p)
                if !reduceMotion {
                    pose.bodyScaleY = keyframes(since, [(0, 1), (0.16, 1.07), (0.42, 1), (0.52, 0.94), (0.62, 1)])
                }
            }
        case .error:
            pose.earOut = 20
            pose.earDrop = 2
            pose.headDrop = 1.4
            pose.eyes = .droopy
            let phase = t.truncatingRemainder(dividingBy: 2.6)
            if phase < 0.36 { pose.eyeScaleY = 1 - 0.85 * sin(.pi * phase / 0.36) }
        }
        return pose
    }

    func mixed(with other: FoxPose, amount a: Double) -> FoxPose {
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * a }
        var out = FoxPose()
        out.earOut = lerp(earOut, other.earOut)
        out.earDrop = lerp(earDrop, other.earDrop)
        out.headRotation = lerp(headRotation, other.headRotation)
        out.headDrop = lerp(headDrop, other.headDrop)
        out.eyes = a < 0.5 ? eyes : other.eyes
        // Squeeze the eyes shut across the swap so it reads as one blink.
        out.eyeScaleY = lerp(eyeScaleY, other.eyeScaleY) * (1 - 0.8 * sin(.pi * a))
        out.bodyScaleY = lerp(bodyScaleY, other.bodyScaleY)
        out.bodyOffsetY = lerp(bodyOffsetY, other.bodyOffsetY)
        return out
    }

    private static func keyframes(_ x: Double, _ points: [(Double, Double)]) -> Double {
        for i in 1..<points.count where x <= points[i].0 {
            let (x0, y0) = points[i - 1], (x1, y1) = points[i]
            let p = (x - x0) / (x1 - x0)
            return y0 + (y1 - y0) * p * p * (3 - 2 * p)
        }
        return points.last!.1
    }
}

struct VectorFoxView: View {
    @ObservedObject var animator: VectorFoxAnimator
    var size: CGFloat

    var body: some View {
        TimelineView(.animation(paused: animator.isPaused)) { context in
            FoxCanvas(pose: animator.pose(at: context.date), size: size)
        }
        .frame(width: size, height: size)
    }
}

/// Static drawing of one pose, on a 100×100 design grid.
struct FoxCanvas: View {
    var pose: FoxPose
    var size: CGFloat

    static let fur = Color(red: 1, green: 1, blue: 1)
    static let furShadow = Color(red: 0xE3 / 255, green: 0xEB / 255, blue: 0xF7 / 255)
    static let ruff = Color(red: 0xCB / 255, green: 0xD7 / 255, blue: 0xE9 / 255)
    static let innerEar = Color(red: 0xF8 / 255, green: 0xC8 / 255, blue: 0xD2 / 255)
    static let ink = Color(red: 0x23 / 255, green: 0x26 / 255, blue: 0x2E / 255)
    static let mouthGray = Color(red: 0xA9 / 255, green: 0xB3 / 255, blue: 0xC2 / 255)

    // Pivots from the mascot spec, in grid units.
    static let headPivot = CGPoint(x: 50, y: 86.2)       // 50% x, 94% y of head bbox (y 26...90)
    static let earLeftPivot = CGPoint(x: 35.5, y: 45.4)  // 76% x, 96% y of ear bbox
    static let earRightPivot = CGPoint(x: 64.5, y: 45.4) // 24% x, 96% y of ear bbox

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 100
            ctx.scaleBy(x: s, y: s)

            // Whole character: breathing / hop around the chin.
            ctx.translateBy(x: 0, y: pose.bodyOffsetY + pose.headDrop)
            ctx.translateBy(x: 50, y: 92)
            ctx.scaleBy(x: 1 / sqrt(pose.bodyScaleY), y: pose.bodyScaleY)
            ctx.translateBy(x: -50, y: -92)

            // Head rotation carries ears, ruffs and face.
            ctx.translateBy(x: Self.headPivot.x, y: Self.headPivot.y)
            ctx.rotate(by: .degrees(pose.headRotation))
            ctx.translateBy(x: -Self.headPivot.x, y: -Self.headPivot.y)

            drawEar(ctx, left: true)
            drawEar(ctx, left: false)

            ctx.fill(Self.ruffPath(left: true), with: .color(Self.ruff))
            ctx.fill(Self.ruffPath(left: false), with: .color(Self.ruff))

            ctx.fill(Self.headPath, with: .linearGradient(
                Gradient(colors: [Self.fur, Self.furShadow]),
                startPoint: CGPoint(x: 50, y: 26), endPoint: CGPoint(x: 50, y: 90)))

            ctx.fill(Self.muzzlePath, with: .color(Self.fur))
            ctx.fill(Self.nosePath, with: .color(Self.ink))
            if size >= 28 {
                ctx.stroke(Self.mouthPath, with: .color(Self.mouthGray),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            drawEyes(ctx)
        }
        .frame(width: size, height: size)
    }

    private func drawEar(_ ctx: GraphicsContext, left: Bool) {
        var ear = ctx
        let pivot = left ? Self.earLeftPivot : Self.earRightPivot
        ear.translateBy(x: pivot.x, y: pivot.y + pose.earDrop)
        ear.rotate(by: .degrees(left ? -pose.earOut : pose.earOut))
        ear.translateBy(x: -pivot.x, y: -pivot.y)
        ear.fill(Self.earPath(left: left), with: .color(Self.fur))
        ear.fill(Self.innerEarPath(left: left), with: .color(Self.innerEar))
    }

    private func drawEyes(_ ctx: GraphicsContext) {
        for left in [true, false] {
            let cx: CGFloat = left ? 37 : 63
            var eye = ctx
            eye.translateBy(x: cx, y: 55)
            eye.scaleBy(x: 1, y: max(0.1, pose.eyeScaleY))
            eye.translateBy(x: -cx, y: -55)

            let line = StrokeStyle(lineWidth: 2.6, lineCap: .round)
            switch pose.eyes {
            case .open:
                eye.fill(Path(ellipseIn: CGRect(x: cx - 3.6, y: 50, width: 7.2, height: 10)), with: .color(Self.ink))
                let hx = left ? cx + 0.9 : cx - 3.1
                eye.fill(Path(ellipseIn: CGRect(x: hx, y: 51.2, width: 2.2, height: 2.2)), with: .color(.white))
            case .happy:
                var arc = Path()
                arc.move(to: CGPoint(x: cx - 4, y: 57))
                arc.addQuadCurve(to: CGPoint(x: cx + 4, y: 57), control: CGPoint(x: cx, y: 49))
                eye.stroke(arc, with: .color(Self.ink), style: line)
            case .closed:
                var flat = Path()
                flat.move(to: CGPoint(x: cx - 4, y: 55.5))
                flat.addLine(to: CGPoint(x: cx + 4, y: 55.5))
                eye.stroke(flat, with: .color(Self.ink), style: line)
            case .droopy:
                eye.fill(Path(ellipseIn: CGRect(x: cx - 3.8, y: 53, width: 7.6, height: 6.4)), with: .color(Self.ink))
            }
        }
    }

    // MARK: Shapes (100×100 grid)

    static let headPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 50, y: 27))
        p.addCurve(to: CGPoint(x: 87, y: 58), control1: CGPoint(x: 69, y: 27), control2: CGPoint(x: 85, y: 40))
        p.addCurve(to: CGPoint(x: 50, y: 90), control1: CGPoint(x: 88, y: 68), control2: CGPoint(x: 58, y: 86))
        p.addCurve(to: CGPoint(x: 13, y: 58), control1: CGPoint(x: 42, y: 86), control2: CGPoint(x: 12, y: 68))
        p.addCurve(to: CGPoint(x: 50, y: 27), control1: CGPoint(x: 15, y: 40), control2: CGPoint(x: 31, y: 27))
        p.closeSubpath()
        return p
    }()

    /// White lower-face patch, wider than tall, tapering with the head.
    static let muzzlePath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 32, y: 70))
        p.addCurve(to: CGPoint(x: 68, y: 70), control1: CGPoint(x: 38, y: 60), control2: CGPoint(x: 62, y: 60))
        p.addCurve(to: CGPoint(x: 50, y: 91), control1: CGPoint(x: 68, y: 80), control2: CGPoint(x: 57, y: 89))
        p.addCurve(to: CGPoint(x: 32, y: 70), control1: CGPoint(x: 43, y: 89), control2: CGPoint(x: 32, y: 80))
        p.closeSubpath()
        return p
    }()

    static func earPath(left: Bool) -> Path {
        mirrored(left) { p in
            p.move(to: CGPoint(x: 17, y: 47))
            p.addQuadCurve(to: CGPoint(x: 14, y: 9), control: CGPoint(x: 11, y: 26))
            p.addQuadCurve(to: CGPoint(x: 17, y: 7), control: CGPoint(x: 14.5, y: 6))
            p.addQuadCurve(to: CGPoint(x: 42, y: 31), control: CGPoint(x: 31, y: 16))
            p.closeSubpath()
        }
    }

    static func innerEarPath(left: Bool) -> Path {
        mirrored(left) { p in
            p.move(to: CGPoint(x: 22, y: 41))
            p.addQuadCurve(to: CGPoint(x: 19.5, y: 15), control: CGPoint(x: 17.5, y: 27))
            p.addQuadCurve(to: CGPoint(x: 36, y: 32), control: CGPoint(x: 29, y: 21))
            p.closeSubpath()
        }
    }

    static func ruffPath(left: Bool) -> Path {
        mirrored(left) { p in
            p.move(to: CGPoint(x: 15, y: 60))
            p.addQuadCurve(to: CGPoint(x: 6, y: 75), control: CGPoint(x: 8, y: 66))
            p.addQuadCurve(to: CGPoint(x: 26, y: 76), control: CGPoint(x: 16, y: 74))
            p.closeSubpath()
        }
    }

    static let nosePath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 45, y: 65.5))
        p.addQuadCurve(to: CGPoint(x: 55, y: 65.5), control: CGPoint(x: 50, y: 63.5))
        p.addQuadCurve(to: CGPoint(x: 50, y: 71.5), control: CGPoint(x: 55.5, y: 68.5))
        p.addQuadCurve(to: CGPoint(x: 45, y: 65.5), control: CGPoint(x: 44.5, y: 68.5))
        p.closeSubpath()
        return p
    }()

    static let mouthPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 45, y: 74.5))
        p.addQuadCurve(to: CGPoint(x: 50, y: 74), control: CGPoint(x: 47.2, y: 77.5))
        p.addQuadCurve(to: CGPoint(x: 55, y: 74.5), control: CGPoint(x: 52.8, y: 77.5))
        return p
    }()

    private static func mirrored(_ left: Bool, _ build: (inout Path) -> Void) -> Path {
        var p = Path()
        build(&p)
        if left { return p }
        return p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100, ty: 0))
    }
}
