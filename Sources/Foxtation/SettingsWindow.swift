import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

/// AppKit settings UI. Written without SwiftUI on purpose: the machine only has
/// the Command Line Tools, which do not ship the SwiftUI macro plugin.
final class SettingsWindow: NSWindow {

    private let content: SettingsContent

    init(settings: Settings, onChange: @escaping () -> Void) {
        content = SettingsContent(settings: settings, onChange: onChange)
        super.init(contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: 400),
                   styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        title = "Foxtation"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        contentView = content
        content.fitWindow(animated: false)
        center()
    }

    func reload() {
        content.reload()
    }

    override func becomeKey() {
        super.becomeKey()
        content.reload()
    }
}

// MARK: - Palette

/// Colors from the app icon: ice-blue tile, white fox, indigo waveform, navy ink.
enum Palette {
    static let background = dynamic(light: 0xDCE7F8, dark: 0x151A33)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1F2647)
    static let ink = dynamic(light: 0x1E2140, dark: 0xEEF1FF)
    static let secondary = dynamic(light: 0x5E6689, dark: 0x9AA3C9)
    static let separator = dynamic(light: 0xE6ECF7, dark: 0x2B3460)
    static let accent = dynamic(light: 0x5B6FE0, dark: 0x8696FF)
    static let track = dynamic(light: 0xC9D6EC, dark: 0x39426E)
    static let good = dynamic(light: 0x2E9E62, dark: 0x5FD394)
    static let bad = dynamic(light: 0xD8456B, dark: 0xF6A3BC)  // the inner-ear pink, deepened for contrast

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}

private enum Layout {
    static let windowWidth: CGFloat = 560
    static let margin: CGFloat = 20
    static let cardWidth: CGFloat = windowWidth - margin * 2
}

// MARK: - Root

final class SettingsContent: FillView {

    private let panes: [Pane]
    private let tabs = NSSegmentedControl()
    private let holder = NSView()
    private var current: Pane?

    init(settings: Settings, onChange: @escaping () -> Void) {
        panes = [
            GeneralPane(settings: settings, onChange: onChange),
            EnginePane(settings: settings, onChange: onChange),
            AdvancedPane(settings: settings, onChange: onChange),
        ]
        super.init(color: Palette.background)

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let name = label("Foxtation", size: 15, weight: .semibold)
        let tagline = label("Local dictation for your Mac", size: 11, color: Palette.secondary)
        let titles = NSStackView(views: [name, tagline])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1

        tabs.segmentStyle = .rounded
        tabs.trackingMode = .selectOne
        tabs.segmentCount = 3
        for (index, title) in ["General", "Engine", "Advanced"].enumerated() {
            tabs.setLabel(title, forSegment: index)
            tabs.setWidth(78, forSegment: index)
        }
        tabs.selectedSegmentBezelColor = Palette.accent
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged)

        let header = NSStackView(views: [icon, titles, NSView(), tabs])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        holder.translatesAutoresizingMaskIntoConstraints = false
        let column = NSStackView(views: [header, holder])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 16
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.margin),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.margin),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 34),  // below the traffic lights
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.margin),
            header.widthAnchor.constraint(equalToConstant: Layout.cardWidth),
            holder.widthAnchor.constraint(equalToConstant: Layout.cardWidth),
            widthAnchor.constraint(equalToConstant: Layout.windowWidth),
        ])

        for pane in panes {
            pane.onResize = { [weak self] in self?.fitWindow(animated: true) }
        }
        show(0)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func reload() {
        panes.forEach { $0.reload() }
    }

    func show(_ index: Int) {
        current?.removeFromSuperview()
        let pane = panes[index]
        pane.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            pane.topAnchor.constraint(equalTo: holder.topAnchor),
            pane.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        current = pane
        tabs.selectedSegment = index
        pane.reload()
    }

    /// The window is exactly as tall as the visible pane, keeping its top edge put.
    func fitWindow(animated: Bool) {
        layoutSubtreeIfNeeded()
        guard let window else { return }
        let height = fittingSize.height
        var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: height))
        frame.origin.x = window.frame.minX
        frame.origin.y = window.frame.maxY - frame.height
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }

    @objc private func tabChanged() {
        show(tabs.selectedSegment)
        fitWindow(animated: true)
    }
}

// MARK: - Building blocks

/// A plain view filled with a (dynamic) color, optionally rounded.
class FillView: NSView {

    var color: NSColor { didSet { needsDisplay = true } }

    init(color: NSColor, radius: CGFloat = 0) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = color.cgColor  // re-resolved on every appearance change
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
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
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
        titleLabel = label(title)
        detailLabel = label(detail ?? "", size: 11, color: Palette.secondary)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.isHidden = detail == nil

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        edgeInsets = NSEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)
        setViews([labels, NSView()] + controls, in: .leading)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
}

/// A titled white card holding rows separated by hairlines.
private func card(_ title: String?, _ rows: [NSView]) -> NSStackView {
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

    let background = FillView(color: Palette.card, radius: 12)
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
    group.spacing = 6
    if let title {
        let heading = label(title.uppercased(), size: 11, weight: .semibold, color: Palette.secondary)
        group.addArrangedSubview(heading)
        group.setCustomSpacing(6, after: heading)
    }
    group.addArrangedSubview(background)
    background.widthAnchor.constraint(equalToConstant: Layout.cardWidth).isActive = true
    return group
}

/// A pane is a column of cards; AppDelegate-facing state lives in the subclasses.
private class Pane: NSStackView {

    /// Asks the window to re-fit after rows were shown or hidden.
    var onResize: (() -> Void)?

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 16
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func reload() {}
}

private func popup(_ titles: [String], target: AnyObject, action: Selector) -> NSPopUpButton {
    let button = NSPopUpButton()
    button.addItems(withTitles: titles)
    button.target = target
    button.action = action
    return button
}

// MARK: - General

private final class GeneralPane: Pane {

    private let settings: Settings
    private let onChange: () -> Void
    private var loading = false

    private let rightOption = Toggle()
    private let recorder = RecorderButton()
    private var modePopup: NSPopUpButton!
    private var languagePopup: NSPopUpButton!
    private let translate = Toggle()
    private var methodPopup: NSPopUpButton!
    private let restoreClipboard = Toggle()
    private let showHUD = Toggle()
    private var placementPopup: NSPopUpButton!
    private let sounds = Toggle()
    private let launchAtLogin = Toggle()
    private let microphone = PermissionRow(title: "Microphone", detail: "Records your voice")
    private let accessibility = PermissionRow(title: "Accessibility", detail: "Pastes text into other apps")
    private var timer: Timer?

    init(settings: Settings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        super.init()

        modePopup = popup(["Press to start, again to stop", "Hold while speaking"],
                          target: self, action: #selector(modeChanged))
        languagePopup = popup(Settings.languages.map(\.label), target: self, action: #selector(languageChanged))
        methodPopup = popup(["Paste (⌘V)", "Type characters"], target: self, action: #selector(methodChanged))
        placementPopup = popup(HUDPlacement.allCases.map(\.label), target: self, action: #selector(placementChanged))

        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 120).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 24).isActive = true
        recorder.onCapture = { [weak self] code, mods in
            guard let self else { return }
            self.settings.hotKeyCode = code
            self.settings.hotKeyModifiers = mods
            self.reload()
            self.onChange()
        }

        rightOption.onToggle = { [weak self] on in self?.settings.holdRightOption = on; self?.onChange() }
        translate.onToggle = { [weak self] on in self?.settings.translate = on; self?.onChange() }
        restoreClipboard.onToggle = { [weak self] on in self?.settings.restoreClipboard = on }
        showHUD.onToggle = { [weak self] on in self?.settings.showHUD = on }
        sounds.onToggle = { [weak self] on in self?.settings.playSounds = on }
        launchAtLogin.onToggle = { [weak self] on in self?.settings.launchAtLogin = on; self?.onChange() }

        addArrangedSubview(card("Dictation", [
            Row("Hold right ⌥ to talk", detail: "Double-tap it for hands-free", [rightOption]),
            Row("Shortcut", detail: "Must include ⌘, ⌥ or ⌃ — Esc cancels", [recorder]),
            Row("Shortcut mode", [modePopup]),
            Row("Language", [languagePopup]),
            Row("Translate to English", [translate]),
        ]))
        addArrangedSubview(card("Output", [
            Row("Insert by", [methodPopup]),
            Row("Restore clipboard afterwards", [restoreClipboard]),
            Row("Floating indicator", [placementPopup, showHUD]),
            Row("Start and stop sounds", [sounds]),
            Row("Launch at login", [launchAtLogin]),
        ]))
        addArrangedSubview(card("Permissions", [microphone, accessibility]))

        microphone.onGrant = {
            Permissions.requestMicrophone { granted in
                if !granted { Permissions.openMicrophoneSettings() }
            }
        }
        accessibility.onGrant = {
            Permissions.requestAccessibility(prompt: true)
            Permissions.openAccessibilitySettings()
        }
        // Grants happen in System Settings; poll so the status flips without a reopen.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit { timer?.invalidate() }

    override func reload() {
        loading = true
        rightOption.isOn = settings.holdRightOption
        recorder.update(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
        modePopup.selectItem(at: TriggerMode.allCases.firstIndex(of: settings.triggerMode) ?? 0)
        languagePopup.selectItem(at: Settings.languages.firstIndex { $0.code == settings.language } ?? 0)
        translate.isOn = settings.translate
        methodPopup.selectItem(at: InsertMethod.allCases.firstIndex(of: settings.insertMethod) ?? 0)
        restoreClipboard.isOn = settings.restoreClipboard
        showHUD.isOn = settings.showHUD
        placementPopup.selectItem(at: HUDPlacement.allCases.firstIndex(of: settings.hudPlacement) ?? 0)
        sounds.isOn = settings.playSounds
        launchAtLogin.isOn = settings.launchAtLogin
        refreshPermissions()
        loading = false
    }

    private func refreshPermissions() {
        microphone.update(granted: Permissions.microphoneGranted)
        accessibility.update(granted: Permissions.accessibilityGranted)
    }

    @objc private func modeChanged() {
        guard !loading else { return }
        settings.triggerMode = TriggerMode.allCases[modePopup.indexOfSelectedItem]
        onChange()
    }

    @objc private func languageChanged() {
        guard !loading else { return }
        settings.language = Settings.languages[languagePopup.indexOfSelectedItem].code
        onChange()
    }

    @objc private func methodChanged() {
        guard !loading else { return }
        settings.insertMethod = InsertMethod.allCases[methodPopup.indexOfSelectedItem]
        onChange()
    }

    @objc private func placementChanged() {
        guard !loading else { return }
        settings.hudPlacement = HUDPlacement.allCases[placementPopup.indexOfSelectedItem]
        onChange()
    }
}

/// Permission line: status on the right, plus a Grant button while missing.
private final class PermissionRow: NSView {

    var onGrant: (() -> Void)?

    private let status = label("", size: 12, weight: .medium)
    private lazy var grant = accentButton("Grant…", target: self, action: #selector(grantPressed))

    init(title: String, detail: String) {
        super.init(frame: .zero)
        grant.controlSize = .small
        let row = Row(title, detail: detail, [status, grant])
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func update(granted: Bool) {
        status.stringValue = granted ? "● Granted" : "● Not granted"
        status.textColor = granted ? Palette.good : Palette.bad
        grant.isHidden = granted
    }

    @objc private func grantPressed() { onGrant?() }
}

// MARK: - Engine

private final class EnginePane: Pane {

    private let settings: Settings
    private let onChange: () -> Void
    private let runtime = MLXRuntime.shared

    private let engineControl = NSSegmentedControl()
    private var mlxCard: NSView!
    private var cppCard: NSView!
    private var mlxRows: [MLXModelRowView] = []
    private var cppRows: [CppModelRowView] = []
    private let runtimeStatus = label("", size: 12, weight: .medium)
    private lazy var setupButton = accentButton("Set Up", target: self, action: #selector(setUpRuntime))
    private let keepLoaded = Toggle()
    private var loading = false

    init(settings: Settings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        super.init()

        engineControl.segmentStyle = .rounded
        engineControl.trackingMode = .selectOne
        engineControl.segmentCount = 2
        engineControl.setLabel("MLX · Apple GPU", forSegment: 0)
        engineControl.setLabel("whisper.cpp", forSegment: 1)
        engineControl.selectedSegmentBezelColor = Palette.accent
        engineControl.target = self
        engineControl.action = #selector(engineChanged)
        addArrangedSubview(card(nil, [Row("Engine", detail: "MLX is fastest on Apple silicon", [engineControl])]))

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
        mlxCard = card("MLX models", [Row("Python runtime", [runtimeStatus, setupButton])] + mlxRows
            + [Row("Keep model in memory", detail: "Instant start, uses about 1.6 GB", [keepLoaded])])
        addArrangedSubview(mlxCard)

        cppRows = ModelStore.catalog.map { CppModelRowView(descriptor: $0, settings: settings, store: ModelStore.shared, onUpdate: update) }
        cppCard = card("whisper.cpp models", cppRows
            + [Row("Needs whisper-cli", detail: "brew install whisper-cpp", [])])
        addArrangedSubview(cppCard)

        runtime.onChange = { [weak self] in self?.reload() }
        ModelStore.shared.onChange = { [weak self] in self?.reload() }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func reload() {
        loading = true
        engineControl.selectedSegment = settings.engine == .mlx ? 0 : 1

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
            setupButton.title = "Set Up"
            setupButton.isEnabled = true
        }

        mlxRows.forEach { $0.refresh() }
        cppRows.forEach { $0.refresh() }
        keepLoaded.isOn = settings.keepModelLoaded

        let showMLX = settings.engine == .mlx
        let changed = mlxCard.isHidden == showMLX || cppCard.isHidden != showMLX
        mlxCard.isHidden = !showMLX
        cppCard.isHidden = showMLX
        if changed { onResize?() }
        loading = false
    }

    @objc private func engineChanged() {
        guard !loading else { return }
        settings.engine = engineControl.selectedSegment == 0 ? .mlx : .whisperCpp
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
            row.detailLabel.textColor = Palette.bad
        } else {
            row.detailLabel.stringValue = "\(descriptor.size) · \(descriptor.note)"
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

private final class AdvancedPane: Pane {

    private let settings: Settings
    private let onChange: () -> Void
    private let threadsValue = label("", size: 12, color: Palette.secondary)
    private let threadsStepper = NSStepper()
    private let maxValue = label("", size: 12, color: Palette.secondary)
    private let maxSlider = NSSlider()
    private let prompt = NSTextView()
    private let binaryValue = label("", size: 12)
    private var loading = false

    init(settings: Settings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
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

        prompt.font = .systemFont(ofSize: 12)
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
        let field = FillView(color: Palette.background, radius: 8)  // visible text area
        field.addSubview(scroll)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: Layout.cardWidth - 28),
            field.heightAnchor.constraint(equalToConstant: 52),
            scroll.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: field.topAnchor, constant: 2),
            scroll.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: -2),
        ])
        let promptBox = NSStackView(views: [
            label("Vocabulary prompt"),
            label("Names, jargon or acronyms to bias recognition. Leave empty to disable.", size: 11, color: Palette.secondary),
            field,
        ])
        promptBox.orientation = .vertical
        promptBox.alignment = .leading
        promptBox.spacing = 4
        promptBox.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 8, right: 14)

        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseBinary))
        choose.controlSize = .small
        choose.bezelStyle = .rounded
        let reset = NSButton(title: "Reset…", target: self, action: #selector(resetAll))
        reset.controlSize = .small
        reset.bezelStyle = .rounded
        reset.contentTintColor = Palette.bad

        addArrangedSubview(card("Recognition", [
            promptBox,
            Row("Max recording length", detail: "Recording stops automatically", [maxValue, maxSlider]),
            Row("CPU threads", detail: "whisper.cpp only", [threadsValue, threadsStepper]),
            Row("whisper-cli binary", detail: "brew install whisper-cpp", [binaryValue, choose]),
        ]))
        addArrangedSubview(card(nil, [
            Row("Reset all settings", detail: "Models and the MLX runtime are kept", [reset]),
        ]))
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
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
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
        // Shift alone would hijack ordinary typing (⇧A = capital A) system-wide.
        guard carbon & UInt32(cmdKey | optionKey | controlKey) != 0 else { NSSound.beep(); return }

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
        layer?.borderColor = (recording ? Palette.accent : Palette.track).cgColor
        layer?.backgroundColor = (recording ? Palette.accent.withAlphaComponent(0.10) : Palette.background).cgColor
    }
}
