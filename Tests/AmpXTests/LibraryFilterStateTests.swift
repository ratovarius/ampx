@testable import AmpX
import XCTest

final class LibraryFilterStateTests: XCTestCase {
    func testQueryMapping() {
        var state = LibraryFilterState()
        state.search = "deep"
        state.genres = [.text("House")]
        state.artists = [.text("Kora")]
        state.bpmMin = 120
        state.bpmMax = 126
        state.showMissing = true
        state.sortBy(.bpm)
        let query = state.query
        XCTAssertEqual(query.search, "deep")
        XCTAssertEqual(query.genres, [.text("House")])
        XCTAssertEqual(query.artists, [.text("Kora")])
        XCTAssertTrue(query.albums.isEmpty)
        XCTAssertEqual(query.bpmRange, 120 ... 126)
        XCTAssertTrue(query.onlyUnavailable)
        XCTAssertEqual(query.sort, .bpm)
        XCTAssertTrue(query.ascending)
    }

    func testBpmSwapAndBlank() {
        var state = LibraryFilterState()
        XCTAssertNil(state.query.bpmRange)
        state.bpmMin = 130
        state.bpmMax = 120
        XCTAssertEqual(state.query.bpmRange, 120 ... 130)
        state.bpmMax = nil
        XCTAssertEqual(state.query.bpmRange?.lowerBound, 130)
        XCTAssertEqual(state.query.bpmRange?.upperBound, .greatestFiniteMagnitude)
        state.bpmMin = nil
        state.bpmMax = 110
        XCTAssertEqual(state.query.bpmRange, 0 ... 110)
    }

    func testFacetClickSingleAndCommandMulti() {
        var state = LibraryFilterState()
        state.facetClick(.text("Techno"), facet: \.genres, command: false)
        XCTAssertEqual(state.genres, [.text("Techno")])
        state.facetClick(.text("House"), facet: \.genres, command: false)
        XCTAssertEqual(state.genres, [.text("House")])
        state.facetClick(.text("Trance"), facet: \.genres, command: true)
        XCTAssertEqual(state.genres, [.text("House"), .text("Trance")])
        state.facetClick(.text("House"), facet: \.genres, command: true)
        XCTAssertEqual(state.genres, [.text("Trance")])
    }

    func testClickingSelectedValueClearsFacet() {
        var state = LibraryFilterState()
        state.facetClick(.absent, facet: \.artists, command: false)
        state.facetClick(.absent, facet: \.artists, command: false)
        XCTAssertTrue(state.artists.isEmpty)
    }

    func testClearKeepsSort() {
        var state = LibraryFilterState()
        state.search = "x"
        state.genres = [.absent]
        state.bpmMin = 1
        state.showMissing = true
        state.sortBy(.bpm)
        state.sortBy(.bpm)
        state.clear()
        XCTAssertEqual(state.query, LibraryQuery(sort: .bpm, ascending: false))
    }

    func testSortToggle() {
        var state = LibraryFilterState()
        state.sortBy(.title)
        XCTAssertEqual(state.sort, .title)
        XCTAssertTrue(state.ascending)
        state.sortBy(.title)
        XCTAssertFalse(state.ascending)
        state.sortBy(.genre)
        XCTAssertEqual(state.sort, .genre)
        XCTAssertTrue(state.ascending)
    }

    func testHidingSortedColumnFallsBackToArtist() {
        var state = LibraryFilterState()
        state.sortBy(.bpm)
        var columns = LibraryColumnSet.default
        columns.toggle(.bpm)
        state.columnsChanged(columns)
        XCTAssertEqual(state.sort, .artist)
        XCTAssertTrue(state.ascending)
        state.sortBy(.title)
        state.columnsChanged(columns)
        XCTAssertEqual(state.sort, .title, "a visible sort column is kept")
    }

    func testPreferencesRoundTripAndDefaults() throws {
        let suite = "LibraryFilterStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LibraryModulePreferences.load(defaults), LibraryModulePreferences())

        var preferences = LibraryModulePreferences()
        preferences.columns.toggle(.number)
        preferences.sort = .genre
        preferences.ascending = false
        preferences.mixesFollowsSelection = true
        preferences.save(defaults)
        XCTAssertEqual(LibraryModulePreferences.load(defaults), preferences)

        defaults.set(Data("garbage".utf8), forKey: LibraryModulePreferences.storageKey)
        XCTAssertEqual(LibraryModulePreferences.load(defaults), LibraryModulePreferences())
    }
}
