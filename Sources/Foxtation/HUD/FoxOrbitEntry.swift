import SwiftUI

/// DictationHUDView, the old window root, still applies this; HUDStage
/// (FoxFlight.swift) replaced it, so it just hides the old runner.
struct OrbitRunner: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        content.hidden()
    }
}

// MARK: - Entry and exit choreography

extension HUDModel {

    enum ExitKind { case normal, success, cancelled }

    /// Starts the storyboard entry (see FoxFlight). Any entry already running is
    /// cancelled and its remaining steps never run, so a fast double trigger
    /// cannot freeze it.
    func runEntry(flight: FoxFlight) {
        entryTask?.cancel()
        entryTask = nil
        generation += 1

        withTransaction(Transaction(animation: nil)) {
            pillOffset = .zero
            pillScale = 1
            pillOpacity = reduceMotion ? 0 : 1
            contentOpacity = 0
            slotOpacity = 0
            slotScale = 1
        }

        if reduceMotion {
            flight.stop()
            withAnimation(.easeInOut(duration: 0.16)) {
                pillOpacity = 1
                slotOpacity = 1
                contentOpacity = 1
            }
            return
        }

        flight.start(mirrored: placement == .rightEdge)
        entryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(FoxFlight.landingReal))
                guard let self else { return }
                // 7 → 8 · the flying fox hands over to the seated face, then the content appears.
                self.checkHandoff()
                withAnimation(.linear(duration: 0.15)) { self.slotOpacity = 1 }
                try await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 0.22)) { self.contentOpacity = 1 }
                try await Task.sleep(for: .seconds(FoxFlight.endReal - FoxFlight.landingReal))
                flight.stop()
                self.entryTask = nil
            } catch {
                // Cancelled by a newer entry, an exit, or finishEntry.
            }
        }
    }

    /// Skips the rest of the flight and shows the seated pill at once, e.g.
    /// when recording stops before the fox has landed.
    func finishEntry(flight: FoxFlight) {
        guard flight.isFlying else { return }
        entryTask?.cancel()
        entryTask = nil
        flight.stop()
        withAnimation(.easeOut(duration: 0.15)) {
            pillOpacity = 1
            slotOpacity = 1
            contentOpacity = 1
        }
    }

    /// Fades the pill out. `completion` only runs if nothing else started
    /// meanwhile, so a show during the fade-out is never ordered out.
    func runExit(_ kind: ExitKind, flight: FoxFlight, completion: @escaping () -> Void) {
        entryTask?.cancel()
        entryTask = nil
        flight.stop()
        generation += 1
        let token = generation

        let duration: Double
        if reduceMotion {
            duration = 0.16
            withAnimation(.easeInOut(duration: duration)) { pillOpacity = 0 }
        } else {
            switch kind {
            case .normal:
                duration = 0.22
                withAnimation(.easeIn(duration: duration)) {
                    pillScale = 0.96
                    pillOpacity = 0
                }
            case .success:
                duration = 0.22
                withAnimation(.easeIn(duration: duration)) {
                    pillOffset = CGSize(width: 0, height: 6)
                    pillOpacity = 0
                }
            case .cancelled:
                duration = 0.14
                withAnimation(.easeIn(duration: duration)) {
                    pillScale = 0.92
                    pillOpacity = 0
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.generation == token else { return }
            completion()
        }
    }

    /// The flight's last point must sit on the measured face slot, or the
    /// hand-over visibly jumps.
    func checkHandoff() {
        guard let measured = measuredSlotCenter else { return }
        let end = FoxFlight.landingPoint
        let delta = hypot(end.x - measured.x, end.y - measured.y)
        NSLog("Foxtation HUD: fox handoff delta %.3fpt (flight %@, slot %@)",
              delta, NSStringFromPoint(end), NSStringFromPoint(measured))
        if delta > 1 {
            assertionFailure("Fox flight/slot handoff off by \(delta)pt")
        }
    }
}
