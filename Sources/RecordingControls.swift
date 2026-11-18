import AppKit
import UniformTypeIdentifiers

// UI state belongs to the main thread; the recorder encodes away from it.
final class RecordingControls {
    private enum Phase: String { case idle, starting, recording, stopping, saving, unsaved }

    private let recorder = WindowRecording()
    private let indicator = RecordingIndicator()
    private weak var window: NSWindow?
    private var phase = Phase.idle {
        didSet { onStateChange?() }
    }
    private var terminateAfterSave = false
    private var pendingMovie: (url: URL, interrupted: Bool)?
    private(set) var lockedFrameSize: NSSize?
    var onStateChange: (() -> Void)?

    var state: String { phase.rawValue }
    var menuTitle: String {
        switch phase {
        case .idle: return "Start Recording"
        case .starting: return "Starting Recording…"
        case .recording: return "Stop Recording"
        case .stopping: return "Finishing Recording…"
        case .saving,.unsaved: return "Save Recording…"
        }
    }
    var isBusy: Bool { phase != .idle }
    var canToggle: Bool { phase == .idle || phase == .recording || phase == .unsaved }
    var canDiscard: Bool { phase == .unsaved }

    init() {
        indicator.onStop = { [weak self] in self?.stop() }
        recorder.onInterruption = { [weak self] error in self?.stop(interruption:error) }
    }

    func toggle(in window: NSWindow, pixels: NSSize, fps: Int) {
        if phase == .recording { stop(); return }
        if phase == .unsaved { beginSave(); return }
        guard phase == .idle, window.attachedSheet == nil, !window.isMiniaturized,
              !window.inLiveResize, window.windowNumber > 0 else { return }
        self.window = window
        let windowID = window.windowNumber
        lockedFrameSize = window.frame.size
        phase = .starting
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await recorder.start(windowID:windowID,size:pixels,fps:fps)
                guard phase == .starting else { return }
                indicator.show()
                phase = .recording
            } catch {
                finish()
                showError("Couldn’t Start Recording",error:error)
            }
        }
    }

    func prepareToTerminate() -> NSApplication.TerminateReply {
        switch phase {
        case .idle: return .terminateNow
        case .recording:
            terminateAfterSave = true
            stop()
            return .terminateLater
        case .unsaved:
            if !terminateAfterSave {
                terminateAfterSave = true
                DispatchQueue.main.async { [self] in confirmUnsavedQuit() }
            }
            return .terminateLater
        case .starting,.stopping,.saving: return .terminateCancel
        }
    }

    private func stop(interruption: Error? = nil) {
        guard phase == .recording || (phase == .starting && interruption != nil) else { return }
        indicator.hide()
        phase = .stopping
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let movie = try await recorder.stop()
                lockedFrameSize = nil
                pendingMovie = (movie,interruption != nil)
                beginSave()
            } catch {
                finish()
                showError("Couldn’t Finish Recording",error:interruption ?? error)
            }
        }
    }

    private func beginSave() {
        guard let pendingMovie else { return }
        phase = .saving
        presentSavePanel(for:pendingMovie.url,interrupted:pendingMovie.interrupted)
    }

    func discardUnsaved() {
        guard phase == .unsaved, let pendingMovie else { return }
        discard(pendingMovie.url)
        finish(allowTermination:true)
    }

    private func confirmUnsavedQuit() {
        let alert = NSAlert()
        alert.messageText = "Save This Recording Before Quitting?"
        alert.informativeText = "The recording hasn’t been saved yet."
        alert.addButton(withTitle:"Save…")
        alert.addButton(withTitle:"Discard and Quit")
        alert.addButton(withTitle:"Cancel").keyEquivalent = "\u{1b}"
        present(alert) { [self] response in
            switch response {
            case .alertFirstButtonReturn: beginSave()
            case .alertSecondButtonReturn: discardUnsaved()
            default: answerTermination(false)
            }
        }
    }

    private func presentSavePanel(for movie: URL, interrupted: Bool) {
        NSApp.activate(ignoringOtherApps:true)
        let panel = NSSavePanel()
        panel.title = "Save Recording"
        if interrupted { panel.message = "Capture stopped early. You can save the video recorded so far." }
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for:.moviesDirectory,in:.userDomainMask).first
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier:"en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH-mm-ss"
        panel.nameFieldStringValue = "Asteroid Squadron \(stamp.string(from:Date())).mp4"
        let complete: (NSApplication.ModalResponse) -> Void = { [self] result in
            guard result == .OK, let destination = panel.url else {
                deferSaving()
                return
            }
            save(movie,to:destination)
        }
        if let window, window.isVisible, window.attachedSheet == nil { panel.beginSheetModal(for:window,completionHandler:complete) }
        else { panel.begin(completionHandler:complete) }
    }

    private func save(_ movie: URL, to destination: URL) {
        DispatchQueue.global(qos:.userInitiated).async { [self] in
            let result = Result { try Self.export(movie,to:destination) }
            DispatchQueue.main.async { [self] in
                switch result {
                case .success:
                    discard(movie)
                    finish(allowTermination:true)
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = "Couldn’t Save Recording"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle:"Choose Location…")
                    alert.addButton(withTitle:"Save Later")
                    let complete: (NSApplication.ModalResponse) -> Void = { [self] response in
                        if response == .alertFirstButtonReturn { beginSave() }
                        else { deferSaving() }
                    }
                    present(alert,completion:complete)
                }
            }
        }
    }

    private static func export(_ movie: URL, to destination: URL) throws {
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        let files = FileManager.default
        if !files.fileExists(atPath:destination.path) {
            try files.moveItem(at:movie,to:destination)
            return
        }
        // NSSavePanel has already confirmed the replacement. Stage the copy on
        // the destination volume so a failed copy never truncates that file.
        let staging = try files.url(for:.itemReplacementDirectory,in:.userDomainMask,appropriateFor:destination,create:true)
        defer { try? files.removeItem(at:staging) }
        let copy = staging.appendingPathComponent(destination.lastPathComponent)
        try files.copyItem(at:movie,to:copy)
        _ = try files.replaceItemAt(destination,withItemAt:copy,backupItemName:nil,options:.usingNewMetadataOnly)
    }

    private func discard(_ movie: URL) { try? FileManager.default.removeItem(at:movie) }

    private func deferSaving() {
        phase = .unsaved
        answerTermination(false)
    }

    private func finish(allowTermination: Bool = false) {
        indicator.hide()
        lockedFrameSize = nil
        pendingMovie = nil
        phase = .idle
        answerTermination(allowTermination)
    }

    private func answerTermination(_ allowTermination: Bool) {
        if terminateAfterSave {
            terminateAfterSave = false
            NSApp.reply(toApplicationShouldTerminate:allowTermination)
        }
    }

    private func showError(_ title: String, error: Error) {
        if case RecordingError.permissionDenied = error {
            showCapturePermissionHelp()
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        if error is RecordingError {
            alert.informativeText = error.localizedDescription
        } else {
            let failure = error as NSError
            alert.informativeText = "\(failure.localizedDescription)\n\n\(failure.domain) (\(failure.code))"
        }
        present(alert) { _ in }
    }

    private func showCapturePermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "Allow Window Recording"
        alert.informativeText = "Open Screen & System Audio Recording in System Settings and enable Asteroid Squadron. If it is already enabled, switch it off and back on, then quit and reopen this app.\n\nApp location\n\(Bundle.main.bundleURL.path)"
        alert.addButton(withTitle:"Open System Settings")
        alert.addButton(withTitle:"Not Now")
        present(alert) { response in
            guard response == .alertFirstButtonReturn,
                  let settings = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
            NSWorkspace.shared.open(settings)
        }
    }

    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible, window.attachedSheet == nil { alert.beginSheetModal(for:window,completionHandler:completion) }
        else { completion(alert.runModal()) }
    }
}
