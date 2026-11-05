import PhotosUI
import SwiftUI

/// Avatar mit Kamera-Knopf, Name, Rolle und Benutzername. Nur das Profilbild lässt sich ändern.
struct ProfileHeader: View {
    let profile: Profile
    @Environment(AppModel.self) private var model
    @State private var imageData: Data?
    @State private var pickerShown = false
    @State private var picked: PhotosPickerItem?
    @State private var failed = false
    @State private var busy = false

    var body: some View {
        VStack(spacing: Spacing.s3) {
            Avatar(initials: initials, size: .profile, imageData: imageData)
                .overlay(alignment: .bottomTrailing) { cameraMenu.offset(x: 14, y: 14) }
                .padding(.bottom, Spacing.s2)
            VStack(spacing: Spacing.s1) {
                Text(verbatim: profile.name).font(.frTitle2).foregroundStyle(Color.frOnSurface)
                    .multilineTextAlignment(.center)
                Text(role).font(.subheadline).foregroundStyle(Color.frOnSurfaceVariant).multilineTextAlignment(.center)
                Text(verbatim: profile.username).font(.subheadline).foregroundStyle(Color.frOnSurfaceVariant)
            }
            .accessibilityElement(children: .combine)
            if failed {
                Notice(.error, title: "Das Profilbild konnte nicht gespeichert werden.", message: "Prüfe dein Internet und versuche es nochmals.")
            }
        }
        .frame(maxWidth: .infinity)
        .photosPicker(isPresented: $pickerShown, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { await upload(item) }
        }
        .task(id: profile.imagePath) { await loadImage() }
    }

    private var cameraMenu: some View {
        Menu {
            Button("Foto auswählen", systemImage: "photo") { pickerShown = true }
            if profile.imagePath != nil {
                Button("Bild entfernen", systemImage: "trash", role: .destructive) { Task { await remove() } }
            }
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.frOnPrimary)
                .frame(width: Sizes.touchTarget, height: Sizes.touchTarget)
                .background(Color.frPrimary, in: .circle)
                .overlay(Circle().stroke(Color.frSurface, lineWidth: 2))
        }
        .disabled(busy)
        .accessibilityLabel(Text("Profilbild ändern"))
    }

    private var initials: String {
        String(profile.name.split(separator: " ").prefix(2).compactMap(\.first))
    }

    private var role: LocalizedStringResource {
        if let unit = profile.units.first {
            switch unit.role {
            case "kommandant": return "Kommandant"
            case "stellvertretung": return "Stellvertretung"
            default: return "Leitung"
            }
        }
        if profile.participants.contains(where: { $0.kind == "eltern" }) { return "Elternteil" }
        return "Teilnehmende Person"
    }

    private func loadImage() async {
        guard let path = profile.imagePath else { imageData = nil; return }
        if case .ok(let data) = await model.api.personImage(path: path) { imageData = data }
    }

    private func upload(_ item: PhotosPickerItem) async {
        busy = true
        failed = false
        defer { busy = false }
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let jpeg = await Task.detached(operation: { ProfileImageResizer.jpeg(from: raw) }).value,
              case .ok = await model.api.setMyImage(jpeg)
        else { failed = true; return }
        await refresh()
    }

    private func remove() async {
        busy = true
        failed = false
        defer { busy = false }
        guard case .ok = await model.api.deleteMyImage() else { failed = true; return }
        await refresh()
    }

    private func refresh() async {
        if case .ok(let fresh) = await model.api.me() {
            model.profile = fresh
            // Bleibt der Pfad gleich, löst `task(id:)` nicht aus: dann direkt neu laden.
            if fresh.imagePath == profile.imagePath { await loadImage() }
        } else {
            failed = true
        }
    }
}
