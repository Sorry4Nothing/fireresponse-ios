import Foundation
import Observation

/// Die Infokanäle der Person: Liste für den Reiter und die Summe der ungelesenen Mitteilungen für das Badge.
@MainActor @Observable
final class InfoChannelsModel {
    enum Phase: Equatable {
        case loading
        case loaded([InfoChannel])
        case failed(ApiError)
    }

    private(set) var phase: Phase = .loading
    let service: any InfoChannelService

    init(service: any InfoChannelService) { self.service = service }

    var channels: [InfoChannel] {
        if case .loaded(let list) = phase { list } else { [] }
    }

    /// Der Zähler am Reiter: die Summe von `ungelesen`.
    var unreadTotal: Int { channels.reduce(0) { $0 + $1.unread } }

    /// Ein Fehler lässt eine schon geladene Liste stehen.
    func load() async {
        switch await service.infoChannels() {
        case .ok(let list): phase = .loaded(list.channels)
        case .failure(let error, _, _): if case .loaded = phase {} else { phase = .failed(error) }
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }

    /// Der Verlauf wurde gelesen: Der Zähler dieser Einheit geht auf null, bis der nächste Abruf den Stand des Servers bringt.
    func markedRead(unitId: String) {
        guard case .loaded(let list) = phase else { return }
        phase = .loaded(list.map { $0.id == unitId ? $0.withUnread(0) : $0 })
    }
}

/// Der Verlauf einer Einheit. Der Server liefert neueste zuerst; `messages` steht aufsteigend, die neueste unten.
@MainActor @Observable
final class InfoConversationModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(ApiError)
    }

    enum Composer: Equatable {
        case idle
        case sending
        case failed(ApiError)
    }

    static let maxLength = 2000
    static let pageSize = 50

    let channel: InfoChannel
    private(set) var phase: Phase = .loading
    private(set) var messages: [InfoMessage] = []
    private(set) var canWrite: Bool
    private(set) var next: String?
    private(set) var isLoadingOlder = false
    private(set) var composer: Composer = .idle
    /// Die Mitteilung, die gerade bearbeitet wird; das Textfeld trägt ihren Text.
    private(set) var editing: InfoMessage?
    /// Fehler beim Löschen (der Verlauf bleibt, wie er war).
    private(set) var deleteError: ApiError?
    private(set) var sentCount = 0
    private(set) var failedCount = 0

    private let service: any InfoChannelService
    private let onRead: @MainActor () -> Void
    private var lastMarked: String?

    init(channel: InfoChannel, service: any InfoChannelService, onRead: @escaping @MainActor () -> Void = {}) {
        self.channel = channel
        self.service = service
        self.canWrite = channel.canWrite
        self.onRead = onRead
    }

    /// Die erste Seite; ältere bleiben, soweit sie schon geladen waren (neue Mitteilungen kommen unten dazu).
    func load() async {
        switch await service.infoMessages(unitId: channel.id, before: nil, limit: Self.pageSize) {
        case .ok(let page):
            let newest = Array(page.messages.reversed())
            // Ältere, schon geladene Seiten bleiben: alles vor der ältesten Mitteilung der ersten Seite.
            if let oldest = newest.first, let index = messages.firstIndex(where: { $0.id == oldest.id }) {
                messages = Array(messages[..<index]) + newest
            } else {
                messages = newest
                next = page.next
            }
            canWrite = page.canWrite
            phase = .loaded
            await markRead()
        case .failure(let error, _, _):
            if phase != .loaded { phase = .failed(error) }
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }

    func loadOlder() async {
        guard let next, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        if case .ok(let page) = await service.infoMessages(unitId: channel.id, before: next, limit: Self.pageSize) {
            messages = Array(page.messages.reversed()) + messages
            self.next = page.next
        }
    }

    /// Der Text zum Senden: ohne Leerzeichen am Rand, 1 bis 2000 Zeichen; sonst `nil`.
    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...maxLength).contains(trimmed.count) ? trimmed : nil
    }

    /// Sendet an die ganze Einheit. `true`, wenn es angekommen ist.
    func send(_ text: String) async -> Bool {
        guard canWrite, composer != .sending, let clean = Self.clean(text) else { return false }
        composer = .sending
        switch await service.postInfoMessage(unitId: channel.id, text: clean) {
        case .ok(let message):
            messages.append(message)
            composer = .idle
            sentCount += 1
            return true
        case .failure(let error, _, _):
            composer = .failed(error)
            failedCount += 1
            return false
        }
    }

    func startEditing(_ message: InfoMessage) {
        guard message.canEdit else { return }
        editing = message
        composer = .idle
    }

    func cancelEditing() {
        editing = nil
        composer = .idle
    }

    /// Speichert die bearbeitete Mitteilung (löst keinen Push aus).
    func saveEdit(_ text: String) async -> Bool {
        guard let editing, composer != .sending, let clean = Self.clean(text) else { return false }
        composer = .sending
        switch await service.editInfoMessage(unitId: channel.id, messageId: editing.id, text: clean) {
        case .ok(let message):
            if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
            self.editing = nil
            composer = .idle
            sentCount += 1
            return true
        case .failure(let error, _, _):
            composer = .failed(error)
            failedCount += 1
            return false
        }
    }

    /// Löscht für alle: Die Mitteilung bleibt als Platzhalter «Nachricht gelöscht».
    func delete(_ message: InfoMessage) async {
        guard message.canDelete else { return }
        deleteError = nil
        switch await service.deleteInfoMessage(unitId: channel.id, messageId: message.id) {
        case .ok:
            if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message.asDeleted }
            if editing?.id == message.id { editing = nil }
        case .failure(let error, _, _):
            deleteError = error
            failedCount += 1
        }
    }

    func dismissDeleteError() { deleteError = nil }

    /// Setzt den Lesestand, sobald die neueste fremde Mitteilung zu sehen ist. Einmal je neuester Mitteilung.
    func markRead() async {
        guard let newest = messages.last, !newest.isOwn, newest.id != lastMarked else { return }
        lastMarked = newest.id
        if case .ok = await service.markInfoRead(unitId: channel.id) { onRead() } else { lastMarked = nil }
    }
}

/// Links in Mitteilungen sind antippbar; nur `http` und `https`, sonst bleibt es Text.
nonisolated enum InfoText {
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased()),
                  let range = Range(match.range, in: text),
                  let attributedRange = result.range(of: String(text[range])) else { continue }
            result[attributedRange].link = url
        }
        return result
    }
}
