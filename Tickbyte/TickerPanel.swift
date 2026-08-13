//
//  TickerPanel.swift
//  Tickbyte
//
//  The dropdown. A borderless panel rather than an `NSMenu` or an `NSPopover`: both of
//  those impose a system material, a shadow and a fixed row shape, and the design calls
//  for a flat surface with one hairline border and no shadow at all.
//
//  Like the menu it replaces, the panel renders state handed to it and owns none — every
//  view is built once and refreshed in place.
//

import AppKit
import QuartzCore

/// Everything the panel needs to draw itself, already resolved by the caller.
struct PanelSnapshot {
    enum DayChart {
        case loading
        case unavailable
        case points([Double])
    }

    struct Coin {
        let symbol: String
        let pair: String
        let price: String
        let change: PanelText.Change
        let dayChart: DayChart
    }

    /// The focused coin sits in the hero slot; the rest become compact rows.
    let focusedSymbol: String
    let feedStatus: PanelText.Status
    let coins: [Coin]
}

extension PanelText.Status {
    var color: NSColor {
        switch self {
        case .live: return NothingTheme.Palette.successOnPaper
        case .sync: return NothingTheme.Palette.warning
        case .lost: return NothingTheme.Palette.accent
        }
    }
}

extension PanelText.ColorRole {
    var color: NSColor {
        switch self {
        case .success: return NothingTheme.Palette.successOnPaper
        case .accent: return NothingTheme.Palette.accent
        case .disabled: return NothingTheme.Palette.textDisabled
        }
    }
}

@MainActor
protocol TickerPanelViewDelegate: AnyObject {
    func panelViewDidRequestQuit(_ view: TickerPanelView)
    func panelView(_ view: TickerPanelView, didFocus symbol: String)
}

// MARK: - Hero

/// The one primary on the board: Doto price and a UTC-day sparkline.
/// Quote and window stay off the number — `BTC/USDT` already names the pair.
final class HeroCoinView: NSView {
    private let pairLabel: NothingLabel
    private let changeLabel: NothingLabel
    private let priceLabel: NothingLabel
    private let dayChartView: DayChartView

    init() {
        pairLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textSecondary,
            tracking: NothingTheme.labelTracking
        )
        changeLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.value),
            color: NothingTheme.Palette.textDisabled,
            alignment: .right
        )
        priceLabel = NothingLabel(
            font: NothingTheme.display(size: NothingTheme.TypeSize.hero),
            color: NothingTheme.Palette.textDisplay,
            tracking: NothingTheme.displayTracking
        )
        dayChartView = DayChartView()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        changeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        priceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [pairLabel, changeLabel, priceLabel, dayChartView] {
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            pairLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            pairLabel.topAnchor.constraint(equalTo: topAnchor),

            changeLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            changeLabel.firstBaselineAnchor.constraint(equalTo: pairLabel.firstBaselineAnchor),
            changeLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: pairLabel.trailingAnchor,
                constant: NothingTheme.Metric.sm
            ),

            priceLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            priceLabel.topAnchor.constraint(
                equalTo: pairLabel.bottomAnchor,
                constant: NothingTheme.Metric.sm
            ),
            priceLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            dayChartView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dayChartView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dayChartView.topAnchor.constraint(
                equalTo: priceLabel.bottomAnchor,
                constant: NothingTheme.Metric.md
            ),
            dayChartView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(with coin: PanelSnapshot.Coin) {
        pairLabel.text = coin.pair
        changeLabel.text = coin.change.text
        changeLabel.textColor = PanelText.changeColorRole(coin.change.direction).color
        flashPrice(ifChangedTo: coin.price)
        dayChartView.state = coin.dayChart
    }

    /// A short ease-out fade-in when the print moves — click, not swoosh.
    private func flashPrice(ifChangedTo newPrice: String) {
        let previous = priceLabel.text
        priceLabel.text = newPrice
        guard !previous.isEmpty, previous != newPrice else { return }
        priceLabel.alphaValue = 0.35
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NothingTheme.Metric.transition
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
            priceLabel.animator().alphaValue = 1
        }
    }
}

// MARK: - Compact row

/// Secondary coin: one stat row. Click promotes it into the hero slot.
final class CompactCoinView: NSControl {
    private let pairLabel: NothingLabel
    private let priceLabel: NothingLabel
    private let changeLabel: NothingLabel

    private(set) var symbol: String = ""

    init() {
        pairLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textSecondary,
            tracking: NothingTheme.labelTracking
        )
        priceLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.value),
            color: NothingTheme.Palette.textDisplay
        )
        changeLabel = NothingLabel(
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textDisabled,
            alignment: .right
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        focusRingType = .exterior
        setAccessibilityRole(.button)

        changeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        priceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        pairLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [pairLabel, priceLabel, changeLabel] {
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: NothingTheme.Metric.buttonTarget),

            pairLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            pairLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            changeLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            changeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            priceLabel.trailingAnchor.constraint(
                equalTo: changeLabel.leadingAnchor,
                constant: -NothingTheme.Metric.md
            ),
            priceLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            pairLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: priceLabel.leadingAnchor,
                constant: -NothingTheme.Metric.sm
            ),
        ])
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: -2, dy: -2) }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 4, yRadius: 4).fill()
    }

    func update(with coin: PanelSnapshot.Coin) {
        symbol = coin.symbol
        pairLabel.text = coin.pair
        priceLabel.text = coin.price
        changeLabel.text = coin.change.text
        changeLabel.textColor = PanelText.changeColorRole(coin.change.direction).color
        setAccessibilityLabel("Show \(coin.pair)")
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.charactersIgnoringModifiers == " " {
            sendAction(action, to: target)
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        pairLabel.textColor = NothingTheme.Palette.textPrimary
    }

    override func mouseExited(with event: NSEvent) {
        pairLabel.textColor = NothingTheme.Palette.textSecondary
    }
}

// MARK: - Panel content

final class TickerPanelView: NSView {
    private typealias Metric = NothingTheme.Metric

    weak var delegate: TickerPanelViewDelegate?

    private let wordmarkLabel = NothingLabel(
        font: NothingTheme.body(size: NothingTheme.TypeSize.label),
        color: NothingTheme.Palette.textDisabled
    )
    private let statusLabel = NothingLabel(
        font: NothingTheme.data(size: NothingTheme.TypeSize.label),
        color: NothingTheme.Palette.textDisabled,
        tracking: NothingTheme.labelTracking
    )
    private let heroSection = HeroCoinView()
    private var compactRows: [CompactCoinView] = []

    /// - Parameter symbols: every supported coin, in a fixed order. One hero and
    ///   `count - 1` compact rows are built once — the panel is never rebuilt.
    init(symbols: [String]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = NothingTheme.Metric.cornerRadius
        layer?.borderWidth = NothingTheme.Metric.hairline
        applyChrome()

        buildLayout(symbols: symbols)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() { applyChrome() }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    private func applyChrome() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NothingTheme.Palette.panel.cgColor
            layer?.borderColor = NothingTheme.Palette.borderVisible.cgColor
        }
    }

    // MARK: Layout

    private func buildLayout(symbols: [String]) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Metric.panelWidth),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metric.padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metric.padding),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Metric.padding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metric.padding),
        ])

        addFullWidth(heroSection, to: stack)
        stack.setCustomSpacing(Metric.sectionGap, after: heroSection)

        compactRows = (0..<max(symbols.count - 1, 0)).map { _ in
            let row = CompactCoinView()
            row.target = self
            row.action = #selector(compactClicked(_:))
            addFullWidth(row, to: stack)
            stack.setCustomSpacing(Metric.md, after: row)
            return row
        }
        if let lastRow = compactRows.last {
            stack.setCustomSpacing(Metric.xl, after: lastRow)
        } else {
            stack.setCustomSpacing(Metric.xl, after: heroSection)
        }

        let quit = NothingTextButton(
            text: "[ QUIT ]",
            font: NothingTheme.data(size: NothingTheme.TypeSize.label),
            color: NothingTheme.Palette.textSecondary,
            activeColor: NothingTheme.Palette.textPrimary,
            tracking: NothingTheme.labelTracking
        )
        quit.target = self
        quit.action = #selector(quitClicked)
        quit.heightAnchor.constraint(greaterThanOrEqualToConstant: Metric.buttonTarget).isActive = true
        addFullWidth(makeFooterRow(quit: quit), to: stack)
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    /// Wordmark, exceptional feed state, and the app action share one quiet footer.
    private func makeFooterRow(quit: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        wordmarkLabel.text = PanelText.wordmark
        container.addSubview(wordmarkLabel)
        container.addSubview(statusLabel)
        container.addSubview(quit)
        NSLayoutConstraint.activate([
            wordmarkLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wordmarkLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            statusLabel.leadingAnchor.constraint(
                equalTo: wordmarkLabel.trailingAnchor,
                constant: Metric.md
            ),
            statusLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            quit.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            quit.leadingAnchor.constraint(
                greaterThanOrEqualTo: statusLabel.trailingAnchor,
                constant: Metric.sm
            ),
            quit.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: quit.heightAnchor),
        ])
        return container
    }

    // MARK: Refresh

    func update(with snapshot: PanelSnapshot) {
        let statusText = snapshot.feedStatus.footerText
        statusLabel.text = statusText ?? ""
        statusLabel.isHidden = statusText == nil
        if statusText != nil {
            statusLabel.textColor = snapshot.feedStatus.color
        }

        let symbols = snapshot.coins.map(\.symbol)
        let board = PanelBoard.arrange(focused: snapshot.focusedSymbol, symbols: symbols)
        let bySymbol = Dictionary(uniqueKeysWithValues: snapshot.coins.map { ($0.symbol, $0) })

        if let heroSymbol = board.hero, let coin = bySymbol[heroSymbol] {
            heroSection.update(with: coin)
            heroSection.isHidden = false
        } else {
            heroSection.isHidden = true
        }

        for (row, symbol) in zip(compactRows, board.compact) {
            if let coin = bySymbol[symbol] {
                row.update(with: coin)
                row.isHidden = false
            }
        }
        for row in compactRows.dropFirst(board.compact.count) {
            row.isHidden = true
        }
    }

    // MARK: Actions

    @objc private func quitClicked() {
        delegate?.panelViewDidRequestQuit(self)
    }

    @objc private func compactClicked(_ sender: CompactCoinView) {
        guard !sender.symbol.isEmpty else { return }
        delegate?.panelView(self, didFocus: sender.symbol)
    }
}

// MARK: - Panel window

/// A borderless, shadowless window anchored under the status item. `NSPanel` (rather than
/// `NSWindow`) so it can take key input for Escape without activating the app.
final class TickerPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentView = contentView
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false
        // Clicking the menu bar deactivates the app, so `hidesOnDeactivate` would close
        // the panel a moment before the status item's action reopened it — the panel could
        // then never be toggled shut. Dismissal is the monitors' job instead.
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - Presentation

/// Shows and hides the panel under the status item, and owns the dismissal rules an
/// `NSMenu` used to provide for free: click anywhere else, or press Escape.
@MainActor
final class TickerPanelController {
    let contentView: TickerPanelView

    /// Called as the panel opens and closes, so the caller can start and stop the live
    /// update traffic that only matters while it is on screen.
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?

    private let panel: TickerPanel
    private var monitors: [Any] = []
    /// The status item the panel hangs from. Clicks inside it are left alone so the
    /// button's own action decides — dismissing here would close the panel and let the
    /// same click reopen it.
    private weak var anchorButton: NSStatusBarButton?

    init(symbols: [String]) {
        contentView = TickerPanelView(symbols: symbols)
        panel = TickerPanel(contentView: contentView)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo button: NSStatusBarButton) {
        isVisible ? hide() : show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        onOpen?()
        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize
        panel.setContentSize(size)
        position(size: size, under: button)
        anchorButton = button
        // `pushOnPushOff` makes this a persistent native illuminated state rather than
        // the transient mouse-down highlight used by a momentary status button.
        button.state = .on
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()
    }

    func hide() {
        guard panel.isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        anchorButton?.state = .off
        onClose?()
    }

    private func position(size: NSSize, under button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        var x = anchor.midX - size.width / 2
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let margin = NothingTheme.Metric.sm
            x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - NothingTheme.Metric.panelOffset - size.height))
    }

    private func installMonitors() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        // A click on our own status item is delivered to *both* monitors — macOS owns the
        // menu bar, so the event system treats the click as having gone to another
        // application while AppKit still routes it through this process. Either monitor
        // dismissing on it would close the panel a moment before the button's action
        // reopened it, and the panel could never be toggled shut. Both must let it past.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.clickIsOnAnchor() else { return }
                self.hide()
            }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                // 53 = Escape.
                if event.keyCode == 53 {
                    self.hide()
                    return nil
                }
                return event
            }
            if event.window !== self.panel && event.window !== self.anchorButton?.window {
                self.hide()
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Whether the pointer is over the status item. A global event carries no window to
    /// compare against, so the anchor has to be recognised geometrically there.
    private func clickIsOnAnchor() -> Bool {
        guard let button = anchorButton, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(NSEvent.mouseLocation)
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
