@testable import AmpX
import XCTest

/// Toolbar, footer and MIXES WELL sidebar (Library Module spec § Layout, Behaviour).
@MainActor
final class LibraryChromeTests: XCTestCase {
    private let skin = ClassicModernSkin()

    private func type(_ text: String, into input: AmpXTextInput) {
        input.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    func testToolbarReportsSearchBpmAndClear() {
        let toolbar = LibraryToolbarView(skin: self.skin)
        var searches: [String] = []
        var bpms: [(Double?, Double?)] = []
        var clears = 0
        toolbar.onSearch = { searches.append($0) }
        toolbar.onBpm = { bpms.append(($0, $1)) }
        toolbar.onClear = { clears += 1 }

        self.type("house", into: toolbar.search)
        self.type("120", into: toolbar.bpmMin)
        toolbar.bpmMin.insertNewline(nil)
        self.type("126", into: toolbar.bpmMax)
        toolbar.bpmMax.insertNewline(nil)
        XCTAssertEqual(searches, ["house"])
        XCTAssertEqual(bpms.map(\.0), [120, 120])
        XCTAssertEqual(bpms.map(\.1), [nil, 126])

        toolbar.clearBpmButton.action?()
        XCTAssertEqual(toolbar.bpmMin.committedText, "")
        XCTAssertEqual(toolbar.bpmMax.committedText, "")
        XCTAssertEqual(bpms.last?.0, nil)
        toolbar.clearButton.action?()
        XCTAssertEqual(clears, 1)
    }

    func testToolbarApplyReflectsState() {
        let toolbar = LibraryToolbarView(skin: self.skin)
        var state = LibraryFilterState()
        state.search = "acid"
        state.bpmMin = 124
        toolbar.apply(state)
        XCTAssertEqual(toolbar.search.committedText, "acid")
        XCTAssertEqual(toolbar.bpmMin.committedText, "124")
        XCTAssertEqual(toolbar.bpmMax.committedText, "")
        toolbar.apply(LibraryFilterState())
        XCTAssertEqual(toolbar.search.committedText, "")
    }

    func testFooterStatusTexts() {
        let footer = LibraryFooterView(skin: self.skin)
        footer.update(trackCount: 360, totalDuration: 41 * 3600 + 12 * 60 + 8, progress: nil, missing: 0, showingMissing: false)
        XCTAssertEqual(footer.summaryText, "360 TRACKS · 41:12:08")
        XCTAssertEqual(footer.statusText, "UP TO DATE")
        let rootID = UUID()
        footer.update(
            trackCount: 1,
            totalDuration: 59,
            progress: ScanProgress(rootID: rootID, phase: .parsing, done: 1204, total: 2232),
            missing: 0,
            showingMissing: false
        )
        XCTAssertEqual(footer.summaryText, "1 TRACK · 0:00:59")
        XCTAssertEqual(footer.statusText, "SCANNING 1,204 / 2,232")
        footer.update(
            trackCount: 0,
            totalDuration: 0,
            progress: ScanProgress(rootID: rootID, phase: .walking, done: 0, total: 0),
            missing: 0,
            showingMissing: false
        )
        XCTAssertEqual(footer.statusText, "SCANNING…")
    }

    func testMissingButtonHiddenAtZero() {
        let footer = LibraryFooterView(skin: self.skin)
        var toggles = 0
        footer.onToggleMissing = { toggles += 1 }
        footer.update(trackCount: 1, totalDuration: 1, progress: nil, missing: 0, showingMissing: false)
        XCTAssertTrue(footer.missingButton.isHidden)
        footer.update(trackCount: 1, totalDuration: 1, progress: nil, missing: 3, showingMissing: true)
        XCTAssertFalse(footer.missingButton.isHidden)
        XCTAssertEqual(footer.missingButton.label, "3 MISSING")
        XCTAssertTrue(footer.missingButton.isActive)
        footer.missingButton.action?()
        XCTAssertEqual(toggles, 1)
    }

    func testFooterEnqueue() {
        let footer = LibraryFooterView(skin: self.skin)
        var enqueued = 0
        footer.onEnqueue = { enqueued += 1 }
        footer.enqueueButton.action?()
        XCTAssertEqual(enqueued, 1)
        XCTAssertEqual(footer.rootsButton.label, "ROOTS")
    }

    func testSidebarPlaceholderAndDisabledQueue() {
        let sidebar = LibraryMixesSidebarView(skin: self.skin)
        XCTAssertEqual(sidebar.placeholderText, "Recommendations arrive with DJ mode (BPM & key analysis).")
        XCTAssertFalse(sidebar.queueButton.isEnabled)
        XCTAssertEqual(sidebar.referenceText, "No track")
        let row = LibraryRow(
            id: UUID(), rootID: UUID(), url: URL(fileURLWithPath: "/a.mp3"), title: "The Finishing", artist: "Stavroz",
            album: "", albumArtist: "", genre: nil, trackNumber: nil, duration: 1, fileSize: 1, bpm: 124, musicalKey: "8A",
            bitrate: 0, bitrateIsDerived: false, codec: "mp3", isAvailable: true, searchKey: ""
        )
        sidebar.updateReference(row)
        XCTAssertEqual(sidebar.referenceText, "Stavroz – The Finishing · 124 BPM · 8A")
    }

    func testSidebarModeToggleReports() {
        let sidebar = LibraryMixesSidebarView(skin: self.skin)
        var modes: [Bool] = []
        sidebar.onModeChange = { modes.append($0) }
        XCTAssertTrue(sidebar.playingButton.isActive)
        sidebar.selectedButton.action?()
        XCTAssertTrue(sidebar.followsSelection)
        XCTAssertTrue(sidebar.selectedButton.isActive)
        XCTAssertFalse(sidebar.playingButton.isActive)
        sidebar.selectedButton.action?()
        sidebar.playingButton.action?()
        XCTAssertEqual(modes, [true, false], "re-selecting the active mode reports nothing")
    }

    // MARK: - rekordbox

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var report: RekordboxSyncReport {
        var report = RekordboxSyncReport(fileName: "collection.xml")
        report.matched = 2232
        report.updated = 12
        report.unmatched = ["/Music/MUSICA/a.mp3", "/Music/MUSICA/b.mp3"]
        report.ambiguous = [.init(path: "/Music/x.mp3", candidates: ["/Music/DJ/x.mp3", "/Music/DJ/y.mp3"])]
        report.noLongerInRekordbox = ["/Music/DJ/gone.mp3"]
        return report
    }

    func testRekordboxIndicatorText() {
        let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 14:13 UTC
        let today = now.addingTimeInterval(-3600)
        let earlier = Date(timeIntervalSince1970: 1_788_400_000) // 2026-09-03
        XCTAssertNil(LibraryFooterView.rekordboxText(.hidden, now: now, calendar: self.utc))
        XCTAssertEqual(LibraryFooterView.rekordboxText(.idle(lastSync: today), now: now, calendar: self.utc), "REKORDBOX 13:13")
        XCTAssertEqual(LibraryFooterView.rekordboxText(.idle(lastSync: earlier), now: now, calendar: self.utc), "REKORDBOX 3 SEP")
        XCTAssertEqual(LibraryFooterView.rekordboxText(.idle(lastSync: nil), now: now, calendar: self.utc), "REKORDBOX")
        XCTAssertEqual(LibraryFooterView.rekordboxText(.syncing, now: now, calendar: self.utc), "REKORDBOX SYNCING")
    }

    func testIndicatorHiddenWithoutSources() {
        let footer = LibraryFooterView(skin: self.skin)
        footer.update(trackCount: 1, totalDuration: 60, progress: nil, missing: 0, showingMissing: false)
        XCTAssertTrue(footer.rekordboxButton.isHidden)
        footer.update(trackCount: 1, totalDuration: 60, progress: nil, missing: 0, showingMissing: false, rekordbox: .syncing)
        XCTAssertFalse(footer.rekordboxButton.isHidden)
        XCTAssertEqual(footer.rekordboxButton.label, "REKORDBOX SYNCING")
        var clicks = 0
        footer.onRekordboxClick = { clicks += 1 }
        footer.rekordboxButton.action?()
        XCTAssertEqual(clicks, 1)
    }

    func testReportSummaryLines() {
        XCTAssertEqual(LibraryRekordboxReportView.summary(self.report), [
            "collection.xml",
            "2,232 of 2,235 tracks matched",
            "12 updated",
            "2 not in any library folder",
            "1 ambiguous",
            "1 no longer in rekordbox",
        ])
        var quiet = RekordboxSyncReport(fileName: "x.xml")
        quiet.matched = 1
        XCTAssertEqual(LibraryRekordboxReportView.summary(quiet), ["x.xml", "1 of 1 tracks matched", "0 updated"])
    }

    func testReportListsEntriesUnderHeadings() {
        let view = LibraryRekordboxReportView(skin: self.skin)
        view.show(self.report)
        XCTAssertEqual(view.entryLines, [
            "NOT IN ANY LIBRARY FOLDER", "/Music/MUSICA/a.mp3", "/Music/MUSICA/b.mp3",
            "AMBIGUOUS", "/Music/x.mp3",
            "NO LONGER IN REKORDBOX", "/Music/DJ/gone.mp3",
        ])
    }

    func testReportCloseOnEscape() throws {
        let view = LibraryRekordboxReportView(skin: self.skin)
        var closes = 0
        view.onClose = { closes += 1 }
        view.show(self.report)
        view.closeButton.action?()
        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
        XCTAssertTrue(view.handleKey(escape))
        XCTAssertEqual(closes, 2)
    }
}
