import AppKit
import ServiceManagement
import SailCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let engine = EngineController()
    private var item: NSStatusItem!
    private var ready = false
    private var checking = false
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        engine.changed = { [weak self] in self?.refresh() }
        engine.finished = { [weak self] in
            guard let self, self.quitting else { return }
            self.quitting = false
            NSApp.reply(toApplicationShouldTerminate: self.engine.session.state != .uncertain)
            if self.engine.session.state == .uncertain { self.showCleanupError() }
        }
        refresh()
        checkSetup()
    }
    func menuWillOpen(_ menu: NSMenu) { refreshMenu(menu) }
    private func refresh() {
        guard item != nil else { return }
        let state = engine.session.state
        if state == .uncertain {
            item.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Sleep needs attention")
        } else {
            item.button?.image = SailIcon.image(raised: state == .on || state == .stopping)
        }
        item.button?.appearsDisabled = state == .starting || state == .stopping
        item.button?.toolTip = "Full Sail — \(state == .on ? "Sails up" : state == .off ? "Sails down" : "\(state)")"
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
        add(menu, state == .on ? "Sails up · Mac stays awake" : state == .off ? "Sails down · Normal sleep" : engine.session.detail)
        if state == .on {
            add(menu, engine.remaining ?? "Until you lower the sails")
            add(menu, engine.session.guardDetail)
        } else if !engine.session.detail.hasPrefix("Your Mac") { add(menu, engine.session.detail) }
        menu.addItem(.separator())
        if state == .uncertain {
            add(menu, "Restore Normal Sleep…", action: #selector(restore))
        } else if engine.isRunning {
            add(menu, state == .stopping ? "Lowering Sails…" : "Lower Sails", action: #selector(stop), enabled: state != .stopping)
        } else {
            add(menu, "Raise Sails", action: #selector(start))
            let duration = NSMenu()
            for minutes in [15, 30, 60, 120, 240] {
                let row = add(duration, minutes < 60 ? "For \(minutes) Minutes" : "For \(minutes / 60) Hour\(minutes == 60 ? "" : "s")", action: #selector(startTimed(_:)))
                row.tag = minutes
            }
            let durationItem = add(menu, "Keep Awake For…")
            durationItem.isEnabled = true; durationItem.submenu = duration
        }
        menu.addItem(.separator())
        if !ready {
            add(menu, checking ? "Checking Setup…" : "Set Up Closed-Lid Support…", action: #selector(setup), enabled: !checking && !engine.isRunning)
            add(menu, "Recheck Setup", action: #selector(checkSetup), enabled: !checking && !engine.isRunning)
        }
        let login = add(menu, "Launch at Login", action: #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        add(menu, "About Full Sail", action: #selector(about))
        menu.addItem(.separator())
        let quit = add(menu, "Quit Full Sail", action: #selector(quitApp))
        quit.keyEquivalent = "q"
    }
    @objc private func checkSetup() {
        guard !checking else { return }
        checking = true; refresh()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = EngineController.supportReady()
            DispatchQueue.main.async { self?.ready = result; self?.checking = false; self?.refresh() }
        }
    }
    @objc private func start() { launch(minutes: nil) }
    @objc private func startTimed(_ sender: NSMenuItem) { launch(minutes: sender.tag) }
    private func launch(minutes: Int?) {
        guard ready else { setup(); return }
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
        alert.messageText = "Give Full Sail a little wind"
        alert.informativeText = "One-time setup lets Full Sail keep your Mac awake with the lid closed and monitor temperature. The installer asks for your administrator password.\n\nIt permits four specific power-management commands for admin users without a password, and installs a boot-time reset for normal sleep.\n\nAfter installing, choose Recheck Setup. Python 3 is also required; this Mac will use \(EngineController.python?.path ?? "an installed Python 3")."
        alert.addButton(withTitle: "Open Setup Installer"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let package = Bundle.main.url(forResource: "FullSailSupport", withExtension: "pkg") {
            NSWorkspace.shared.open(package)
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
        alert.informativeText = "Sails up. Mac awake.\n\nA small menu bar companion for chris-cafe, with timed sessions and the original temperature safeguard.\n\nBased on Chris Pennello’s chris-cafe. Icon inspired by Wholesail.\nVersion 0.1.0"
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
