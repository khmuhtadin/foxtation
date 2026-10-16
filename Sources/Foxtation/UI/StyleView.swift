import SwiftUI

struct StyleView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: Library

    var body: some View {
        let group = model.styleGroup
        let style = library.styles.style(group)
        let tones: [Tone] = group == .code ? [.literal, .casual, .neutral, .formal] : [.casual, .neutral, .formal]

        PageColumn {
            VStack(alignment: .leading, spacing: 6) {
                Text("Style").font(.system(size: 26, weight: .semibold)).tracking(-0.5)
                Text("Choose how cleanup sounds in each kind of app. Foxtation detects the app you’re typing in.")
                    .font(.system(size: 14)).foregroundStyle(Fx.secondary)
            }

            UnderlineTabs(options: StyleGroup.allCases.map { ($0, $0.label, nil) },
                          selection: $model.styleGroup, spacing: 24) { EmptyView() }

            HStack(alignment: .top, spacing: 14) {
                ForEach(tones, id: \.self) { tone in
                    ToneCard(tone: tone, selected: style.tone == tone) { library.setTone(tone, for: group) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Apps using \(group.label) style")
                FlowLayout(spacing: 8) {
                    ForEach(style.apps, id: \.bundleID) { app in
                        HStack(spacing: 6) {
                            Text(app.name).font(.system(size: 12.5, weight: .medium))
                            Button { library.removeApp(app, from: group) } label: {
                                Text("×").font(.system(size: 13)).foregroundStyle(Fx.secondary).frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(app.name)")
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 6)
                        .frame(height: 30)
                        .background(Capsule().fill(Fx.card))
                        .overlay(Capsule().strokeBorder(Fx.separator, lineWidth: 1))
                        .help(app.bundleID)
                    }
                    Button {
                        if let app = Editors.chooseApp() { library.addApp(app, to: group) }
                    } label: {
                        Text("+ Add app").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Fx.ink.opacity(0.85))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .overlay(Capsule().strokeBorder(Fx.track, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                }
                Text("Apps in no group get a style that fits their name.")
                    .font(.system(size: 12)).foregroundStyle(Fx.secondary)
            }

            RowGroup {
                SettingRow(title: "Keep emoji I say out loud", detail: "“emoji ketawa” becomes 😂 instead of the words.", verticalPadding: 14) {
                    FxToggle(isOn: Binding(get: { library.styles.spokenEmoji },
                                           set: { library.styles.spokenEmoji = $0; library.saveStyles() }))
                }
            }
        }
    }
}

struct ToneCard: View {
    var tone: Tone
    var selected: Bool
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tone.label).font(.system(size: 14, weight: .semibold))
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Fx.accent))
                }
            }
            .frame(height: 18)
            Text(description).font(.system(size: 12.5)).foregroundStyle(Fx.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            Text(example).font(.system(size: 13))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Fx.wash))
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Fx.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Fx.accent : Fx.separator, lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var description: String {
        switch tone {
        case .casual: return "Lowercase is fine, no trailing period, slang stays."
        case .neutral: return "Normal casing and punctuation, words untouched."
        case .formal: return "Full sentences, standard spelling, no slang."
        case .literal: return "Exactly what you said. No added punctuation or capitals."
        }
    }

    private var example: String {
        switch tone {
        case .casual: return "oke gw otw ya, 10 menit lagi sampe"
        case .neutral: return "Oke, gw otw ya. 10 menit lagi sampe."
        case .formal: return "Oke, saya sedang di jalan. Sekitar 10 menit lagi sampai."
        case .literal: return "git commit dash m fix upload retries"
        }
    }
}
