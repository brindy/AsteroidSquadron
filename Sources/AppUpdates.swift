import AppKit
import Sparkle

// Created with the app delegate, then started only after the application launches.
// Sparkle's standard interface owns update prompts and asks before enabling checks.
final class AppUpdates: NSObject, NSMenuItemValidation {
    private var controller: SPUStandardUpdaterController?
    private var installationDelegate: UpdateInstallationDelegate?
    var canInstallUpdate: (() -> Bool)?

    func start() {
        MainActor.assumeIsolated {
            guard controller == nil else { return }
            let delegate = UpdateInstallationDelegate { [weak self] in self?.canInstallUpdate?() ?? true }
            installationDelegate = delegate
            controller = SPUStandardUpdaterController(startingUpdater:true,updaterDelegate:delegate,userDriverDelegate:nil)
        }
    }

    func resumePendingUpdateIfReady() {
        MainActor.assumeIsolated { installationDelegate?.resumeIfReady() }
    }

    func checkForUpdatesMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title:"Check for Updates…",action:#selector(checkForUpdates(_:)),keyEquivalent:"")
        item.target = self
        return item
    }

    func automaticChecksMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title:"Check for Updates Automatically",action:#selector(toggleAutomaticChecks(_:)),keyEquivalent:"")
        item.target = self
        return item
    }

    @objc func checkForUpdates(_ sender: Any?) {
        MainActor.assumeIsolated { controller?.checkForUpdates(sender) }
    }

    @objc private func toggleAutomaticChecks(_ sender: NSMenuItem) {
        MainActor.assumeIsolated {
            guard let updater = controller?.updater else { return }
            updater.automaticallyChecksForUpdates.toggle()
            sender.state = updater.automaticallyChecksForUpdates ? .on : .off
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        MainActor.assumeIsolated {
            guard let updater = controller?.updater else { return false }
            if menuItem.action == #selector(checkForUpdates(_:)) { return updater.canCheckForUpdates }
            menuItem.state = updater.automaticallyChecksForUpdates ? .on : .off
            return true
        }
    }
}

@MainActor
private final class UpdateInstallationDelegate: NSObject, SPUUpdaterDelegate {
    private let canInstall: () -> Bool
    private var pendingInstallation: (() -> Void)?

    init(canInstall: @escaping () -> Bool) {
        self.canInstall = canInstall
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !canInstall() else { return false }
        pendingInstallation = installHandler
        return true
    }

    func resumeIfReady() {
        guard canInstall(), let install = pendingInstallation else { return }
        pendingInstallation = nil
        DispatchQueue.main.async { install() }
    }
}
