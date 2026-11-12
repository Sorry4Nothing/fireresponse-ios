import Foundation
import Testing
@testable import FireResponse

/// Beispieldaten sind erfunden.
@MainActor
struct WidgetTests {
    private let now = ISO8601DateFormatter().date(from: "2027-03-01T10:00:00Z") ?? .now

    @Test func upcomingSkipsCancelledAndPastAndSortsByStart() throws {
        let past = try makeProgram(id: "past", start: "2027-02-20T13:00:00.000Z", end: "2027-02-20T15:00:00.000Z")
        let cancelled = try makeProgram(id: "cancelled", start: "2027-03-02T13:00:00.000Z", end: "2027-03-02T15:00:00.000Z", status: "abgesagt")
        let later = try makeProgram(id: "later", start: "2027-03-09T13:00:00.000Z", end: "2027-03-09T15:00:00.000Z")
        let sooner = try makeProgram(id: "sooner", start: "2027-03-04T13:00:00.000Z", end: "2027-03-04T15:00:00.000Z")
        let running = try makeProgram(id: "running", start: "2027-03-01T09:00:00.000Z", end: "2027-03-01T11:00:00.000Z")

        let ids = WidgetRules.upcoming([past, cancelled, later, sooner, running], now: now).map(\.id)
        #expect(ids == ["running", "sooner", "later"])
        #expect(WidgetRules.upcoming([later, sooner, running], now: now, count: 2).map(\.id) == ["running", "sooner"])
    }

    @Test func rowCountsAnsweredPeopleIncludingOwnRegistration() throws {
        let program = try makeProgram(start: "2027-03-06T13:00:00.000Z", end: "2027-03-06T16:00:00.000Z", own: "offen", participantStatus: "ja")
        let row = try #require(WidgetSnapshot.make(from: [program], now: now).rows.first)
        #expect(row.count == "1 von 2")
        #expect(row.people == [.init(name: "Anna", stand: .yes), .init(name: "Du", stand: .open)])
        #expect(row.unitType == "JF")
        #expect(row.when == "SA 6.3. · 14:00")
        #expect(row.spoken.contains("Anna: kommt"))
        #expect(row.endsAt == program.end)
    }

    @Test func beforeTheRegistrationWindowShowsTheOpeningDayInsteadOfPeople() throws {
        let program = try makeProgram(start: "2027-03-06T13:00:00.000Z", end: "2027-03-06T16:00:00.000Z", registrationFrom: "2027-03-03", open: false)
        let row = try #require(WidgetSnapshot.make(from: [program], now: now).rows.first)
        #expect(row.count == "ab 3.3.")
        #expect(row.people.isEmpty)
    }

    @Test func storeRoundTripsAndClears() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString).json")
        let store = WidgetSnapshotStore(url: url)
        defer { store.clear() }
        #expect(store.read() == nil)

        let snapshot = WidgetSnapshot.make(from: [try makeProgram()], now: now)
        store.write(snapshot)
        #expect(store.read() == snapshot)

        store.clear()
        #expect(store.read() == nil)
    }

    @Test func linkRoundTripsAndRejectsOtherUrls() throws {
        let id = "0b8c3f2e-1a4d-4c6e-9f3a-2d5b7e8c9a10"
        let url = try #require(WidgetLink.url(programId: id))
        #expect(WidgetLink.programId(from: url) == id)
        #expect(WidgetLink.programId(from: try #require(URL(string: "https://example.com/programm/\(id)"))) == nil)
        #expect(PushTarget.from(type: "programm", id: WidgetLink.programId(from: try #require(URL(string: "fireresponse://programm/x")))) == nil)
    }
}
