import Cocoa
import SwiftUI
import Combine

// MARK: - Menu Bar Manager

@MainActor
final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let statusMenu = NSMenu()
    private var monitor: Any?
    private var autoCloseTimer: Timer?
    private var hoverStateTimer: Timer?
    private var isMouseInsidePanel = false
    private var isMouseInsideDetailPanel = false
    private var panelDragMonitor: Any?
    private var panelDragStartLocation: NSPoint?
    private var panelDragWindowOrigin: NSPoint?
    private var panelDragDidMove = false
    private var isDragging = false
    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []

    let viewModel = DashboardViewModel()

    private lazy var settingsWindowController: SettingsWindowController = {
        SettingsWindowController(viewModel: viewModel)
    }()

    private lazy var modelDetailWindowController: ModelDetailWindowController = {
        ModelDetailWindowController(viewModel: viewModel)
    }()

    // MARK: - Init

    override init() {
        super.init()
        setupStatusItem()
        setupPanel()
        observeViewModel()
        observeUsageExportDownloads()
        startAutoRefresh()
        UsageExportAutomationService.shared.start()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }

        updateStatusBarButton(button)
        button.action = #selector(togglePanel)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        configureStatusMenu()
    }

    private func configureStatusMenu() {
        statusMenu.autoenablesItems = false
        statusMenu.removeAllItems()

        addStatusMenuItem(title: "刷新", action: #selector(manualRefresh), keyEquivalent: "r")
        statusMenu.addItem(.separator())
        addStatusMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ",")
        statusMenu.addItem(.separator())
        addStatusMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
    }

    private func addStatusMenuItem(title: String, action: Selector, keyEquivalent: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = true
        statusMenu.addItem(item)
    }

    // MARK: - Panel

    private func setupPanel() {
        let hostingController = NSHostingController(
            rootView: ContentView(
                viewModel: viewModel,
                onOpenSettings: { [weak self] in self?.openSettings() },
                onOpenModelDetail: { [weak self] model in self?.openModelDetail(model) },
                onClose: { [weak self] in self?.closePanel() }
            )
        )

        panel = FloatingPanel(
            contentViewController: hostingController,
            contentSize: NSSize(width: Theme.panelWidth, height: Theme.panelHeight)
        )
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }

        if NSApp.currentEvent?.type == .rightMouseUp ||
            NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showStatusMenu(button: button)
            return
        }

        if panel.isVisible {
            closePanel()
        } else {
            showPanel(button: button)
        }
    }

    private func showStatusMenu(button: NSStatusBarButton) {
        closePanel()
        statusItem.menu = statusMenu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func showPanel(button: NSStatusBarButton) {
        if let screen = button.window?.screen ?? NSScreen.main {
            let buttonRect = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero

            var origin = NSPoint(
                x: buttonRect.midX - panel.frame.width / 2,
                y: buttonRect.minY - panel.frame.height - Theme.panelTopGap
            )

            if origin.x < screen.visibleFrame.minX + 4 {
                origin.x = screen.visibleFrame.minX + 4
            }
            if origin.x + panel.frame.width > screen.visibleFrame.maxX - 4 {
                origin.x = screen.visibleFrame.maxX - panel.frame.width - 4
            }

            panel.setFrameOrigin(origin)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        panel.isDetached = false
        panel.level = .statusBar

        startHoverStateMonitoring()
        refreshHoverState()
        schedulePanelAutoClose()
        startPanelDragMonitoring()

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        hoverStateTimer?.invalidate()
        hoverStateTimer = nil
        isMouseInsidePanel = false
        isMouseInsideDetailPanel = false
        modelDetailWindowController.close()
        panel.orderOut(nil)
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let dragMonitor = panelDragMonitor {
            NSEvent.removeMonitor(dragMonitor)
            panelDragMonitor = nil
        }
        panelDragStartLocation = nil
        panelDragWindowOrigin = nil
        panelDragDidMove = false
        isDragging = false
    }

    private func schedulePanelAutoClose() {
        autoCloseTimer?.invalidate()
        guard panel.isVisible, !panel.isDetached, shouldPausePanelAutoClose == false else { return }
        let duration = max(1, viewModel.panelResidenceSeconds)
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePanel()
            }
        }
    }

    private func startHoverStateMonitoring() {
        hoverStateTimer?.invalidate()
        guard !panel.isDetached else { return }
        hoverStateTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshHoverState()
            }
        }
    }

    private func startPanelDragMonitoring() {
        if let existing = panelDragMonitor {
            NSEvent.removeMonitor(existing)
        }
        panelDragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self, panel.isVisible else { return event }

            switch event.type {
            case .leftMouseDown:
                guard event.window === panel else { return event }
                isDragging = true
                panelDragStartLocation = NSEvent.mouseLocation
                panelDragWindowOrigin = panel.frame.origin
                panelDragDidMove = false

            case .leftMouseDragged:
                guard isDragging,
                      let start = panelDragStartLocation,
                      let winOrigin = panelDragWindowOrigin else { return event }

                let current = NSEvent.mouseLocation
                let dx = current.x - start.x
                let dy = current.y - start.y

                if !panelDragDidMove {
                    guard abs(dx) > Theme.detachDragThreshold else { return event }
                }

                if !panelDragDidMove {
                    panelDragDidMove = true
                    if !panel.isDetached { detachPanel() }
                }

                panel.setFrameOrigin(NSPoint(
                    x: winOrigin.x + dx,
                    y: winOrigin.y + dy
                ))

            case .leftMouseUp:
                isDragging = false
                panelDragStartLocation = nil
                panelDragWindowOrigin = nil
                panelDragDidMove = false

            default:
                break
            }

            return event
        }
    }

    private func detachPanel() {
        guard !panel.isDetached else { return }
        panel.isDetached = true

        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        hoverStateTimer?.invalidate()
        hoverStateTimer = nil
        isMouseInsidePanel = false
        isMouseInsideDetailPanel = false

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        modelDetailWindowController.close()
        panel.level = .floating
    }

    private var shouldPausePanelAutoClose: Bool {
        isMouseInsidePanel || isMouseInsideDetailPanel
    }

    private func refreshHoverState() {
        guard panel.isVisible else { return }

        let mouseLocation = NSEvent.mouseLocation
        let wasPaused = shouldPausePanelAutoClose

        isMouseInsidePanel = panel.frame.contains(mouseLocation)
        if let detailFrame = modelDetailWindowController.visibleFrame {
            isMouseInsideDetailPanel = detailFrame.contains(mouseLocation)
        } else {
            isMouseInsideDetailPanel = false
        }

        let isPaused = shouldPausePanelAutoClose
        if isPaused {
            autoCloseTimer?.invalidate()
            autoCloseTimer = nil
        } else if wasPaused != isPaused || autoCloseTimer == nil {
            schedulePanelAutoClose()
        }
    }

    // MARK: - ViewModel

    private func observeViewModel() {
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshStatusBarText()
            }
            .store(in: &cancellables)
    }

    private func refreshStatusBarText() {
        guard let button = statusItem.button else { return }
        updateStatusBarButton(button)
    }

    private func observeUsageExportDownloads() {
        let observer = NotificationCenter.default.addObserver(
            forName: .usageExportDownloadFinished,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.viewModel.autoImportUsageIfNeeded()
            }
        }
        notificationObservers.append(observer)
    }

    private lazy var menuBarIcon: NSImage? = {
        if let url = Bundle.main.url(forResource: "deepseek-menu", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = false
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        if let url = Bundle.main.url(forResource: "deepseek-color", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return nil
    }()

    private func updateStatusBarButton(_ button: NSStatusBarButton) {
        button.image = menuBarIcon
        button.title = ""
        button.imagePosition = .imageOnly
    }

    func startAutoRefresh() { viewModel.startAutoRefresh() }
    func stopAutoRefresh() { viewModel.stopAutoRefresh() }

    @objc private func manualRefresh() { Task { await viewModel.refresh() } }
    @objc private func openSettings() { settingsWindowController.show(anchorTo: panel.isVisible ? panel : nil) }
    private func openModelDetail(_ model: DeepSeekModel) {
        guard panel.isVisible else { return }
        modelDetailWindowController.show(for: model, anchoredTo: panel)
    }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }

    func cleanup() {
        stopAutoRefresh()
        UsageExportAutomationService.shared.stop()
        UsageExportAutomationService.shared.closeWindow()
        closePanel()
        modelDetailWindowController.close()
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        if let button = statusItem.button {
            button.action = nil
            button.target = nil
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

// MARK: - Floating Panel

private final class FloatingPanel: NSWindow {
    init(contentViewController: NSViewController, contentSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.contentViewController = contentViewController
        self.setContentSize(contentSize)
        self.contentViewController?.view.wantsLayer = true
        self.contentViewController?.view.layer?.cornerRadius = Theme.panelCornerRadius
        self.contentViewController?.view.layer?.masksToBounds = true
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = Theme.panelCornerRadius
        self.contentView?.layer?.masksToBounds = true
        self.contentView?.superview?.wantsLayer = true
        self.contentView?.superview?.layer?.cornerRadius = Theme.panelCornerRadius

        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.hidesOnDeactivate = false
    }

    var isDetached = false
}
