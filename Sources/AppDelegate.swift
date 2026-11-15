import AppKit
import IOKit.pwr_mgt
import ServiceManagement
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    /// True while the system's SleepDisabled flag is set (as far as we know).
    private var active = false
    /// True while a privileged pmset call is in flight.
    private var busy = false
    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var offTimer: Timer?
    private var offDate: Date?
    private var batteryTimer: Timer?
    private var battery: BatteryInfo?
    private var signalSources: [DispatchSourceSignal] = []
    private var skipRestoreOnTerminate = false

    private let thresholdKey = "batteryThreshold"
    private var threshold: Int { UserDefaults.standard.integer(forKey: thresholdKey) }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [thresholdKey: 20])
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        syncWithSystem() // adopts a leftover SleepDisabled=1 (e.g. after a crash)
        battery = Battery.read()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.batteryTick() }
        }
        installSignalHandlers()
        refreshIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Synchronous restore: never leave the Mac unable to sleep behind us.
        if (active || busy) && !skipRestoreOnTerminate && PowerControl.isSleepDisabled() != false {
            _ = PowerControl.setSleepDisabled(false)
        }
        releaseAssertion()
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - State

    /// Reconciles our state with the real `pmset -g` SleepDisabled value.
    private func syncWithSystem() {
        guard !busy, let disabled = PowerControl.isSleepDisabled(), disabled != active else { return }
        active = disabled
        if disabled {
            takeAssertion()
        } else {
            releaseAssertion()
            cancelOffTimer()
        }
        refreshIcon()
    }

    private func enable(for duration: TimeInterval?) {
        if active { scheduleOff(duration); return } // just retime
        guard !busy else { return }
        if let b = Battery.read(), b.onBattery, threshold > 0, b.percent < threshold {
            showAlert("Battery is below \(threshold)%",
                      "Plug in or lower the auto-disable threshold before keeping the Mac awake.")
            return
        }
        busy = true
        Task.detached {
            let result = PowerControl.setSleepDisabled(true)
            await self.finishEnable(result, duration)
        }
    }

    private func finishEnable(_ result: PrivResult, _ duration: TimeInterval?) {
        busy = false
        switch result {
        case .ok:
            active = true
            takeAssertion()
            scheduleOff(duration)
        case .cancelled:
            break
        case .failed(let msg):
            showAlert("Couldn't disable sleep", msg)
        }
        refreshIcon()
    }

    /// Restores normal sleep. `notice` (if any) is posted as a user notification on success.
    private func disable(notice: String? = nil) {
        guard active, !busy else { return }
        busy = true
        Task.detached {
            let result = PowerControl.setSleepDisabled(false)
            await self.finishDisable(result, notice)
        }
    }

    private func finishDisable(_ result: PrivResult, _ notice: String?) {
        busy = false
        switch result {
        case .ok:
            active = false
            releaseAssertion()
            cancelOffTimer()
            if let notice { notify(notice) }
        case .cancelled:
            break
        case .failed(let msg):
            if notice != nil { notify("Couldn't restore normal sleep: \(msg)") }
            else { showAlert("Couldn't restore normal sleep", msg) }
        }
        refreshIcon()
    }

    private func scheduleOff(_ duration: TimeInterval?) {
        cancelOffTimer()
        guard let duration else { return }
        offDate = Date().addingTimeInterval(duration)
        offTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.disable() }
        }
    }

    private func cancelOffTimer() {
        offTimer?.invalidate()
        offTimer = nil
        offDate = nil
    }

    private func batteryTick() {
        battery = Battery.read()
        if active, !busy, threshold > 0, let b = battery, b.onBattery, b.percent < threshold {
            disable(notice: "Battery at \(b.percent)% — LidAwake restored normal sleep.")
        }
        refreshIcon()
    }

    // MARK: - Idle-sleep assertion

    private func takeAssertion() {
        guard !hasAssertion else { return }
        let ok = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "LidAwake keeping Mac awake" as CFString,
            &assertionID)
        hasAssertion = (ok == kIOReturnSuccess)
    }

    private func releaseAssertion() {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertionID)
        hasAssertion = false
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        syncWithSystem()
        battery = Battery.read()
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = item("Keep Awake (lid closed)", #selector(toggleAwake))
        toggle.state = active ? .on : .off
        toggle.isEnabled = !busy
        menu.addItem(toggle)

        let forMenu = NSMenu()
        for hours in [1, 2, 4, 8] {
            forMenu.addItem(item("\(hours) h", #selector(keepAwakeFor(_:)), hours))
        }
        forMenu.addItem(item("Indefinitely", #selector(keepAwakeFor(_:)), 0))
        forMenu.items.forEach { $0.isEnabled = !busy }
        let forItem = NSMenuItem(title: "Keep awake for…", action: nil, keyEquivalent: "")
        forItem.submenu = forMenu
        menu.addItem(forItem)

        let batMenu = NSMenu()
        for pct in [0, 10, 20, 30] {
            let i = item(pct == 0 ? "Off" : "\(pct)%", #selector(setThreshold(_:)), pct)
            i.state = threshold == pct ? .on : .off
            batMenu.addItem(i)
        }
        let batItem = NSMenuItem(title: "Auto-disable on battery below", action: nil, keyEquivalent: "")
        batItem.submenu = batMenu
        menu.addItem(batItem)

        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = item("Quit LidAwake", #selector(quitApp))
        quit.keyEquivalent = "q"
        quit.isEnabled = !busy
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, _ tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.tag = tag
        return i
    }

    private func statusText() -> String {
        var s = busy ? "Working…" : (active ? "Awake — lid close won't sleep" : "Sleep: normal")
        if active, let offDate {
            let mins = max(0, Int(offDate.timeIntervalSinceNow / 60))
            s += " (\(mins / 60)h \(mins % 60)m left)"
        }
        if let b = battery {
            s += " · Battery \(b.percent)%" + (b.onBattery ? "" : " (AC)")
        }
        return s
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let name = active ? "sun.max.fill" : "moon.zzz"
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: "LidAwake") {
            img.isTemplate = true
            button.image = img
            button.title = ""
        } else {
            button.image = nil
            button.title = active ? "☀︎" : "☾"
        }
        button.toolTip = active ? "LidAwake: keeping Mac awake" : "LidAwake: sleep is normal"
    }

    // MARK: - Actions

    @objc private func toggleAwake() {
        if active { disable() } else { enable(for: nil) }
    }

    @objc private func keepAwakeFor(_ sender: NSMenuItem) {
        enable(for: sender.tag > 0 ? TimeInterval(sender.tag * 3600) : nil)
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: thresholdKey)
        batteryTick()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            showAlert("Couldn't change Launch at Login",
                      "\(error.localizedDescription)\n\nThis only works when LidAwake runs from an app bundle, ideally copied to /Applications.")
            return
        }
        if service.status == .requiresApproval {
            showAlert("Approval needed", "Allow LidAwake under System Settings › General › Login Items.")
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func quitApp() {
        guard active else { NSApp.terminate(nil); return }
        guard !busy else { return }
        busy = true
        Task.detached {
            let result = PowerControl.setSleepDisabled(false)
            await self.finishQuit(result)
        }
    }

    private func finishQuit(_ result: PrivResult) {
        busy = false
        if case .ok = result {
            active = false
            releaseAssertion()
            NSApp.terminate(nil)
            return
        }
        activate()
        let alert = NSAlert()
        alert.messageText = "Normal sleep was not restored"
        alert.informativeText = "If you quit now, your Mac will stay unable to sleep. You can restore it later with:\n\nsudo pmset -a disablesleep 0"
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Anyway")
        if alert.runModal() == .alertSecondButtonReturn {
            skipRestoreOnTerminate = true
            NSApp.terminate(nil)
        }
    }

    // MARK: - UI helpers

    private func activate() {
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }

    private func showAlert(_ title: String, _ text: String) {
        activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    private func notify(_ body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return } // UN center needs a bundle
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "LidAwake"
            content.body = body
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
