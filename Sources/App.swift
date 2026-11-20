import SwiftUI

@main
struct DockOrganizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DockStore.shared

    var body: some Scene {
        Window("Dock Organizer", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("Dock Organizer", systemImage: "dock.rectangle") {
            MenuBarContent().environmentObject(store)
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: DockStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.profiles.isEmpty {
            Text("Keine Profile")
        } else {
            Section("Profil anwenden") {
                ForEach(store.profiles) { p in
                    Button {
                        store.applyProfile(p)
                    } label: {
                        if store.activeProfileID == p.id {
                            Label(p.name, systemImage: "checkmark")
                        } else {
                            Text(p.name)
                        }
                    }
                }
            }
        }
        if let active = store.activeProfile, !active.locked {
            Button("Aktuelles Dock in „\(active.name)“ speichern") { store.saveRealDock(into: active.id) }
        }
        Divider()
        Toggle("Dock automatisch ausblenden", isOn: Binding(
            get: { store.settings.autohide },
            set: { store.setAutohideNow($0) }
        ))
        Button("Neuer Dock-Ordner …") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            store.requestNewFolder(with: [])
        }
        Button("Dock neu starten") { DockPrefs.restartDock() }
        Divider()
        Button("Dock Organizer öffnen …") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")
        Button("Beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
