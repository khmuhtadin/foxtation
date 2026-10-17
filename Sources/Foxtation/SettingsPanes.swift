import AppKit

// AppKit panes the Settings panel hosts: engine and model setup, advanced
// options, and the shortcut recorder.
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

private enum Layout {
    static let windowWidth: CGFloat = 560
    static let margin: CGFloat = 20
    static let cardWidth: CGFloat = windowWidth - margin * 2
}

// MARK: - Building blocks

/// A plain view filled with a (dynamic) color, optionally rounded.
class FillView: NSView {

    var color: NSColor { didSet { needsDisplay = true } }
    /// Optional hairline around the view.
    var border: NSColor? { didSet { needsDisplay = true } }

    init(color: NSColor, radius: CGFloat = 0, border: NSColor? = nil) {
        self.color = color
        self.border = border
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = color.cgColor  // re-resolved on every appearance change
        layer?.borderColor = border?.cgColor
        layer?.borderWidth = border == nil ? 0 : 1
    }
}

/// An on/off switch in the icon's accent color (NSSwitch can't be tinted).
final class Toggle: NSView {

    var isOn = false { didSet { needsDisplay = true } }
    var onToggle: ((Bool) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 34, height: 20))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 34).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func draw(_ dirtyRect: NSRect) {
        (isOn ? Palette.accent : Palette.track).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let knob = NSRect(x: isOn ? bounds.maxX - 18 : 2, y: 2, width: 16, height: 16)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()  // same knob shadow as FXSwitch
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) { flip() }

    override func accessibilityValue() -> Any? { isOn }
    override func accessibilityPerformPress() -> Bool { flip(); return true }

    private func flip() {
        isOn.toggle()
        onToggle?(isOn)
    }
}

private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                   color: NSColor = Palette.ink) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    return field
}

private func accentButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    button.bezelColor = Palette.accent
    return button
}

/// One line of a card: title (+ optional detail) on the left, controls on the right.
private final class Row: NSStackView {

    let titleLabel: NSTextField
    let detailLabel: NSTextField

    init(_ title: String, detail: String? = nil, _ controls: [NSView]) {
        titleLabel = label(title, weight: .medium)
        detailLabel = label(detail ?? "", size: 12, color: Palette.secondary)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.toolTip = detail  // the full text when it truncates
        detailLabel.isHidden = detail == nil

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        edgeInsets = NSEdgeInsets(top: 11, left: 14, bottom: 11, right: 14)
        setViews([labels, NSView()] + controls, in: .leading)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
}

/// A titled white card holding rows separated by hairlines.
private func card(_ title: String?, _ rows: [NSView], width: CGFloat = Layout.cardWidth) -> NSStackView {
    let body = NSStackView()
    body.orientation = .vertical
    body.alignment = .leading
    body.spacing = 0
    for (index, row) in rows.enumerated() {
        if index > 0 {
            let line = FillView(color: Palette.separator)
            line.translatesAutoresizingMaskIntoConstraints = false
            line.heightAnchor.constraint(equalToConstant: 1).isActive = true
            body.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -28).isActive = true
            line.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 14).isActive = true
        }
        body.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
    }

    let background = FillView(color: Palette.card, radius: 10, border: Palette.separator)
    body.translatesAutoresizingMaskIntoConstraints = false
    background.addSubview(body)
    NSLayoutConstraint.activate([
        body.leadingAnchor.constraint(equalTo: background.leadingAnchor),
        body.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        body.topAnchor.constraint(equalTo: background.topAnchor, constant: 2),
        body.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -2),
    ])

    let group = NSStackView()
    group.orientation = .vertical
    group.alignment = .leading
    group.spacing = 8
    if let title {
        let heading = label("", size: 11, weight: .semibold, color: Palette.secondary)
        // Same as the SwiftUI SectionLabel: small caps with a little tracking.
        heading.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: Palette.secondary,
            .kern: 0.4,
        ])
        group.addArrangedSubview(heading)
        group.setCustomSpacing(8, after: heading)
    }
    group.addArrangedSubview(background)
    background.widthAnchor.constraint(equalToConstant: width).isActive = true
    return group
}

/// A pane is a column of cards; AppDelegate-facing state lives in the subclasses.
/// The Engine and Advanced panes are also shown in the main window's Settings panel.
class Pane: NSStackView {

    /// Asks the window to re-fit after rows were shown or hidden.
    var onResize: (() -> Void)?

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 20
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func reload() {}
}

// MARK: - Engine

final class EnginePane: Pane {

    private let settings: Settings
    private let onChange: () -> Void
    private let runtime = MLXRuntime.shared
    private let width: CGFloat

    private let engineControl = NSSegmentedControl()
    private var wkCard: NSView!
    private var mlxCard: NSView!
    private var cppCard: NSView!
    private var wkRow: Row!
    private let wkStatus = label("", size: 12, weight: .medium)
    private let wkProgress = NSProgressIndicator()
    private lazy var wkButton = accentButton("Download", target: self, action: #selector(installWhisperKit))
    private var mlxRows: [MLXModelRowView] = []
    private var cppRows: [CppModelRowView] = []
    private let runtimeStatus = label("", size: 12, weight: .medium)
    private lazy var setupButton = accentButton("Set up", target: self, action: #selector(setUpRuntime))
    private let keepLoaded = Toggle()
    private var loading = false

    init(settings: Settings, onChange: @escaping () -> Void, width: CGFloat) {
        self.settings = settings
        self.onChange = onChange
        self.width = width
        super.init()

        engineControl.segmentStyle = .rounded
        engineControl.trackingMode = .selectOne
        engineControl.segmentCount = 3
        engineControl.setLabel("WhisperKit", forSegment: 0)
        engineControl.setLabel("MLX", forSegment: 1)
        engineControl.setLabel("whisper.cpp", forSegment: 2)
        engineControl.selectedSegmentBezelColor = Palette.accent
        engineControl.target = self
        engineControl.action = #selector(engineChanged)
        addArrangedSubview(card(nil, [Row("Engine", detail: "WhisperKit is fastest: it transcribes while you speak.", [engineControl])], width: width))

        wkButton.controlSize = .small
        wkProgress.style = .bar
        wkProgress.minValue = 0
        wkProgress.maxValue = 1
        wkProgress.controlSize = .small
        wkProgress.translatesAutoresizingMaskIntoConstraints = false
        wkProgress.widthAnchor.constraint(equalToConstant: 90).isActive = true
        wkRow = Row("Whisper large-v3 turbo", detail: "", [wkProgress, wkStatus, wkButton])
        wkCard = card("WhisperKit model", [wkRow], width: width)
        addArrangedSubview(wkCard)
        WhisperKitEngine.shared.onStateChange = { [weak self] in self?.reload() }

        setupButton.controlSize = .small
        let update: () -> Void = { [weak self] in
            self?.reload()
            self?.onChange()
        }
        mlxRows = MLXRuntime.catalog.map { MLXModelRowView(model: $0, settings: settings, runtime: runtime, onUpdate: update) }
        keepLoaded.onToggle = { [weak self] on in
            guard let self else { return }
            self.settings.keepModelLoaded = on
            if on { MLXEngine.shared.preload(repo: self.settings.mlxModel) } else { MLXEngine.shared.unload() }
            self.onChange()
        }
        mlxCard = card("MLX models", [Row("Python runtime", detail: "About 200 MB · needs uv: brew install uv", [runtimeStatus, setupButton])] + mlxRows
            + [Row("Keep model in memory", detail: "Starts instantly, uses about 1.6 GB of memory.", [keepLoaded])], width: width)
        addArrangedSubview(mlxCard)

        cppRows = ModelStore.catalog.map { CppModelRowView(descriptor: $0, settings: settings, store: ModelStore.shared, onUpdate: update) }
        cppCard = card("whisper.cpp models", cppRows
            + [Row("Needs whisper-cli", detail: "brew install whisper-cpp", [])], width: width)
        addArrangedSubview(cppCard)

        runtime.onChange = { [weak self] in self?.reload() }
        ModelStore.shared.onChange = { [weak self] in self?.reload() }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func reload() {
        loading = true
        engineControl.selectedSegment = TranscriptionEngine.allCases.firstIndex(of: settings.engine) ?? 0

        switch WhisperKitEngine.shared.state {
        case .notInstalled:
            showWhisperKit("● Not installed", Palette.bad, button: "Download",
                           detail: "1.6 GB download, then about a minute of setup.")
        case .downloading(let progress):
            showWhisperKit("\(Int(progress * 100))%", Palette.secondary, button: nil, progress: progress,
                           detail: String(format: "Downloading %.1f of 1.6 GB", progress * 1.6))
        case .loading:
            showWhisperKit("Preparing…", Palette.secondary, button: nil, progress: -1,
                           detail: "Setting up for the Neural Engine, about a minute.")
        case .ready:
            showWhisperKit("● Ready", Palette.good, button: nil,
                           detail: "On this Mac and ready to dictate.")
        case .failed(let message):
            showWhisperKit("● Failed", Palette.bad, button: "Retry", detail: message)
        }

        if runtime.isBusy {
            runtimeStatus.stringValue = runtime.busyLabel
            runtimeStatus.textColor = Palette.secondary
            setupButton.title = "Working…"
            setupButton.isEnabled = false
        } else if runtime.readyPython() != nil {
            runtimeStatus.stringValue = "● Installed"
            runtimeStatus.textColor = Palette.good
            setupButton.title = "Reinstall"
            setupButton.isEnabled = true
        } else {
            runtimeStatus.stringValue = "● Not installed"
            runtimeStatus.textColor = Palette.bad
            setupButton.title = "Set up"
            setupButton.isEnabled = true
        }

        mlxRows.forEach { $0.refresh() }
        cppRows.forEach { $0.refresh() }
        keepLoaded.isOn = settings.keepModelLoaded

        let before = [wkCard.isHidden, mlxCard.isHidden, cppCard.isHidden]
        wkCard.isHidden = settings.engine != .whisperKit
        mlxCard.isHidden = settings.engine != .mlx
        cppCard.isHidden = settings.engine != .whisperCpp
        if before != [wkCard.isHidden, mlxCard.isHidden, cppCard.isHidden] { onResize?() }
        loading = false
    }

    @objc private func engineChanged() {
        guard !loading else { return }
        settings.engine = TranscriptionEngine.allCases[engineControl.selectedSegment]
        if settings.engine == .whisperKit { WhisperKitEngine.shared.prewarm() }
        if settings.engine == .mlx, settings.keepModelLoaded, runtime.readyPython() != nil {
            MLXEngine.shared.preload(repo: settings.mlxModel)
        }
        reload()
        onChange()
    }

    @objc private func setUpRuntime() {
        runtime.provision()
        reload()
    }

    /// `progress` 0...1 fills the bar, -1 animates it, nil hides it.
    private func showWhisperKit(_ status: String, _ color: NSColor, button: String?,
                                progress: Double? = nil, detail: String) {
        wkStatus.stringValue = status
        wkStatus.textColor = color
        wkButton.isHidden = button == nil
        if let button { wkButton.title = button }
        wkRow.detailLabel.stringValue = detail
        wkRow.detailLabel.toolTip = detail
        wkRow.detailLabel.isHidden = false
        wkProgress.isHidden = progress == nil
        wkProgress.isIndeterminate = progress == -1
        if progress == -1 { wkProgress.startAnimation(nil) } else { wkProgress.stopAnimation(nil) }
        wkProgress.doubleValue = progress ?? 0
    }

    @objc private func installWhisperKit() {
        WhisperKitEngine.shared.install()
    }
}

/// Right side of a model row: "In use", or a Use button once downloaded,
/// plus the download/delete action.
private func modelControls(inUse: NSTextField, use: NSButton, action: NSButton) -> [NSView] {
    inUse.stringValue = "✓ In use"
    inUse.font = .systemFont(ofSize: 12, weight: .semibold)
    inUse.textColor = Palette.accent
    use.bezelStyle = .rounded
    use.controlSize = .small
    action.bezelStyle = .rounded
    action.controlSize = .small
    return [inUse, use, action]
}

private final class MLXModelRowView: NSView {

    private let model: MLXModel
    private let settings: Settings
    private let runtime: MLXRuntime
    private let onUpdate: () -> Void

    private let inUse = NSTextField(labelWithString: "")
    private lazy var use = NSButton(title: "Use", target: self, action: #selector(selectModel))
    private lazy var action = NSButton(title: "Download", target: self, action: #selector(performAction))

    init(model: MLXModel, settings: Settings, runtime: MLXRuntime, onUpdate: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        self.runtime = runtime
        self.onUpdate = onUpdate
        super.init(frame: .zero)

        let row = Row(model.recommended ? "\(model.name)  ★" : model.name,
                      detail: "\(model.size) · \(model.note)",
                      modelControls(inUse: inUse, use: use, action: action))
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func refresh() {
        let installed = runtime.isModelDownloaded(model)
        let selected = settings.mlxModel == model.repo
        inUse.isHidden = !(installed && selected)
        use.isHidden = !installed || selected
        action.title = installed ? "Delete" : "Download"
        action.bezelColor = installed ? nil : Palette.accent
        action.isEnabled = !runtime.isBusy
    }

    @objc private func selectModel() {
        settings.mlxModel = model.repo
        if settings.keepModelLoaded, runtime.readyPython() != nil {
            MLXEngine.shared.preload(repo: model.repo)
        }
        onUpdate()
    }

    @objc private func performAction() {
        if runtime.isModelDownloaded(model) {
            runtime.deleteModel(model)
            if settings.mlxModel == model.repo { settings.mlxModel = "" }
        } else {
            runtime.downloadModel(model)
        }
        onUpdate()
    }
}

private final class CppModelRowView: NSView {

    private let descriptor: ModelDescriptor
    private let settings: Settings
    private let store: ModelStore
    private let onUpdate: () -> Void

    private var row: Row!
    private let inUse = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private lazy var use = NSButton(title: "Use", target: self, action: #selector(selectModel))
    private lazy var action = NSButton(title: "Download", target: self, action: #selector(performAction))

    init(descriptor: ModelDescriptor, settings: Settings, store: ModelStore, onUpdate: @escaping () -> Void) {
        self.descriptor = descriptor
        self.settings = settings
        self.store = store
        self.onUpdate = onUpdate
        super.init(frame: .zero)

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .small
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 90).isActive = true

        row = Row(descriptor.recommended ? "\(descriptor.name)  ★" : descriptor.name,
                  detail: "",
                  [progress] + modelControls(inUse: inUse, use: use, action: action))
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func refresh() {
        let path = store.path(for: descriptor.file).path
        let installed = store.installed.contains(descriptor.file)
        let downloading = store.isDownloading(descriptor.file)
        let selected = settings.modelPath == path

        inUse.isHidden = !(installed && selected)
        use.isHidden = !installed || selected || downloading
        progress.isHidden = !downloading
        progress.doubleValue = store.progress[descriptor.file] ?? 0

        row.detailLabel.isHidden = false
        if let error = store.errors[descriptor.file], !downloading {
            row.detailLabel.stringValue = error
            row.detailLabel.toolTip = error
            row.detailLabel.textColor = Palette.bad
        } else {
            row.detailLabel.stringValue = "\(descriptor.size) · \(descriptor.note)"
            row.detailLabel.toolTip = row.detailLabel.stringValue
            row.detailLabel.textColor = Palette.secondary
        }
        action.title = downloading ? "Cancel" : (installed ? "Delete" : "Download")
        action.bezelColor = installed || downloading ? nil : Palette.accent
    }

    @objc private func selectModel() {
        settings.modelPath = store.path(for: descriptor.file).path
        onUpdate()
    }

    @objc private func performAction() {
        if store.isDownloading(descriptor.file) {
            store.cancel(descriptor.file)
        } else if store.installed.contains(descriptor.file) {
            if settings.modelPath == store.path(for: descriptor.file).path { settings.modelPath = "" }
            store.delete(descriptor)
        } else {
            store.download(descriptor)
        }
        onUpdate()
    }
}

// MARK: - Advanced

final class AdvancedPane: Pane {

    private let settings: Settings
    private let onChange: () -> Void
    private let threadsValue = label("", size: 12, color: Palette.secondary)
    private let threadsStepper = NSStepper()
    private let maxValue = label("", size: 12, color: Palette.secondary)
    private let maxSlider = NSSlider()
    private let prompt = NSTextView()
    private let binaryValue = label("", size: 12)
    private var loading = false
    private let width: CGFloat

    init(settings: Settings, onChange: @escaping () -> Void, width: CGFloat) {
        self.settings = settings
        self.onChange = onChange
        self.width = width
        super.init()

        threadsStepper.minValue = 1
        threadsStepper.maxValue = 16
        threadsStepper.increment = 1
        threadsStepper.target = self
        threadsStepper.action = #selector(threadsChanged)

        maxSlider.minValue = 10
        maxSlider.maxValue = 600
        maxSlider.isContinuous = false  // one change per drag, not one per pixel
        maxSlider.trackFillColor = Palette.accent
        maxSlider.target = self
        maxSlider.action = #selector(maxChanged)
        maxSlider.translatesAutoresizingMaskIntoConstraints = false
        maxSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true

        prompt.font = .systemFont(ofSize: 13)
        prompt.textColor = Palette.ink
        prompt.drawsBackground = false
        prompt.isRichText = false
        prompt.textContainerInset = NSSize(width: 0, height: 4)
        prompt.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = prompt
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        prompt.autoresizingMask = [.width]
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // The window's inset field style, as in the Dictionary editor.
        let field = FillView(color: Palette.wash, radius: 7, border: Palette.separator)
        field.addSubview(scroll)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: width - 28),
            field.heightAnchor.constraint(equalToConstant: 56),
            scroll.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: field.topAnchor, constant: 3),
            scroll.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: -3),
        ])
        let promptDetail = label("Names, jargon or acronyms to bias recognition. Leave empty to turn it off.", size: 12, color: Palette.secondary)
        let promptBox = NSStackView(views: [label("Vocabulary prompt", weight: .medium), promptDetail, field])
        promptBox.orientation = .vertical
        promptBox.alignment = .leading
        promptBox.spacing = 2
        promptBox.setCustomSpacing(8, after: promptDetail)
        promptBox.edgeInsets = NSEdgeInsets(top: 11, left: 14, bottom: 14, right: 14)

        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseBinary))
        choose.controlSize = .small
        choose.bezelStyle = .rounded
        let reset = NSButton(title: "Reset…", target: self, action: #selector(resetAll))
        reset.controlSize = .small
        reset.bezelStyle = .rounded
        reset.contentTintColor = Palette.bad

        addArrangedSubview(card("Recognition", [
            promptBox,
            Row("Max recording length", detail: "Recording stops on its own after this.", [maxValue, maxSlider]),
            Row("CPU threads", detail: "whisper.cpp only", [threadsValue, threadsStepper]),
            Row("whisper-cli binary", detail: "brew install whisper-cpp", [binaryValue, choose]),
        ], width: width))
        addArrangedSubview(card(nil, [
            Row("Reset all settings", detail: "Downloaded models and the MLX runtime are kept.", [reset]),
        ], width: width))
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func reload() {
        loading = true
        threadsValue.stringValue = "\(settings.threads)"
        threadsStepper.integerValue = settings.threads
        maxValue.stringValue = "\(Int(settings.maxSeconds)) s"
        maxSlider.doubleValue = settings.maxSeconds
        if prompt.string != settings.initialPrompt {
            prompt.string = settings.initialPrompt
        }
        let resolved = Transcriber.resolveBinary(configured: settings.whisperBinary)
        binaryValue.stringValue = resolved.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "not found"
        binaryValue.textColor = resolved == nil ? Palette.bad : Palette.secondary
        loading = false
    }

    @objc private func threadsChanged() {
        settings.threads = threadsStepper.integerValue
        reload()
        onChange()
    }

    @objc private func maxChanged() {
        settings.maxSeconds = maxSlider.doubleValue.rounded()
        reload()
        onChange()
    }

    @objc private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Select the whisper-cli executable"
        if panel.runModal() == .OK, let url = panel.url {
            settings.whisperBinary = url.path
            reload()
            onChange()
        }
    }

    @objc private func resetAll() {
        let alert = NSAlert()
        alert.messageText = "Reset all Foxtation settings?"
        alert.informativeText = "Downloaded models and the MLX runtime are kept."
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

extension AdvancedPane: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard !loading else { return }
        settings.initialPrompt = prompt.string
    }
}

// MARK: - Hot key recorder

final class RecorderButton: NSView {

    var onCapture: ((UInt32, UInt32) -> Void)?

    private var code: UInt32 = 0
    private var mods: UInt32 = 0
    private var recording = false
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1

        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshChrome()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
        refreshChrome()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        refreshChrome()
        return true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }

        // Ignore presses of the modifier keys themselves.
        let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeyCodes.contains(Int(event.keyCode)) { return }
        // Escape cancels recording and keeps the current shortcut.
        if event.keyCode == 53, carbon == 0 {
            window?.makeFirstResponder(nil)
            return
        }
        // Plain or ⇧ keys would hijack typing, and ⌘ alone (⌘V, ⌘C…) every app's shortcuts.
        guard HotKey.isAllowed(modifiers: carbon) else { NSSound.beep(); return }

        code = UInt32(event.keyCode)
        mods = carbon
        recording = false
        window?.makeFirstResponder(nil)
        onCapture?(code, mods)
        refreshChrome()
    }

    func update(keyCode: UInt32, modifiers: UInt32) {
        if recording, window?.firstResponder !== self {
            recording = false  // window was closed or focus moved away mid-recording
        }
        guard !recording else { return }
        code = keyCode
        mods = modifiers
        refreshChrome()
    }

    private func refreshChrome() {
        label.stringValue = recording ? "Press shortcut…" : HotKey.describe(keyCode: code, modifiers: mods)
        label.textColor = recording ? Palette.accent : Palette.ink
        needsDisplay = true
    }

    override func updateLayer() {
        // The window's inset field style; accent while it listens for keys.
        layer?.borderColor = (recording ? Palette.accent : Palette.separator).cgColor
        layer?.backgroundColor = (recording ? Palette.accent.withAlphaComponent(0.10) : Palette.wash).cgColor
    }
}
