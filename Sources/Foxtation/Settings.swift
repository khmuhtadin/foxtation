import Foundation

enum TriggerMode: String, CaseIterable {
    case toggle, hold
    var label: String {
        switch self {
        case .toggle: return "Toggle — press to start, press again to stop"
        case .hold:   return "Push to talk — hold the key while speaking"
        }
    }
}

enum InsertMethod: String, CaseIterable {
    case paste, type
    var label: String {
        switch self {
        case .paste: return "Paste (⌘V) — restores your clipboard afterwards"
        case .type:  return "Type characters — slower, leaves clipboard alone"
        }
    }
}

enum TranscriptionEngine: String, CaseIterable {
    case mlx, whisperCpp
    var label: String {
        switch self {
        case .mlx:        return "MLX Whisper — Apple GPU, fastest on Apple silicon"
        case .whisperCpp: return "whisper.cpp — ggml models, no Python"
        }
    }
}

/// Single source of truth for user preferences. Every property persists to
/// UserDefaults on write and notifies `onChange` so open UI stays in sync.
final class Settings {

    static let shared = Settings()

    static let languages: [(code: String, label: String)] = [
        ("auto", "Auto detect"), ("en", "English"), ("id", "Indonesian"),
        ("ms", "Malay"), ("zh", "Chinese"), ("ja", "Japanese"), ("ko", "Korean"),
        ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("pt", "Portuguese"),
        ("ru", "Russian"), ("ar", "Arabic"), ("hi", "Hindi"), ("th", "Thai"),
        ("vi", "Vietnamese"), ("tr", "Turkish"), ("it", "Italian"), ("nl", "Dutch"),
        ("pl", "Polish"),
    ]

    /// Fired after any value changes so the app can re-register the hot key etc.
    var onChange: (() -> Void)?

    var engine: TranscriptionEngine { didSet { persist("engine", engine.rawValue) } }
    var mlxModel: String { didSet { persist("mlxModel", mlxModel) } }
    var keepModelLoaded: Bool { didSet { persist("keepModelLoaded", keepModelLoaded) } }
    var uvPath: String { didSet { persist("uvPath", uvPath) } }
    var modelPath: String { didSet { persist("modelPath", modelPath) } }
    var language: String { didSet { persist("language", language) } }
    var translate: Bool { didSet { persist("translate", translate) } }
    var triggerMode: TriggerMode { didSet { persist("triggerMode", triggerMode.rawValue) } }
    var hotKeyCode: UInt32 { didSet { persist("hotKeyCode", Int(hotKeyCode)) } }
    var hotKeyModifiers: UInt32 { didSet { persist("hotKeyModifiers", Int(hotKeyModifiers)) } }
    var insertMethod: InsertMethod { didSet { persist("insertMethod", insertMethod.rawValue) } }
    var restoreClipboard: Bool { didSet { persist("restoreClipboard", restoreClipboard) } }
    var playSounds: Bool { didSet { persist("playSounds", playSounds) } }
    var holdRightOption: Bool { didSet { persist("holdRightOption", holdRightOption) } }
    var showHUD: Bool { didSet { persist("showHUD", showHUD) } }
    var hudPlacement: HUDPlacement { didSet { persist("hudPlacement", hudPlacement.rawValue) } }
    var launchAtLogin: Bool { didSet { persist("launchAtLogin", launchAtLogin) } }
    var threads: Int { didSet { persist("threads", threads) } }
    var maxSeconds: Double { didSet { persist("maxSeconds", maxSeconds) } }
    var initialPrompt: String { didSet { persist("initialPrompt", initialPrompt) } }
    var whisperBinary: String { didSet { persist("whisperBinary", whisperBinary) } }

    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            "engine": TranscriptionEngine.mlx.rawValue,
            "mlxModel": "mlx-community/whisper-large-v3-turbo",
            "keepModelLoaded": true,
            "uvPath": "",
            "modelPath": "",
            "language": "auto",
            "translate": false,
            "triggerMode": TriggerMode.toggle.rawValue,
            "hotKeyCode": Int(HotKey.defaultKeyCode),
            "hotKeyModifiers": Int(HotKey.defaultModifiers),
            "insertMethod": InsertMethod.paste.rawValue,
            "restoreClipboard": true,
            "playSounds": true,
            "holdRightOption": true,
            "showHUD": true,
            "hudPlacement": HUDPlacement.rightEdge.rawValue,
            "launchAtLogin": false,
            "threads": max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)),
            "maxSeconds": 120.0,
            "initialPrompt": "",
            "whisperBinary": "",
        ])

        modelPath = d.string(forKey: "modelPath") ?? ""
        engine = TranscriptionEngine(rawValue: d.string(forKey: "engine") ?? "") ?? .mlx
        mlxModel = d.string(forKey: "mlxModel") ?? "mlx-community/whisper-large-v3-turbo"
        keepModelLoaded = d.bool(forKey: "keepModelLoaded")
        uvPath = d.string(forKey: "uvPath") ?? ""
        language = d.string(forKey: "language") ?? "auto"
        translate = d.bool(forKey: "translate")
        triggerMode = TriggerMode(rawValue: d.string(forKey: "triggerMode") ?? "") ?? .toggle
        hotKeyCode = UInt32(d.integer(forKey: "hotKeyCode"))
        hotKeyModifiers = UInt32(d.integer(forKey: "hotKeyModifiers"))
        insertMethod = InsertMethod(rawValue: d.string(forKey: "insertMethod") ?? "") ?? .paste
        restoreClipboard = d.bool(forKey: "restoreClipboard")
        playSounds = d.bool(forKey: "playSounds")
        holdRightOption = d.bool(forKey: "holdRightOption")
        showHUD = d.bool(forKey: "showHUD")
        hudPlacement = HUDPlacement(rawValue: d.string(forKey: "hudPlacement") ?? "") ?? .rightEdge
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        threads = d.integer(forKey: "threads")
        maxSeconds = d.double(forKey: "maxSeconds")
        initialPrompt = d.string(forKey: "initialPrompt") ?? ""
        whisperBinary = d.string(forKey: "whisperBinary") ?? ""
    }

    /// Off for the headless CLI, so its flags don't leak into the menu-bar app.
    var persistsChanges = true

    private func persist(_ key: String, _ value: Any) {
        guard persistsChanges else { return }
        d.set(value, forKey: key)
        onChange?()
    }
}
