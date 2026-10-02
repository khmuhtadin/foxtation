import Foundation

struct ModelDescriptor: Hashable {
    var name: String
    var file: String
    var size: String
    var note: String
    var recommended: Bool = false
}

/// Catalogue plus downloader for ggml models hosted on Hugging Face.
final class ModelStore: NSObject {

    static let shared = ModelStore()

    static let catalog: [ModelDescriptor] = [
        ModelDescriptor(name: "Tiny", file: "ggml-tiny.bin", size: "75 MB",
                        note: "Fastest, lowest accuracy"),
        ModelDescriptor(name: "Base", file: "ggml-base.bin", size: "142 MB",
                        note: "Quick, decent for clear speech"),
        ModelDescriptor(name: "Small", file: "ggml-small.bin", size: "466 MB",
                        note: "Good balance"),
        ModelDescriptor(name: "Large v3 Turbo (q5_0)", file: "ggml-large-v3-turbo-q5_0.bin", size: "547 MB",
                        note: "Best speed/accuracy trade-off", recommended: true),
        ModelDescriptor(name: "Large v3 Turbo", file: "ggml-large-v3-turbo.bin", size: "1.5 GB",
                        note: "Highest accuracy, slower"),
    ]

    /// Fired on the main thread whenever install state or progress changes.
    var onChange: (() -> Void)?

    private(set) var installed: Set<String> = []
    private(set) var progress: [String: Double] = [:]
    private(set) var errors: [String: String] = [:]

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private let directory: URL
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    override private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Foxtation/models", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        refresh()
    }

    var modelsDirectory: URL { directory }

    func path(for file: String) -> URL { directory.appendingPathComponent(file) }

    func refresh() {
        var found: Set<String> = []
        for descriptor in Self.catalog where FileManager.default.fileExists(atPath: path(for: descriptor.file).path) {
            found.insert(descriptor.file)
        }
        // Models the user dropped in by hand still count as available.
        if !found.isEmpty || installed != found {
            installed = found
        }
    }

    func isDownloading(_ file: String) -> Bool { tasks[file] != nil }

    func download(_ descriptor: ModelDescriptor) {
        guard tasks[descriptor.file] == nil else { return }
        errors[descriptor.file] = nil
        progress[descriptor.file] = 0
        onChange?()

        let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(descriptor.file)")!
        let task = session.downloadTask(with: url)
        task.taskDescription = descriptor.file
        tasks[descriptor.file] = task
        task.resume()
    }

    func cancel(_ file: String) {
        tasks[file]?.cancel()
        tasks[file] = nil
        progress[file] = nil
        onChange?()
    }

    func delete(_ descriptor: ModelDescriptor) {
        try? FileManager.default.removeItem(at: path(for: descriptor.file))
        refresh()
        onChange?()
    }
}

extension ModelStore: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let file = downloadTask.taskDescription else { return }
        let fraction = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        DispatchQueue.main.async {
            guard self.tasks[file] === downloadTask else { return }
            self.progress[file] = fraction
            self.onChange?()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let file = downloadTask.taskDescription else { return }
        let destination = path(for: file)
        // A 404/5xx or captive-portal page still "downloads"; never install it as a model.
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            DispatchQueue.main.async {
                guard self.tasks[file] === downloadTask else { return }
                self.tasks[file] = nil
                self.progress[file] = nil
                self.errors[file] = "Download failed (HTTP \(status))"
                self.onChange?()
            }
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            DispatchQueue.main.async {
                guard self.tasks[file] === downloadTask else { return }
                self.tasks[file] = nil
                self.progress[file] = nil
                self.refresh()
                if Settings.shared.modelPath.isEmpty
                    || !FileManager.default.fileExists(atPath: Settings.shared.modelPath) {
                    Settings.shared.modelPath = destination.path
                }
                self.onChange?()
            }
        } catch {
            DispatchQueue.main.async {
                guard self.tasks[file] === downloadTask else { return }
                self.tasks[file] = nil
                self.progress[file] = nil
                self.errors[file] = error.localizedDescription
                self.onChange?()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let file = task.taskDescription, let error else { return }
        let nsError = error as NSError
        DispatchQueue.main.async {
            guard self.tasks[file] === task else { return }
            self.tasks[file] = nil
            self.progress[file] = nil
            if nsError.code != NSURLErrorCancelled {
                self.errors[file] = error.localizedDescription
            }
            self.onChange?()
        }
    }
}
