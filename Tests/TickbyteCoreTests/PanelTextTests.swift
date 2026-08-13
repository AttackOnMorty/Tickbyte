import XCTest
@testable import TickbyteCore

final class PanelTextTests: XCTestCase {

    // MARK: pair

    func testPairSpellsOutTheQuoteAsset() {
        XCTAssertEqual(PanelText.pair(for: "btcusdt"), "BTC/USDT")
    }

    func testPairFallsBackToTheBareCode() {
        XCTAssertEqual(PanelText.pair(for: "btc"), "BTC")
    }

    // MARK: status

    func testSymbolReportsItsSocketState() {
        XCTAssertEqual(PanelText.status(state: .connected), .live)
        XCTAssertEqual(PanelText.status(state: .connecting), .sync)
        XCTAssertEqual(PanelText.status(state: .disconnected), .lost)
        XCTAssertEqual(PanelText.status(state: .error(.invalidURL)), .lost)
        XCTAssertEqual(PanelText.status(state: nil), .lost)
    }

    func testStatusLabelsAreTheSameWidthSoTheHeaderNeverReflows() {
        let widths = Set([PanelText.Status.live, .sync, .lost].map(\.rawValue.count))
        XCTAssertEqual(widths, [4])
    }

    func testSharedFeedIsLiveOnlyWhenEverySocketIsLive() {
        XCTAssertEqual(PanelText.feedStatus(states: [.connected, .connected]), .live)
        XCTAssertEqual(PanelText.feedStatus(states: [.connected, .connecting]), .sync)
        XCTAssertEqual(PanelText.feedStatus(states: [.connected, .disconnected]), .lost)
        XCTAssertEqual(PanelText.feedStatus(states: []), .lost)
    }

    func testFooterIsSilentWhenHealthyAndShowsExceptions() {
        XCTAssertNil(PanelText.Status.live.footerText)
        XCTAssertEqual(PanelText.Status.sync.footerText, "[SYNC]")
        XCTAssertEqual(PanelText.Status.lost.footerText, "[LOST]")
    }

    // MARK: change

    func testChangeCarriesDirectionInSignAndCase() {
        XCTAssertEqual(PanelText.change(fromRaw: "2.5").text, "+2.50%")
        XCTAssertEqual(PanelText.change(fromRaw: "2.5").direction, .up)
        XCTAssertEqual(PanelText.change(fromRaw: "-1.2").text, "-1.20%")
        XCTAssertEqual(PanelText.change(fromRaw: "-1.2").direction, .down)
    }

    func testZeroChangeCountsAsFlat() {
        XCTAssertEqual(PanelText.change(fromRaw: "0").direction, .flat)
        XCTAssertEqual(PanelText.change(fromRaw: "0").text, "+0.00%")
    }

    func testQuoteAssetIsTheUSDTSuffix() {
        XCTAssertEqual(PanelText.quoteAsset(for: "btcusdt"), "USDT")
        XCTAssertEqual(PanelText.quoteAsset(for: "ethusdt"), "USDT")
    }

    func testQuoteAssetIsEmptyWhenThePairHasNoUSDTQuote() {
        XCTAssertEqual(PanelText.quoteAsset(for: "btc"), "")
    }

    func testUpIsAccentAndDownIsSuccess() {
        XCTAssertEqual(PanelText.changeColorRole(.up), .accent)
        XCTAssertEqual(PanelText.changeColorRole(.down), .success)
        XCTAssertEqual(PanelText.changeColorRole(.flat), .disabled)
    }

    func testLastPrintDirectionComparesThisPrintToTheLast() {
        XCTAssertEqual(PanelText.lastPrintDirection(from: "64,556", to: "64,557"), .up)
        XCTAssertEqual(PanelText.lastPrintDirection(from: "64,557", to: "64,556"), .down)
        XCTAssertEqual(PanelText.lastPrintDirection(from: "64,556", to: "64,556"), .flat)
    }

    func testLastPrintDirectionReadsGroupedAndDecimalDisplay() {
        XCTAssertEqual(PanelText.lastPrintDirection(from: "1,889", to: "1,890"), .up)
        XCTAssertEqual(PanelText.lastPrintDirection(from: "9.99", to: "10.00"), .up)
        XCTAssertEqual(PanelText.lastPrintDirection(from: "10.00", to: "9.99"), .down)
    }

    func testLastPrintDirectionIsFlatWhenASideIsUnparseable() {
        XCTAssertEqual(PanelText.lastPrintDirection(from: "", to: "64,556"), .flat)
        XCTAssertEqual(PanelText.lastPrintDirection(from: "—", to: "64,556"), .flat)
        XCTAssertEqual(PanelText.lastPrintDirection(from: "64,556", to: "—"), .flat)
    }

    func testBoardPromotesTheFocusedCoinAndKeepsTheRestCompact() {
        let board = PanelBoard.arrange(focused: "ethusdt", symbols: ["btcusdt", "ethusdt"])
        XCTAssertEqual(board.hero, "ethusdt")
        XCTAssertEqual(board.compact, ["btcusdt"])
    }

    func testBoardFallsBackToTheFirstSymbolWhenFocusIsMissing() {
        let unknown = PanelBoard.arrange(focused: "dogeusdt", symbols: ["btcusdt", "ethusdt"])
        XCTAssertEqual(unknown.hero, "btcusdt")
        XCTAssertEqual(unknown.compact, ["ethusdt"])

        let empty = PanelBoard.arrange(focused: nil, symbols: ["btcusdt", "ethusdt"])
        XCTAssertEqual(empty.hero, "btcusdt")
        XCTAssertEqual(empty.compact, ["ethusdt"])
    }

    func testBoardIsEmptyWhenThereAreNoSymbols() {
        let board = PanelBoard.arrange(focused: "btcusdt", symbols: [])
        XCTAssertNil(board.hero)
        XCTAssertTrue(board.compact.isEmpty)
    }

    func testUnparseableChangeFallsBackToThePlaceholder() {
        let change = PanelText.change(fromRaw: "not a number")
        XCTAssertEqual(change.text, PriceFormatter.placeholder)
        XCTAssertEqual(change.direction, .flat)
    }
}
