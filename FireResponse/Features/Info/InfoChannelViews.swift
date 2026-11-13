import SwiftUI

/// Reiter «Infokanal» (Issue #68). Hat die Person eine Einheit, öffnet er direkt den Verlauf, bei mehreren Einheiten steht eine Liste.
/// Eingabe nur für Kommando und Leitung der jeweiligen Einheit; alle anderen lesen nur. Im Design für iOS nicht gezeichnet: aus den
/// Bausteinen und den Texten des Prompts gebaut (Entwurf).
struct InfoChannelRootView: View {
    let model: InfoChannelsModel
    var router: PushRouter = PushCenter.shared.router
    @State private var path: [InfoChannel] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch model.phase {
                case .loading:
                    StateView(.loading)
                case .failed(let error):
                    ScrollView { StateView(error == .network ? .offline : .error, primary: { Task { await model.retry() } }) }
                case .loaded(let channels) where channels.isEmpty:
                    ScrollView { EmptyChannels() }
                case .loaded(let channels) where channels.count == 1:
                    InfoConversationView(channel: channels[0], service: model.service, onRead: { model.markedRead(unitId: channels[0].id) })
                        .id(channels[0].id)
                case .loaded(let channels):
                    ChannelList(channels: channels)
                }
            }
            .background(Color.frSurface)
            .navigationTitle(singleName ?? String(localized: "Infokanal"))
            .navigationBarTitleDisplayMode(singleName == nil ? .large : .inline)
            .navigationDestination(for: InfoChannel.self) { channel in
                // Wer mehrere Einheiten hat, wechselt im Kopf über ein Menü; der neue Verlauf ersetzt den alten.
                InfoConversationView(
                    channel: channel, service: model.service, siblings: model.channels,
                    onSwitch: { path = [$0] }, onRead: { model.markedRead(unitId: channel.id) }
                )
                .id(channel.id)
            }
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load() } } }
        // Ein angetippter Push öffnet den Verlauf der Einheit.
        .onChange(of: router.pendingInfoChannel, initial: true) { openPending() }
        .onChange(of: model.phase) { openPending() }
    }

    private var singleName: String? {
        model.channels.count == 1 ? model.channels[0].name : nil
    }

    private func openPending() {
        guard let unitId = router.pendingInfoChannel, case .loaded(let channels) = model.phase else { return }
        _ = router.consumeInfoChannel()
        if channels.count > 1, let channel = channels.first(where: { $0.id == unitId }) { path = [channel] }
    }
}

extension InfoChannel: Hashable {
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct EmptyChannels: View {
    var body: some View {
        VStack(spacing: Spacing.s4) {
            Image(systemName: "megaphone").font(.title).foregroundStyle(Color.frOnSecondaryContainer)
                .frame(width: 72, height: 72).background(Color.frSecondaryContainer, in: .circle).accessibilityHidden(true)
            Text("Noch kein Infokanal").font(.frTitle2).foregroundStyle(Color.frOnSurface).accessibilityAddTraits(.isHeader)
            Text("Sobald deine Einheit Mitteilungen verschickt, siehst du sie hier.").font(.body)
                .foregroundStyle(Color.frOnSurfaceVariant).multilineTextAlignment(.center)
        }
        .padding(Spacing.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Eine Zeile je Einheit mit Zähler und Zeit der letzten Mitteilung.
private struct ChannelList: View {
    let channels: [InfoChannel]

    var body: some View {
        List(channels) { channel in
            NavigationLink(value: channel) {
                HStack(spacing: Spacing.s3) {
                    UnitMark(data: nil, type: channel.unit.type, settled: true, size: 32)
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text(verbatim: channel.name).font(.body.weight(.semibold)).foregroundStyle(Color.frOnSurface)
                        if let last = channel.lastMessageAt {
                            Text(verbatim: InfoFormat.listTime(last)).font(.footnote).foregroundStyle(Color.frOnSurfaceVariant)
                        }
                    }
                    Spacer(minLength: Spacing.s2)
                    if channel.unread > 0 {
                        Text("\(channel.unread)").font(.footnote.weight(.bold)).foregroundStyle(Color.frOnPrimary)
                            .padding(.horizontal, Spacing.s2).frame(minWidth: 24, minHeight: 24)
                            .background(Color.frPrimary, in: .capsule).accessibilityHidden(true)
                    }
                }
                .frame(minHeight: Sizes.touchTarget)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(channel.unread > 0 ? Text("\(channel.name), \(channel.unread) ungelesen") : Text(verbatim: channel.name))
            }
            .listRowBackground(Color.frSurfaceContainerLow)
        }
        .scrollContentBackground(.hidden)
    }
}

nonisolated enum InfoFormat {
    /// «14:30» heute, sonst «14.11.».
    static func listTime(_ date: Date, now: Date = .now) -> String {
        let day = SwissDay(date: date)
        return day == SwissDay(date: now) ? ExerciseFormat.time(date) : ExerciseFormat.numeric(day)
    }

    /// Tagestrenner im Verlauf: «Heute» oder «Samstag, 14. November».
    static func dayHeading(_ day: SwissDay, now: Date = .now) -> String {
        day == SwissDay(date: now) ? String(localized: "Heute") : ExerciseFormat.longDay(day)
    }

    /// «Kommando» oder «Leitung»; die Stellvertretung gilt als Kommando (der Server liefert schon `kommando`).
    static func roleName(_ role: String?) -> String? {
        switch role {
        case "kommando": String(localized: "Kommando")
        case "leitung": String(localized: "Leitung")
        default: nil
        }
    }
}

/// Der Verlauf einer Einheit: neueste Mitteilung unten, Tagestrenner, Eingabe nur für Schreibende.
struct InfoConversationView: View {
    @State private var model: InfoConversationModel
    @State private var draft = ""
    @State private var deleting: InfoMessage?
    @FocusState private var inputFocused: Bool
    private let siblings: [InfoChannel]
    private let onSwitch: (InfoChannel) -> Void

    init(
        channel: InfoChannel, service: any InfoChannelService, siblings: [InfoChannel] = [],
        onSwitch: @escaping (InfoChannel) -> Void = { _ in }, onRead: @escaping @MainActor () -> Void = {}
    ) {
        _model = State(initialValue: InfoConversationModel(channel: channel, service: service, onRead: onRead))
        self.siblings = siblings
        self.onSwitch = onSwitch
    }

    var body: some View {
        content
            .background(Color.frSurface)
            .navigationTitle(model.channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if siblings.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(siblings.filter { $0.id != model.channel.id }) { other in
                                Button(other.name) { onSwitch(other) }
                            }
                        } label: {
                            Label("Einheit wechseln", systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .task { await model.load() }
            .refreshable { await model.load() }
            .sensoryFeedback(.success, trigger: model.sentCount)
            .sensoryFeedback(.error, trigger: model.failedCount)
            .alert("Mitteilung für alle löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    if let message = deleting { Task { await model.delete(message) } }
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            StateView(.loading)
        case .failed(let error):
            ScrollView { StateView(error == .network ? .offline : .error, primary: { Task { await model.retry() } }) }
        case .loaded where model.messages.isEmpty:
            ScrollView {
                VStack(spacing: Spacing.s2) {
                    Text("Noch keine Mitteilungen").font(.frTitle2).foregroundStyle(Color.frOnSurface).accessibilityAddTraits(.isHeader)
                    Text(model.canWrite ? "Deine Mitteilung geht an alle in der Einheit." : "Hier erscheinen die Mitteilungen deiner Einheit.")
                        .font(.body).foregroundStyle(Color.frOnSurfaceVariant).multilineTextAlignment(.center)
                }
                .padding(Spacing.s6).frame(maxWidth: .infinity)
            }
        case .loaded:
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.s3) {
                    if model.next != nil {
                        Button { Task { await model.loadOlder() } } label: {
                            Text(model.isLoadingOlder ? "Wird geladen …" : "Ältere Mitteilungen laden").frame(maxWidth: .infinity, minHeight: Sizes.touchTarget)
                        }
                        .disabled(model.isLoadingOlder)
                    }
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || SwissDay(date: model.messages[index - 1].createdAt) != SwissDay(date: message.createdAt) {
                            Text(verbatim: InfoFormat.dayHeading(SwissDay(date: message.createdAt))).font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.frOnSurfaceVariant).frame(maxWidth: .infinity).padding(.top, Spacing.s2)
                                .accessibilityAddTraits(.isHeader)
                        }
                        MessageCard(message: message, isNew: model.newIds.contains(message.id), onEdit: { start(editing: message) }, onDelete: { deleting = message })
                            .id(message.id)
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s3)
                .frame(maxWidth: Sizes.contentMax)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            // Nach dem Senden und bei einer neuen Mitteilung unten bleiben.
            .onChange(of: model.messages.last?.id) { _, last in
                if let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
            }
            }
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if model.phase == .loaded {
            VStack(spacing: Spacing.s2) {
                if model.deleteError != nil {
                    Notice(.error, title: "Löschen hat nicht geklappt", message: "Prüfe dein Internet und versuche es nochmals.")
                }
                if case .failed(let error) = model.composer {
                    Notice(.error, title: model.editing == nil ? "Mitteilung nicht gesendet" : "Änderung nicht gespeichert", message: ExerciseMessage.text(for: error))
                }
                if model.canWrite { composer } else {
                    Text("Nur Kommando und Leitung schreiben hier").font(.footnote).foregroundStyle(Color.frOnSurfaceVariant)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
            .background(.bar)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            if model.editing != nil {
                HStack {
                    Text("Mitteilung bearbeiten").font(.footnote.weight(.semibold)).foregroundStyle(Color.frOnSurfaceVariant)
                    Spacer()
                    Button("Abbrechen") { draft = ""; model.cancelEditing() }.font(.footnote.weight(.semibold))
                }
            }
            HStack(alignment: .bottom, spacing: Spacing.s2) {
                TextField("Mitteilung an die Einheit", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .padding(.horizontal, Spacing.s3).padding(.vertical, Spacing.s2)
                    .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
                    .overlay(RoundedRectangle(radius: Radius.md).stroke(Color.frOutline, lineWidth: 1))
                Button(action: tapSend) {
                    Image(systemName: model.editing == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill").font(.system(size: 32))
                        .frame(width: Sizes.touchTarget, height: Sizes.touchTarget)
                }
                .foregroundStyle(canSubmit ? Color.frPrimary : Color.frOnSurfaceVariant)
                .disabled(!canSubmit)
                .accessibilityLabel(model.editing == nil ? Text("Senden") : Text("Speichern"))
            }
            if draft.count > InfoConversationModel.maxLength - 200 {
                Text("\(draft.count) von \(InfoConversationModel.maxLength) Zeichen").font(.footnote)
                    .foregroundStyle(draft.count > InfoConversationModel.maxLength ? Color.frOnErrorContainer : .frOnSurfaceVariant)
            }
        }
    }

    private var canSubmit: Bool { model.composer != .sending && InfoConversationModel.clean(draft) != nil }

    private func tapSend() {
        submit()
    }

    private func submit() {
        let text = draft
        Task {
            let done = model.editing == nil ? await model.send(text) : await model.saveEdit(text)
            if done { draft = ""; inputFocused = false }
        }
    }

    private func start(editing message: InfoMessage) {
        model.startEditing(message)
        draft = message.text ?? ""
        inputFocused = true
    }
}

/// Eine Mitteilung: ruhige Karte, Absender mit Rolle, Zeit, Text (Links antippbar, Text auswählbar), «bearbeitet».
/// Das Menü (Langdruck) bietet nur, was `darfBearbeiten` und `darfLoeschen` sagen.
private struct MessageCard: View {
    let message: InfoMessage
    let isNew: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            if message.isDeleted {
                Text("Nachricht gelöscht").font(.body.italic()).foregroundStyle(Color.frOnSurfaceVariant)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: author).font(.footnote.weight(.semibold)).foregroundStyle(Color.frAccentText)
                    if isNew {
                        Label("Neu", systemImage: "circle.fill").font(.caption.weight(.bold)).foregroundStyle(Color.frPrimaryText)
                            .labelStyle(.titleAndIcon)
                    }
                    Spacer(minLength: Spacing.s2)
                    Text(verbatim: ExerciseFormat.time(message.createdAt)).font(.footnote).monospacedDigit().foregroundStyle(Color.frOnSurfaceVariant)
                }
                Text(InfoText.attributed(message.text ?? "")).font(.body).foregroundStyle(Color.frOnSurface).textSelection(.enabled)
                if message.isEdited { Text("bearbeitet").font(.caption).foregroundStyle(Color.frOnSurfaceVariant) }
            }
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
        .contextMenu {
            if message.canEdit { Button("Bearbeiten", systemImage: "pencil", action: onEdit) }
            if message.canDelete { Button("Löschen", systemImage: "trash", role: .destructive, action: onDelete) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if message.canEdit { Button("Bearbeiten", action: onEdit) }
            if message.canDelete { Button("Löschen", action: onDelete) }
        }
    }

    private var author: String {
        // Gelöschtes Konto: der Server liefert keinen Autor.
        let name = message.author?.name ?? String(localized: "Ehemaliges Mitglied")
        guard let role = InfoFormat.roleName(message.author?.role) else { return name }
        return name.isEmpty ? role : "\(name) · \(role)"
    }
}

#if DEBUG
/// Erfundene Daten für Vorschauen; nie echte Namen.
final class PreviewInfoService: InfoChannelService, @unchecked Sendable {
    private let canWrite: Bool

    init(canWrite: Bool) { self.canWrite = canWrite }

    private func message(_ id: String, _ text: String?, hoursAgo: Double, role: String? = "kommando", name: String = "Petra Beispiel",
                         own: Bool = false, edited: Bool = false, deleted: Bool = false) -> InfoMessage {
        InfoMessage(
            id: id, text: text, isDeleted: deleted, isEdited: edited, createdAt: .now.addingTimeInterval(-hoursAgo * 3600),
            author: deleted ? nil : InfoAuthor(name: name, role: role, imagePath: nil), isOwn: own,
            canEdit: own && !deleted && canWrite, canDelete: (own || role == "kommando") && !deleted && canWrite
        )
    }

    func infoChannels() async -> ApiResult<InfoChannelList> {
        let unit = ProgramUnit(id: "e1", name: "Jugendfeuerwehr Beispielstadt", type: "jf")
        return .ok(InfoChannelList(channels: [InfoChannel(unit: unit, name: "Infokanal Jugendfeuerwehr Beispielstadt", canWrite: canWrite, unread: 3, lastMessageAt: .now)]))
    }

    func infoMessages(unitId: String, before: String?, limit: Int) async -> ApiResult<InfoMessagePage> {
        let all = [
            message("m3", "Am Samstag treffen wir uns schon um 13:00 im Magazin. Details: https://example.org/lager", hoursAgo: 1, own: true, edited: true),
            message("m2", nil, hoursAgo: 5, deleted: true),
            message("m1", "Das Sommerlager steht. Bitte die Anmeldung bis Ende Monat zurückschicken.", hoursAgo: 30, role: "leitung", name: "Sandra Probe"),
        ]
        return .ok(InfoMessagePage(canWrite: canWrite, messages: all, next: nil))
    }

    func postInfoMessage(unitId: String, text: String) async -> ApiResult<InfoMessage> {
        .ok(message("neu", text, hoursAgo: 0, own: true))
    }

    func editInfoMessage(unitId: String, messageId: String, text: String) async -> ApiResult<InfoMessage> {
        .ok(message(messageId, text, hoursAgo: 0, own: true, edited: true))
    }

    func deleteInfoMessage(unitId: String, messageId: String) async -> ApiResult<Void> { .ok(()) }
    func markInfoRead(unitId: String) async -> ApiResult<Void> { .ok(()) }
}

#Preview("Infokanal Schreibende, Nacht") {
    InfoChannelRootView(model: InfoChannelsModel(service: PreviewInfoService(canWrite: true))).preferredColorScheme(.dark)
}
#Preview("Infokanal Lesende, Tag, AX3") {
    InfoChannelRootView(model: InfoChannelsModel(service: PreviewInfoService(canWrite: false))).preferredColorScheme(.light)
        .dynamicTypeSize(.accessibility3)
}
#endif
