import AppKit
import ServiceManagement
import SailCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let engine = EngineController()
    private var item: NSStatusItem!
    private let setupMonitor = SetupMonitor(probe: EngineController.supportReady)
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupMonitor.changed = { [weak self] in self?.refresh() }
        setupMonitor.shouldCheck = { [weak self] in self?.engine.isRunning == false }
        engine.changed = { [weak self] in self?.refresh() }
        engine.finished = { [weak self] in
            guard let self, self.quitting else { return }
            self.quitting = false
            NSApp.reply(toApplicationShouldTerminate: self.engine.session.state != .uncertain)
            if self.engine.session.state == .uncertain { self.showCleanupError() }
        }
        refresh()
        setupMonitor.start()
    }
    func menuWillOpen(_ menu: NSMenu) { setupMonitor.refresh(); refreshMenu(menu) }
    private func refresh() {
        guard item != nil else { return }
        let state = engine.session.state
        if state == .uncertain {
            item.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Sleep needs attention")
        } else {
            item.button?.image = SailIcon.image(raised: state == .on || state == .stopping)
        }
        item.button?.appearsDisabled = state == .starting || state == .stopping
        item.button?.title = " \(engine.session.statusEmoji)"
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "Full Sail — \(state == .on ? "Sails up (keep awake)" : state == .off ? "Sails down (normal sleep)" : engine.session.detail)"
        item.button?.setAccessibilityLabel(item.button?.toolTip)
        if item.menu == nil {
            let menu = NSMenu(); menu.delegate = self; item.menu = menu
        }
        refreshMenu(item.menu!)
    }
    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, action: Selector? = nil, enabled: Bool = true) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
        row.target = self; row.isEnabled = enabled && action != nil
        menu.addItem(row); return row
    }
    private func refreshMenu(_ menu: NSMenu) {
        menu.autoenablesItems = false; menu.removeAllItems()
        let title = add(menu, "Full Sail")
        title.attributedTitle = NSAttributedString(string: "Full Sail", attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)])
        let state = engine.session.state
        let emoji = engine.session.statusEmoji
        add(menu, "\(emoji) " + (state == .on ? "Sails up (Mac stays awake)" : state == .off ? "Sails down (normal sleep)" : engine.session.detail))
        if state == .on {
            add(menu, engine.remaining ?? "Until you turn off keep-awake")
            add(menu, "\(engine.session.guardEmoji) \(engine.session.guardDetail)")
        } else if state == .off && !engine.session.detail.hasPrefix("Your Mac") {
            add(menu, "\(emoji) \(engine.session.detail)")
        }
        menu.addItem(.separator())
        if state == .uncertain && !engine.isRunning {
            add(menu, "Restore Normal Sleep…", action: #selector(restore))
        } else if engine.isRunning {
            add(menu, state == .stopping ? "Lowering Sails (turning off)…" : "🛌 Lower Sails (turn off)", action: #selector(stop), enabled: state != .stopping)
        } else {
            add(menu, "☕ Raise Sails (turn on)", action: #selector(start), enabled: setupMonitor.ready)
            let duration = NSMenu()
            for minutes in [15, 30, 60, 120, 240] {
                let row = add(duration, minutes < 60 ? "For \(minutes) Minutes" : "For \(minutes / 60) Hour\(minutes == 60 ? "" : "s")", action: #selector(startTimed(_:)))
                row.tag = minutes
            }
            let durationItem = add(menu, "Keep Awake For…")
            durationItem.isEnabled = setupMonitor.ready; durationItem.submenu = duration
        }
        menu.addItem(.separator())
        if !setupMonitor.ready {
            if !setupMonitor.hasChecked {
                add(menu, "Checking setup automatically…")
            } else {
                add(menu, "One-time setup needed to turn on keep-awake.")
                add(menu, "Set Up Full Sail (allow closed-lid use)…", action: #selector(setup), enabled: !engine.isRunning)
                add(menu, "Setup completion is detected automatically.")
            }
        }
        let login = add(menu, "Launch at Login", action: #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        add(menu, "About Full Sail", action: #selector(about))
        menu.addItem(.separator())
        let quit = add(menu, "Quit Full Sail", action: #selector(quitApp))
        quit.keyEquivalent = "q"
    }
    @objc private func start() { launch(minutes: nil) }
    @objc private func startTimed(_ sender: NSMenuItem) { launch(minutes: sender.tag) }
    private func launch(minutes: Int?) {
        guard setupMonitor.ready else { setup(); return }
        engine.start(minutes: minutes)
    }
    @objc private func stop() { engine.stop() }
    @objc private func restore() {
        let alert = NSAlert()
        alert.messageText = "Restore normal sleep?"
        alert.informativeText = "This clears the Mac’s sleep override. Stop any other keep-awake sessions first."
        alert.addButton(withTitle: "Restore Sleep"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { engine.restore() }
    }
    @objc private func setup() {
        guard !engine.isRunning else { return }
        let alert = NSAlert()
        alert.messageText = "One-time setup for Full Sail"
        alert.informativeText = "1. Open the installer below.\n2. Follow its steps and approve the Mac administrator prompt.\n3. Return to the sail icon and choose Raise Sails (turn on).\n\nFull Sail checks automatically every few seconds and detects when setup is finished.\n\nSetup allows four specific sleep and temperature commands without further password prompts for administrator accounts, and restores normal sleep at boot."
        if EngineController.python == nil {
            alert.informativeText += "\n\nPython 3 is also missing. Install Python 3 so Full Sail can run."
        }
        alert.addButton(withTitle: "Open Installer"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let package = Bundle.main.url(forResource: "FullSailSupport", withExtension: "pkg") {
            if !NSWorkspace.shared.open(package) {
                showError("Couldn’t open the installer", "Try opening Full Sail again, then choose Set Up Full Sail.")
            }
        }
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { showError("Couldn’t change launch at login", error.localizedDescription) }
        refresh()
    }
    @objc private func about() {
        let alert = NSAlert()
        alert.icon = SailIcon.image(raised: true, size: 128, template: false)
        alert.messageText = "Full Sail"
        alert.informativeText = "Keep your Mac running so your agents can keep working in the background, even while the screen is locked.\n\nRaise Sails (turn on) to keep the Mac awake, including with the lid closed. Lower Sails (turn off) to return to normal sleep.\n\nUse Lock Screen when you step away; your agents can keep working behind the lock screen. Full Sail preserves your Mac’s lock settings. Automatic locking still depends on those settings.\n\nBased on Chris Pennello’s chris-cafe, with timed sessions and its original temperature safeguard. Sail icon inspired by Wholesail.\nVersion 0.1.1"
        alert.addButton(withTitle: "Done"); alert.addButton(withTitle: "View Source")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/milesskorpen/chris-cafe/tree/full-sail-menubar")!)
        }
    }
    private func showError(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    private func showCleanupError() {
        showError("Sleep needs attention", "Full Sail couldn’t confirm normal sleep was restored. Use Restore Normal Sleep in the menu. If that fails, run: sudo /usr/bin/pmset -a disablesleep 0")
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if engine.isRunning {
            quitting = true; engine.stop(); return .terminateLater
        }
        if engine.session.state == .uncertain { showCleanupError(); return .terminateCancel }
        return .terminateNow
    }
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--export-assets" {
    try SailIcon.export(to: URL(fileURLWithPath: CommandLine.arguments[2]))
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
