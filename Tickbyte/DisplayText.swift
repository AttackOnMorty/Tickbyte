//
//  DisplayText.swift
//  Tickbyte
//
//  Pure builders for the menu-bar title and the panel's strings. Foundation-only so they
//  are testable without AppKit.
//

import Foundation

/// Text for the panel. The panel owns colour and layout; this owns the words, so the
/// wording rules (instrument-panel labels, signed percentages, placeholders) can be
/// tested without a live socket.
enum PanelText {
    static let wordmark = "TICKBYTE"

    /// "btcusdt" -> "BTC/USDT". The quote asset is spelled out here — the panel has the
    /// room the menu bar does not.
    static func pair(for symbol: String) -> String {
        let code = SymbolCatalog.displayCode(for: symbol)
        let quote = quoteAsset(for: symbol)
        return quote.isEmpty ? code : "\(code)/\(quote)"
    }

    /// Adjacent unit for the hero price. Empty when the pair has no known quote.
    static func quoteAsset(for symbol: String) -> String {
        symbol.hasSuffix("usdt") ? "USDT" : ""
    }

    /// Four-letter instrument states, all the same width so the header never reflows.
    enum Status: String {
        case live = "LIVE"
        case sync = "SYNC"
        case lost = "LOST"

        /// A healthy feed is self-evident from the moving market data. Reserve the
        /// footer for states that need attention instead of confirming routine success.
        var footerText: String? {
            self == .live ? nil : "[\(rawValue)]"
        }
    }

    static func status(state: ConnectionState?) -> Status {
        switch state {
        case .connected: return .live
        case .connecting: return .sync
        case .disconnected, .error, .none: return .lost
        }
    }

    /// The panel has one feed indicator rather than repeating a status beside every
    /// instrument. It only claims LIVE when every visible socket is healthy.
    static func feedStatus(states: [ConnectionState?]) -> Status {
        guard !states.isEmpty else { return .lost }
        if states.allSatisfy({ status(state: $0) == .live }) { return .live }
        if states.contains(where: { status(state: $0) == .lost }) { return .lost }
        return .sync
    }

    enum Direction {
        case up, down, flat
    }

    /// Status colour roles, kept as names so the AppKit layer can map them to tokens
    /// without the colour decision living in a view.
    enum ColorRole {
        case success, accent, disabled
    }

    struct Change {
        let text: String
        let direction: Direction
    }

    /// The sign and the colour carry the direction — no arrow glyph, which would have to
    /// be a filled triangle. Zero is flat, not up: a print of `+0.00%` is not a move.
    static func change(fromRaw raw: String) -> Change {
        guard let value = PriceFormatter.percentValue(raw) else {
            return Change(text: PriceFormatter.placeholder, direction: .flat)
        }
        let direction: Direction = value > 0 ? .up : value < 0 ? .down : .flat
        return Change(text: PriceFormatter.percent(raw), direction: direction)
    }

    /// East-Asian tape: red marks an advance, green a decline. Zero stays
    /// disabled — it is not a move.
    static func changeColorRole(_ direction: Direction) -> ColorRole {
        switch direction {
        case .up: return .accent
        case .down: return .success
        case .flat: return .disabled
        }
    }
}

/// Which coin sits in the hero slot. Pure set math so the panel can stay a dumb view.
enum PanelBoard {
    struct Arrangement: Equatable {
        let hero: String?
        let compact: [String]
    }

    static func arrange(focused: String?, symbols: [String]) -> Arrangement {
        guard let first = symbols.first else {
            return Arrangement(hero: nil, compact: [])
        }
        let hero = focused.flatMap { symbols.contains($0) ? $0 : nil } ?? first
        return Arrangement(hero: hero, compact: symbols.filter { $0 != hero })
    }
}

/// Builds the status-bar title from already-resolved per-symbol items, together with the
/// exact ranges to colour. Ranges are computed by construction rather than by searching
/// the finished string, so a placeholder value can never make a colour land on the wrong
/// token.
///
/// Staleness is shown by dimming the whole item rather than by adding a warning glyph —
/// the menu bar has no room for ornament, and opacity already encodes state everywhere
/// else in the system.
enum StatusBarText {
    struct Item {
        let code: String
        let price: String
        /// A price is stale only after a confirmed socket failure. Connecting and
        /// not-yet-connected items remain readable while loading.
        let isStale: Bool
    }

    /// `Equatable` so the caller can skip touching the status bar when nothing changed —
    /// colour shifts count as changes, which a plain string comparison would miss.
    struct Title: Equatable {
        let text: String
        /// Ticker codes of live items — secondary weight.
        let codeRanges: [NSRange]
        /// Prices of live items — display weight.
        let valueRanges: [NSRange]
        /// Whole items whose sockets have genuinely failed — dimmed, never hidden.
        let staleRanges: [NSRange]
    }

    /// Wide enough that the eye groups each code with its own price. Spacing, not a
    /// divider, separates the pair.
    private static let separator = "  "

    static func make(items: [Item]) -> Title {
        guard !items.isEmpty else {
            let text = AppConfiguration.UI.loadingText
            return Title(
                text: text,
                codeRanges: [],
                valueRanges: [],
                staleRanges: []
            )
        }

        var text = ""
        var codeRanges: [NSRange] = []
        var valueRanges: [NSRange] = []
        var staleRanges: [NSRange] = []

        for item in items {
            if !text.isEmpty { text += separator }
            let start = (text as NSString).length
            let codeLength = (item.code as NSString).length
            text += "\(item.code) \(item.price)"
            let itemLength = (text as NSString).length - start

            if !item.isStale {
                codeRanges.append(NSRange(location: start, length: codeLength))
                valueRanges.append(NSRange(location: start + codeLength + 1, length: itemLength - codeLength - 1))
            } else {
                staleRanges.append(NSRange(location: start, length: itemLength))
            }
        }

        return Title(text: text, codeRanges: codeRanges, valueRanges: valueRanges, staleRanges: staleRanges)
    }
}
