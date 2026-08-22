//
//  AppDelegate.swift
//  Tickbyte
//
//  Created by Luke Mao on 5/2/2025.
//

import Cocoa
import SwiftUI
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    private let webSocketManager = WebSocketManager()
    private let logger = Logger(subsystem: AppConfiguration.Logging.subsystem, category: "AppDelegate")

    private lazy var panelController = TickerPanelController(symbols: webSocketManager.availableSymbols)
    private var statusBarTimer: Timer?
    private var lastStatusTitle: StatusBarText.Title?
    private var lastPanelFetch: Date?
    /// Which coin occupies the panel's hero slot — and, by the same token, the menu bar.
    /// Persisted: it is the one preference the user expresses, so it must survive a
    /// relaunch. Loaded through the `SymbolCatalog` whitelist like every stored symbol.
    private var focusedSymbol: String {
        didSet {
            UserDefaults.standard.set(focusedSymbol, forKey: AppConfiguration.UserDefaultsKeys.focusedSymbol)
        }
    }

    override init() {
        let stored = UserDefaults.standard.string(forKey: AppConfiguration.UserDefaultsKeys.focusedSymbol)
        focusedSymbol = SymbolCatalog.validSymbols(from: [stored].compactMap { $0 }).first
            ?? SymbolCatalog.supported[0]
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application launching...")
        setupMainMenu()
        setupStatusBarItem()
        setupPanel()
        setupObservers()
        startPriceUpdates()
        logger.info("Application launched successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Application terminating...")
        statusBarTimer?.invalidate()
        webSocketManager.disconnectWebSockets()
    }

    /// Menu-bar-only apps still need a main menu for standard keyboard command routing.
    /// The menu is not shown in the custom panel, but gives AppKit a native ⌘Q command.
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        mainMenu.addItem(applicationItem)

        let applicationMenu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit Tickbyte",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu

        NSApplication.shared.mainMenu = mainMenu
    }

    private func setupStatusBarItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusBarItem.button else {
            logger.error("Failed to create status bar button")
            return
        }

        button.attributedTitle = attributedStatusTitle(StatusBarText.make(items: []))
        // A two-state status button retains AppKit's native illuminated pill while the
        // custom panel is open. A momentary button clears its highlight on mouse-up.
        button.setButtonType(.pushOnPushOff)
        button.state = .off
        button.action = #selector(statusBarButtonClicked)
        button.target = self
        // Act on press, the way a menu does. On mouse *up* the app's first click while it
        // is inactive is swallowed by activation, so the panel would need two clicks to
        // open — which is what `NSStatusItem.menu` used to hide from us.
        button.sendAction(on: [.leftMouseDown])

        logger.info("Status bar item created")
    }

    private func setupPanel() {
        panelController.contentView.delegate = self
        panelController.onOpen = { [weak self] in self?.panelWillOpen() }
        panelController.onClose = { [weak self] in self?.webSocketManager.isPanelVisible = false }
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange(_:)),
            name: .priceUpdated,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange(_:)),
            name: .connectionStateChanged,
            object: nil
        )
    }

    // MARK: - Status bar

    private func startPriceUpdates() {
        statusBarTimer = Timer.scheduledTimer(withTimeInterval: AppConfiguration.UI.statusBarUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusBarTitle()
            }
        }
    }

    private func updateStatusBarTitle() {
        guard let button = statusBarItem.button else { return }

        let title = createStatusBarTitle()
        // F9: only touch the UI when something actually changed. Colour is part of the
        // title here, so the comparison covers the ranges too.
        guard title != lastStatusTitle else { return }
        lastStatusTitle = title
        button.attributedTitle = attributedStatusTitle(title)
    }

    /// The menu bar shows one coin: the panel's hero. Two equal-weight prices side by
    /// side were two primaries competing, and too wide for a crowded bar. Picking the
    /// coin through `PanelBoard` — the same function the panel uses — means the bar and
    /// the hero slot can never disagree.
    private func createStatusBarTitle() -> StatusBarText.Title {
        let board = PanelBoard.arrange(focused: focusedSymbol, symbols: webSocketManager.selectedSymbols)
        guard let symbol = board.hero, let price = webSocketManager.prices[symbol] else {
            return StatusBarText.make(items: [])
        }
        let isStale: Bool
        switch webSocketManager.connectionStates[symbol] {
        case .disconnected, .error: isStale = true
        case .connecting, .connected, .none: isStale = false
        }
        let item = StatusBarText.Item(
            code: SymbolCatalog.displayCode(for: symbol),
            price: price,
            isStale: isStale
        )
        return StatusBarText.make(items: [item])
    }

    /// One size and one opaque ink for code and price (`NothingTheme.MenuBar` explains
    /// why the bar gets no secondary grey); a failed item dims as a whole.
    private func attributedStatusTitle(_ title: StatusBarText.Title) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title.text,
            attributes: [
                .font: NothingTheme.data(size: NothingTheme.TypeSize.menuBar),
                .foregroundColor: NothingTheme.MenuBar.ink,
            ]
        )
        for range in title.staleRanges {
            result.addAttribute(
                .foregroundColor,
                value: NothingTheme.MenuBar.stale,
                range: range
            )
        }
        return result
    }

    // MARK: - Panel

    private func panelWillOpen() {
        webSocketManager.isPanelVisible = true
        refreshPanel()

        let now = Date()
        if let last = lastPanelFetch, now.timeIntervalSince(last) < AppConfiguration.UI.panelFetchDebounce { return }
        lastPanelFetch = now
        Task { @MainActor in
            await webSocketManager.fetchAllPrices()
            refreshPanel()
        }
    }

    private func refreshPanel() {
        panelController.contentView.update(with: makeSnapshot())
    }

    private func makeSnapshot() -> PanelSnapshot {
        let symbols = webSocketManager.availableSymbols
        return PanelSnapshot(
            focusedSymbol: focusedSymbol,
            feedStatus: PanelText.feedStatus(
                states: symbols.map { webSocketManager.connectionStates[$0] }
            ),
            coins: symbols.map(coin(for:))
        )
    }

    private func coin(for symbol: String) -> PanelSnapshot.Coin {
        let dayChart: PanelSnapshot.DayChart
        if let points = webSocketManager.dayChartPoints[symbol] {
            dayChart = .points(points.map(\.close))
        } else if webSocketManager.unavailableDayCharts.contains(symbol) {
            dayChart = .unavailable
        } else {
            dayChart = .loading
        }

        return PanelSnapshot.Coin(
            symbol: symbol,
            pair: PanelText.pair(for: symbol),
            price: webSocketManager.prices[symbol] ?? PriceFormatter.placeholder,
            change: PanelText.change(fromRaw: webSocketManager.priceChanges[symbol] ?? ""),
            dayChart: dayChart
        )
    }

    // MARK: - Events

    @objc private func statusBarButtonClicked() {
        guard let button = statusBarItem.button else { return }
        panelController.toggle(relativeTo: button)
    }

    /// Live data changed. Only the open panel needs refreshing; when it is closed the 1 Hz
    /// status-bar timer already covers the visible UI, so we do nothing (F6).
    @objc private func dataDidChange(_ notification: Notification) {
        guard webSocketManager.isPanelVisible else { return }
        refreshPanel()
    }
}

extension AppDelegate: TickerPanelViewDelegate {
    func panelViewDidRequestQuit(_ view: TickerPanelView) {
        logger.info("Quit requested")
        statusBarTimer?.invalidate()
        webSocketManager.disconnectWebSockets()
        NSApplication.shared.terminate(nil)
    }

    func panelView(_ view: TickerPanelView, didFocus symbol: String) {
        guard SymbolCatalog.supported.contains(symbol), symbol != focusedSymbol else { return }
        focusedSymbol = symbol
        refreshPanel()
        // The bar follows the hero; don't make the user wait for the next 1 Hz tick.
        updateStatusBarTitle()
    }
}
