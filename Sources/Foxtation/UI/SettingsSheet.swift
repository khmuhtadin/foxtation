import AppKit
import ServiceManagement
import SwiftUI

/// Settings as a sheet over the main window: sections on the left, the
/// selected one on the right.
struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    @ObservedObject var library: Library
    var section: SettingsSection

    var body: some View {
        HStack(spacing: 0) {
            nav
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(section.title).font(.system(size: 22, weight: .semibold)).tracking(-0.4)
                    page
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .topTrailing) {
                IconButton(symbol: "xmark", label: "Close settings") { model.settingsSection = nil }
                    .padding(16)
            }
        }
        .frame(width: 960, height: 640)
        .background(Fx.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.24), radius: 32, y: 24)
    }

    private var nav: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(text: "Settings").padding(.horizontal, 10).padding(.bottom, 8)
            ForEach([SettingsSection.general, .cloud, .shortcuts, .sounds, .engine, .advanced], id: \.self, content: navItem)
            Hairline().padding(.horizontal, 10).padding(.vertical, 12)
            Eyebrow(text: "Account").padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 8)
            ForEach([SettingsSection.license, .privacy], id: \.self, content: navItem)
            Spacer()
            HStack {
                Text("Foxtation v\(model.version)")
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(settings.cloudReady ? Fx.good : Fx.track).frame(width: 7, height: 7)
                    Text("Cloud")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Fx.secondary)
            .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        .frame(width: 232)
        .frame(maxHeight: .infinity)
        .background(Fx.background.opacity(0.45))
        .overlay(alignment: .trailing) { Rectangle().fill(Fx.separator).frame(width: 1) }
    }

    private func navItem(_ item: SettingsSection) -> some View {
        NavItem(title: item.title, symbol: item.symbol, selected: item == section) { model.openSettings(item) }
    }

    @ViewBuilder private var page: some View {
        switch section {
        case .general: GeneralSettings(model: model, settings: settings)
        case .cloud: CloudSettings(model: model, settings: settings)
        case .shortcuts: ShortcutSettings(model: model, settings: settings)
        case .sounds: SoundSettings(model: model, settings: settings)
        case .engine: EngineSettings(model: model, settings: settings)
        case .advanced: AdvancedSettings(model: model, settings: settings)
        case .license: LicenseSettings(model: model, settings: settings)
        case .privacy: PrivacySettings(model: model, settings: settings, library: library)
        }
    }
}

/// A native pop-up menu sized like the design's selects.
struct Popup<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T
    var width: CGFloat = 160
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.0) { value, title in Text(title).tag(value) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: width)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        RowGroup {
            SettingRow(title: "Push-to-talk", detailView: AnyView(
                HStack(spacing: 6) {
                    Text(model.triggerVerb)
                    Kbd(text: model.triggerKey, size: 11.5)
                    Text(model.triggerVerb == "Hold" ? "and speak. Release to paste." : "to start, again to paste.")
                }
                .font(.system(size: 13))
                .foregroundStyle(Fx.secondary))) {
                Button("Change") { model.openSettings(.shortcuts) }.buttonStyle(FxButtonStyle())
            }
            Hairline()
            SettingRow(title: "Hands-free mode",
                       detail: settings.holdRightOption ? "Double-tap right ⌥ to keep recording until you tap again."
                                                        : "Needs “Hold right ⌥ to talk” in Shortcuts.") {
                FxToggle(isOn: model.binding(\.handsFree)).opacity(settings.holdRightOption ? 1 : 0.4)
            }
            Hairline()
            SettingRow(title: "Microphone", detail: model.microphoneName + " (system default)") {
                Button("Change") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.sound?input")!)
                }
                .buttonStyle(FxButtonStyle())
            }
            Hairline()
            SettingRow(title: "Dictation language",
                       detail: settings.language == "auto" ? "Auto detect — mixed Indonesian and English stays mixed" : "Speech is transcribed in this language") {
                Popup(options: Settings.languages.map { ($0.code, $0.label) }, selection: model.binding(\.language))
            }
            Hairline()
            SettingRow(title: "Translate to English", detail: "Paste an English translation of what you said") {
                FxToggle(isOn: model.binding(\.translate))
            }
            Hairline()
            SettingRow(title: "Launch at login", detail: "Keep Foxtation ready in the menu bar.") {
                FxToggle(isOn: model.binding(\.launchAtLogin))
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Permissions")
            RowGroup {
                PermissionLine(title: "Microphone", detail: "Records your voice", granted: Permissions.microphoneGranted) {
                    Permissions.requestMicrophone { granted in if !granted { Permissions.openMicrophoneSettings() } }
                }
                Hairline()
                PermissionLine(title: "Accessibility", detail: "Pastes text into other apps", granted: Permissions.accessibilityGranted) {
                    _ = Permissions.requestAccessibility(prompt: true)
                    Permissions.openAccessibilitySettings()
                }
            }
        }
    }
}

struct PermissionLine: View {
    var title: String
    var detail: String
    var granted: Bool
    var grant: () -> Void

    var body: some View {
        SettingRow(title: title, detail: detail, verticalPadding: 14) {
            HStack(spacing: 10) {
                Text(granted ? "● Granted" : "● Not granted")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(granted ? Fx.good : Fx.bad)
                if !granted { Button("Grant…", action: grant).buttonStyle(FxButtonStyle(kind: .primary, height: 28)) }
            }
        }
    }
}

// MARK: - Cloud cleanup

struct CloudSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        RowGroup {
            SettingRow(title: "Cloud cleanup", detail: "Removes filler words, applies self-corrections and fixes punctuation. Off: paste the raw on-device transcript.") {
                FxToggle(isOn: model.binding(\.cloudCleanup))
            }
            Hairline()
            SettingRow(title: "License",
                       detail: settings.activationID.isEmpty ? "Not activated on this Mac" : "Active on this Mac") {
                Button(settings.activationID.isEmpty ? "Add license" : "Manage") { model.openSettings(.license) }
                    .buttonStyle(FxButtonStyle(kind: settings.activationID.isEmpty ? .primary : .plain))
            }
            Hairline()
            SettingRow(title: "Style per app", detail: "Casual in chat, polished in email, literal in code.") {
                Button("Edit styles") { model.settingsSection = nil; model.section = .style }.buttonStyle(FxButtonStyle())
            }
        }
        InfoNote(symbol: "lock", text: "Only text is sent: the transcript, its language, your dictionary words, snippet cues and the style for the app in front. Never audio. If cleanup fails or the daily limit is reached, the raw transcript is pasted instead.")
    }
}

struct InfoNote: View {
    var symbol: String
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Fx.good).padding(.top, 1)
            Text(text).font(.system(size: 13)).lineSpacing(3).foregroundStyle(Fx.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Fx.good.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Fx.good.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Shortcuts

struct ShortcutSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        RowGroup {
            SettingRow(title: "Hold right ⌥ to talk", detail: "Release to paste. Double-tap for hands-free.") {
                FxToggle(isOn: model.binding(\.holdRightOption))
            }
            Hairline()
            SettingRow(title: "Shortcut", detail: "Must include ⌘, ⌥ or ⌃. Click, then press the keys. Esc cancels.") {
                ShortcutRecorder(settings: settings, onChange: model.onSettingsChanged)
                    .frame(width: 130, height: 28)
            }
            Hairline()
            SettingRow(title: "Shortcut mode", detail: nil) {
                Popup(options: [(TriggerMode.toggle, "Press to start, again to stop"), (.hold, "Hold while speaking")],
                      selection: model.binding(\.triggerMode), width: 230)
            }
        }
        RowGroup {
            SettingRow(title: "Insert by", detail: "Typing is slower but leaves the clipboard alone.") {
                Popup(options: [(InsertMethod.paste, "Paste (⌘V)"), (.type, "Type characters")],
                      selection: model.binding(\.insertMethod))
            }
            Hairline()
            SettingRow(title: "Restore clipboard afterwards", detail: "Puts back what you had copied before the paste.") {
                FxToggle(isOn: model.binding(\.restoreClipboard))
            }
        }
    }
}

/// The AppKit shortcut recorder inside SwiftUI.
struct ShortcutRecorder: NSViewRepresentable {
    var settings: Settings
    var onChange: () -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(frame: .zero)
        button.onCapture = { code, modifiers in
            settings.hotKeyCode = code
            settings.hotKeyModifiers = modifiers
            onChange()
        }
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.update(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
    }
}

// MARK: - Sounds

struct SoundSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        RowGroup {
            SettingRow(title: "Start and stop sounds", detail: "A short tick when recording starts and stops.") {
                FxToggle(isOn: model.binding(\.playSounds))
            }
            Hairline()
            SettingRow(title: "Recording pill", detail: "Shows the timer, level meter and what happened to the text.") {
                FxToggle(isOn: model.binding(\.showHUD))
            }
            Hairline()
            SettingRow(title: "Pill position", detail: nil) {
                Popup(options: HUDPlacement.allCases.map { ($0, $0.label) }, selection: model.binding(\.hudPlacement))
            }
        }
    }
}

// MARK: - Engine

struct EngineSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        let runtime = MLXRuntime.shared
        let store = ModelStore.shared
        let _ = model.engineTick  // redraw when downloads or setup progress

        RowGroup {
            SettingRow(title: "Engine", detail: "Speech is transcribed on this Mac. MLX is fastest on Apple silicon.") {
                Picker("", selection: Binding(get: { settings.engine }, set: { engine in
                    settings.engine = engine
                    if engine == .mlx, settings.keepModelLoaded, runtime.readyPython() != nil {
                        MLXEngine.shared.preload(repo: settings.mlxModel)
                    }
                    model.onSettingsChanged()
                })) {
                    Text("MLX · Apple GPU").tag(TranscriptionEngine.mlx)
                    Text("whisper.cpp").tag(TranscriptionEngine.whisperCpp)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }

        if settings.engine == .mlx {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "MLX models")
                RowGroup {
                    SettingRow(title: "Python runtime", detail: runtime.isBusy ? runtime.busyLabel : nil, verticalPadding: 12) {
                        HStack(spacing: 10) {
                            if !runtime.isBusy {
                                let ready = runtime.readyPython() != nil
                                Text(ready ? "● Installed" : "● Not installed")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ready ? Fx.good : Fx.bad)
                            }
                            Button(runtime.isBusy ? "Working…" : runtime.readyPython() != nil ? "Reinstall" : "Set Up") {
                                runtime.provision()
                                model.engineTick += 1
                            }
                            .buttonStyle(FxButtonStyle(kind: runtime.readyPython() == nil ? .primary : .plain, height: 28))
                            .disabled(runtime.isBusy)
                        }
                    }
                    ForEach(MLXRuntime.catalog, id: \.repo) { item in
                        Hairline()
                        ModelLine(name: item.name, recommended: item.recommended, detail: "\(item.size) · \(item.note)",
                                  installed: runtime.isModelDownloaded(item),
                                  selected: settings.mlxModel == item.repo,
                                  downloading: false, progress: 0, enabled: !runtime.isBusy,
                                  use: {
                                      settings.mlxModel = item.repo
                                      if settings.keepModelLoaded, runtime.readyPython() != nil { MLXEngine.shared.preload(repo: item.repo) }
                                      model.onSettingsChanged()
                                  },
                                  action: {
                                      if runtime.isModelDownloaded(item) {
                                          runtime.deleteModel(item)
                                          if settings.mlxModel == item.repo { settings.mlxModel = "" }
                                      } else {
                                          runtime.downloadModel(item)
                                      }
                                      model.engineTick += 1
                                  })
                    }
                    Hairline()
                    SettingRow(title: "Keep model in memory", detail: "Instant start, uses about 1.6 GB", verticalPadding: 12) {
                        FxToggle(isOn: Binding(get: { settings.keepModelLoaded }, set: { on in
                            settings.keepModelLoaded = on
                            if on { MLXEngine.shared.preload(repo: settings.mlxModel) } else { MLXEngine.shared.unload() }
                            model.onSettingsChanged()
                        }))
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "whisper.cpp models")
                RowGroup {
                    ForEach(ModelStore.catalog, id: \.file) { item in
                        if item.file != ModelStore.catalog.first?.file { Hairline() }
                        let path = store.path(for: item.file).path
                        let downloading = store.isDownloading(item.file)
                        ModelLine(name: item.name, recommended: item.recommended,
                                  detail: (!downloading ? store.errors[item.file] : nil) ?? "\(item.size) · \(item.note)",
                                  installed: store.installed.contains(item.file),
                                  selected: settings.modelPath == path,
                                  downloading: downloading, progress: store.progress[item.file] ?? 0, enabled: true,
                                  use: { settings.modelPath = path; model.onSettingsChanged() },
                                  action: {
                                      if downloading {
                                          store.cancel(item.file)
                                      } else if store.installed.contains(item.file) {
                                          if settings.modelPath == path { settings.modelPath = "" }
                                          store.delete(item)
                                      } else {
                                          store.download(item)
                                      }
                                      model.engineTick += 1
                                  })
                    }
                    Hairline()
                    SettingRow(title: "Needs whisper-cli", detail: "brew install whisper-cpp", verticalPadding: 12) {
                        let found = Transcriber.resolveBinary(configured: settings.whisperBinary) != nil
                        Text(found ? "● Found" : "● Not found").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(found ? Fx.good : Fx.bad)
                    }
                }
            }
        }
    }
}

struct ModelLine: View {
    var name: String
    var recommended: Bool
    var detail: String
    var installed: Bool
    var selected: Bool
    var downloading: Bool
    var progress: Double
    var enabled: Bool
    var use: () -> Void
    var action: () -> Void

    var body: some View {
        SettingRow(title: recommended ? "\(name)  ★" : name, detail: detail, verticalPadding: 12) {
            HStack(spacing: 8) {
                if downloading { Meter(fraction: progress).frame(width: 90) }
                if installed && selected {
                    Text("✓ In use").font(.system(size: 12, weight: .semibold)).foregroundStyle(Fx.accent)
                } else if installed && !downloading {
                    Button("Use", action: use).buttonStyle(FxButtonStyle(height: 28))
                }
                Button(downloading ? "Cancel" : installed ? "Delete" : "Download", action: action)
                    .buttonStyle(FxButtonStyle(kind: installed || downloading ? .plain : .primary, height: 28))
                    .disabled(!enabled)
            }
        }
    }
}

// MARK: - Advanced

struct AdvancedSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        RowGroup {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vocabulary prompt").font(.system(size: 14, weight: .medium))
                Text("Names, jargon or acronyms to bias the on-device recognizer. Leave empty to disable.")
                    .font(.system(size: 13)).foregroundStyle(Fx.secondary)
                TextEditor(text: model.binding(\.initialPrompt))
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Fx.wash))
                    .padding(.top, 6)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            Hairline()
            SettingRow(title: "Max recording length", detail: "Recording stops automatically") {
                HStack(spacing: 10) {
                    Text("\(Int(settings.maxSeconds)) s").font(Fx.mono(12)).foregroundStyle(Fx.secondary)
                    Slider(value: Binding(get: { settings.maxSeconds }, set: { settings.maxSeconds = $0.rounded() }),
                           in: 10...600, onEditingChanged: { editing in if !editing { model.onSettingsChanged() } })
                        .frame(width: 160)
                }
            }
            Hairline()
            SettingRow(title: "CPU threads", detail: "whisper.cpp only") {
                Stepper("\(settings.threads)", value: model.binding(\.threads), in: 1...16)
                    .font(Fx.mono(12))
            }
            Hairline()
            SettingRow(title: "whisper-cli binary", detail: "brew install whisper-cpp") {
                HStack(spacing: 10) {
                    let resolved = Transcriber.resolveBinary(configured: settings.whisperBinary)
                    Text(resolved.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "not found")
                        .font(.system(size: 12)).foregroundStyle(resolved == nil ? Fx.bad : Fx.secondary)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = false
                        panel.showsHiddenFiles = true
                        panel.message = "Select the whisper-cli executable"
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.whisperBinary = url.path
                            model.onSettingsChanged()
                        }
                    }
                    .buttonStyle(FxButtonStyle(height: 28))
                }
            }
        }
        RowGroup {
            SettingRow(title: "Reset all settings", detail: "History, dictionary, models and the MLX runtime are kept. Foxtation quits.") {
                Button("Reset…", action: resetAll).buttonStyle(FxButtonStyle(kind: .danger))
            }
        }
    }

    private func resetAll() {
        let alert = NSAlert()
        alert.messageText = "Reset all Foxtation settings?"
        alert.informativeText = "History, dictionary, snippets, downloaded models and the MLX runtime are kept."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? SMAppService.mainApp.unregister()  // the reset default is "off"
        let domain = Bundle.main.bundleIdentifier ?? "com.khmuhtadin.foxtation"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        NSApp.terminate(nil)
    }
}

// MARK: - License

struct LicenseSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        let active = !settings.activationID.isEmpty
        let license = model.license

        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("Foxtation Cloud").font(.system(size: 17, weight: .semibold))
                    Text(active ? (license?.status?.capitalized ?? "Active") : "Not active")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(active ? Fx.ink : Fx.card)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(active ? Fx.good.opacity(0.9) : Fx.card.opacity(0.2)))
                }
                Text(active ? subscriptionLine(license) : "Cleans up every dictation: fewer fillers, real punctuation, your style per app.")
                    .font(.system(size: 13)).foregroundStyle(Fx.card.opacity(0.75))
            }
            Spacer()
            if active, let portal = license?.portal_url, let url = URL(string: portal) {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label("Manage subscription", systemImage: "arrow.up.right").labelStyle(TrailingIcon())
                }
                .buttonStyle(InvertedButtonStyle())
            } else if !active {
                Button("Get a license") { NSWorkspace.shared.open(CloudCleanup.buyURL) }
                    .buttonStyle(InvertedButtonStyle())
            }
        }
        .foregroundStyle(Fx.card)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 12).fill(Fx.ink))

        RowGroup {
            if active && !model.enteringKey {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("License key").font(.system(size: 14, weight: .medium))
                        Text(model.showLicenseKey ? settings.licenseKey : Self.mask(settings.licenseKey))
                            .font(Fx.mono(13))
                            .lineLimit(1)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: 360, minHeight: 34, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Fx.wash))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Fx.track, lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Button(model.showLicenseKey ? "Hide" : "Show") { model.showLicenseKey.toggle() }
                        Button("Copy") { model.copy(settings.licenseKey) }
                        Button("Use another key") { model.enteringKey = true; model.keyDraft = "" }
                    }
                    .buttonStyle(FxButtonStyle())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            } else {
                keyEntry(active: active)
            }
            if active {
                Hairline()
                thisMac(license)
                Hairline()
                usage
            }
        }

        if let message = model.licenseMessage {
            Text(message).font(.system(size: 12.5)).foregroundStyle(message == "Checking…" ? Fx.secondary : Fx.bad)
        }
    }

    private func subscriptionLine(_ license: LicenseInfo?) -> String {
        var parts = ["Subscription via Polar"]
        if let expires = license?.expires_at, let date = ISO8601DateFormatter.cloud.date(from: expires) ?? ISO8601DateFormatter().date(from: expires) {
            parts.append("ends \(AppModel.dayFormatter.string(from: date))")
        }
        return parts.joined(separator: " · ")
    }

    private func keyEntry(active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(active ? "Use another license key" : "License key").font(.system(size: 14, weight: .medium))
            HStack(spacing: 8) {
                TextField("Paste the key from your Polar receipt", text: $model.keyDraft)
                    .textFieldStyle(.plain)
                    .font(Fx.mono(13))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: 360, minHeight: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Fx.wash))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Fx.track, lineWidth: 1))
                    .onSubmit { model.activate() }
                Button("Activate") { model.activate() }
                    .buttonStyle(FxButtonStyle(kind: .primary))
                    .disabled(model.busy || model.keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                if active {
                    Button("Cancel") { model.enteringKey = false; model.licenseMessage = nil }.buttonStyle(FxButtonStyle())
                }
            }
            Text("Activating uses one of the license’s Mac activations.")
                .font(.system(size: 12.5)).foregroundStyle(Fx.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thisMac(_ license: LicenseInfo?) -> some View {
        let label = license?.this_device?.label ?? Host.current().localizedName ?? "Mac"
        var parts: [String] = []
        let created = license?.this_device?.created_at.flatMap { ISO8601DateFormatter.cloud.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            ?? (settings.activatedAt > 0 ? Date(timeIntervalSince1970: settings.activatedAt) : nil)
        if let created { parts.append("Activated \(AppModel.dayFormatter.string(from: created))") }
        if let used = license?.activations?.used, let limit = license?.activations?.limit {
            parts.append("\(used) of \(limit) activations used")
        } else if let limit = license?.activations?.limit {
            parts.append("Up to \(limit) Macs")
        }
        if model.licenseUnavailable { parts.append("Deactivation isn’t available on the server yet") }

        return HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 15))
                .foregroundStyle(Fx.secondary)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Fx.wash))
            VStack(alignment: .leading, spacing: 3) {
                Text("This Mac · \(label)").font(.system(size: 14, weight: .medium))
                if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.system(size: 13)).foregroundStyle(Fx.secondary) }
            }
            Spacer()
            Button("Deactivate") { model.deactivate() }
                .buttonStyle(FxButtonStyle(kind: .danger))
                .disabled(model.busy || model.licenseUnavailable)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cloud cleanups today").font(.system(size: 14, weight: .medium))
                Spacer()
                HStack(spacing: 0) {
                    Text(model.usage.map { "\($0.used)" } ?? "—").font(Fx.mono(13)).foregroundStyle(Fx.ink)
                    Text(" / " + model.usageDetail.replacingOccurrences(of: "of ", with: ""))
                }
                .font(.system(size: 13)).foregroundStyle(Fx.secondary)
            }
            Meter(fraction: model.usage.map { Double($0.used) / Double(max(1, $0.limit)) } ?? 0, height: 8)
            Text("Past the limit, dictation keeps working and pastes the raw transcript.")
                .font(.system(size: 12.5)).foregroundStyle(Fx.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    /// "FOX-1234-5678-ABCD" → "FOX-••••-••••-ABCD": the first group and last four stay readable.
    static func mask(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        let head = key.firstIndex(of: "-").map { key[..<$0].count } ?? 4
        let keep = min(head, 4)
        let chars = Array(key)
        return String(chars.enumerated().map { index, char in
            index < keep || index >= chars.count - 4 || char == "-" ? char : "•"
        })
    }
}

/// Light button on the dark license banner.
struct InvertedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Fx.ink)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(Fx.card))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .fixedSize()
    }
}

struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.font(.system(size: 10, weight: .semibold))
        }
    }
}

// MARK: - Data & Privacy

struct PrivacySettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    @ObservedObject var library: Library

    var body: some View {
        InfoNote(symbol: "lock", text: "Your voice never leaves this Mac. Only the text transcript is sent to Foxtation Cloud for cleanup, and it isn’t stored after the reply.")

        RowGroup {
            SettingRow(title: "Cloud cleanup", detail: "Off: paste the raw on-device transcript, nothing sent.", verticalPadding: 15) {
                FxToggle(isOn: model.binding(\.cloudCleanup))
            }
            Hairline()
            SettingRow(title: "Share the app name", detail: "Sends “Slack” or “Mail” so cleanup can match the style.", verticalPadding: 15) {
                FxToggle(isOn: model.binding(\.shareAppName))
            }
            Hairline()
            SettingRow(title: "Keep history on this Mac", detail: "Transcripts shown on Home. Stored locally only.", verticalPadding: 15) {
                Popup(options: HistoryRetention.allCases.map { ($0, $0.label) },
                      selection: Binding(get: { settings.historyRetention }, set: { retention in
                          settings.historyRetention = retention
                          library.prune(retention)
                      }), width: 140)
            }
            Hairline()
            SettingRow(title: "Keep audio recordings", detail: "Lets you replay a dictation. Uses disk space.", verticalPadding: 15) {
                FxToggle(isOn: model.binding(\.keepAudio))
            }
        }

        HStack(spacing: 16) {
            Text("\(library.history.count.formatted()) dictations · \(ByteCountFormatter.string(fromByteCount: Int64(library.diskUsage()), countStyle: .file)) on disk")
                .font(.system(size: 13)).foregroundStyle(Fx.secondary)
            Spacer()
            Button("Export history") { model.exportHistory() }.buttonStyle(FxButtonStyle())
                .disabled(library.history.isEmpty)
            Button("Delete all history") { model.deleteAllHistory() }.buttonStyle(FxButtonStyle(kind: .danger))
                .disabled(library.history.isEmpty)
        }
    }
}
