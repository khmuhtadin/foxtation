import SwiftUI

struct HomePage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let now = model.now()
        let entries = model.history.entries
        let today = Stats.today(entries, now: now)

        VStack(alignment: .leading, spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(now: now)
                        .padding(.bottom, 26)
                    tiles(entries: entries, today: today, now: now)
                        .padding(.bottom, 28)
                    todayList(today, hasHistory: !entries.isEmpty)
                }
                .padding(.top, 30)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: - Top bar

    /// "● Cloud cleanup on · MacBook Pro Microphone" and the avatar, across the card's top edge.
    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(model.cloudOn ? Color.fxGood : Color.fxSecondary).frame(width: 6, height: 6)
                Text(model.cloudOn ? "Cloud cleanup on" : "Cloud cleanup off")
                    .foregroundStyle(Color.fxInk)
                Text("·").foregroundStyle(Color.fxSecondary)
                Text(model.microphoneName).foregroundStyle(Color.fxSecondary)
                Spacer()
                Button { model.page = .history } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.fxSecondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Search history")
                .accessibilityLabel("Search history")
                Avatar(name: model.userName)
            }
            .font(FXFont.detail)
            .padding(.horizontal, 20)
            .frame(height: 50)
            RowDivider()
        }
        // The window's content padding is 36 / 30; the bar spans the whole card.
        .padding(.horizontal, -36)
        .padding(.top, -30)
    }

    // MARK: - Greeting

    private func header(now: Date) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(greeting(now)), \(firstName)")
                    .font(FXFont.pageTitle)
                    .foregroundStyle(Color.fxInk)
                hint
            }
            Spacer()
            Button(action: model.startDictation) {
                HStack(spacing: 7) {
                    Image(systemName: "mic.fill").font(.system(size: 11))
                    Text("Start dictation")
                }
            }
            .fxButton(.primary)
        }
    }

    /// "Hold [fn] anywhere to dictate. Release to paste." or the toggle wording.
    private var hint: some View {
        let toggles = !model.settings.holdRightOption && model.settings.triggerMode == .toggle
        return HStack(spacing: 6) {
            Text(toggles ? "Press" : "Hold")
            KeyCap(text: model.triggerKey)
            Text(toggles ? "to start, again to stop." : "anywhere to dictate. Release to paste.")
        }
        .font(FXFont.body)
        .foregroundStyle(Color.fxSecondary)
    }

    private func greeting(_ now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var firstName: String {
        model.userName.split(separator: " ").first.map(String.init) ?? model.userName
    }

    // MARK: - Stat tiles

    private func tiles(entries: [Dictation], today: [Dictation], now: Date) -> some View {
        let wpm = Stats.wpm(Stats.lastDays(7, of: entries, now: now))
        let saved = Stats.minutesSaved(today)
        let streak = Stats.currentStreak(entries, now: now)
        let savedRounded = Int(saved.rounded())

        return HStack(spacing: 12) {
            StatTile(title: "Words today", value: Format.number(Stats.words(today)))
            StatTile(title: "Avg. speed", value: wpm > 0 ? "\(wpm)" : "—", unit: wpm > 0 ? "wpm" : nil)
            if savedRounded < 60 {
                StatTile(title: "Time saved", value: "\(savedRounded)", unit: "min")
            } else {
                StatTile(title: "Time saved", value: Format.duration(minutes: saved))
            }
            StatTile(title: "Streak", value: "\(streak)", unit: streak == 1 ? "day" : "days")
        }
    }

    // MARK: - Today

    private func todayList(_ today: [Dictation], hasHistory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Today")
                Spacer()
                if hasHistory {
                    Button("View all") { model.page = .history }
                        .buttonStyle(.plain)
                        .font(FXFont.detail.weight(.medium))
                        .foregroundStyle(Color.fxAccent)
                }
            }
            if today.isEmpty {
                HistoryEmptyCard(symbol: "waveform",
                                 title: "Nothing dictated today yet",
                                 detail: "Your dictations show up here, newest first.")
            } else {
                HistoryRowsCard(model: model, dictations: today)
            }
        }
    }
}
