import SwiftUI

// MARK: - Alle installierten Apps

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    let name: String
    var id: String { url.path }
}

@MainActor
final class AppLibrary: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var isLoading = false

    func scan() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let found = Self.findApps()
            await MainActor.run {
                self.apps = found
                self.isLoading = false
            }
        }
    }

    nonisolated private static func findApps() -> [InstalledApp] {
        let fm = FileManager.default
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications",
                     "/System/Applications/Utilities", fm.homeDirectoryForCurrentUser.path + "/Applications"]
        var seen = Set<String>(), result: [InstalledApp] = []

        func add(_ url: URL) {
            let key = url.lastPathComponent.lowercased()
            guard seen.insert(key).inserted else { return }
            let name = fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            result.append(InstalledApp(url: url, name: name))
        }

        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: root),
                                                          includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else { continue }
            for item in items {
                if item.pathExtension == "app" {
                    add(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                          item.lastPathComponent != "Utilities" {
                    // eine Ebene tiefer (z. B. „Adobe Photoshop/“, „Microsoft Office/“)
                    for sub in (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles])) ?? []
                    where sub.pathExtension == "app" { add(sub) }
                }
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Seitenleiste „Apps hinzufügen“

struct AppLibraryView: View {
    @EnvironmentObject var store: DockStore
    @StateObject private var library = AppLibrary()
    @State private var search = ""
    @State private var hideInDock = false

    private var dockPaths: Set<String> {
        Set(store.apps.compactMap { $0.url?.standardizedFileURL.path })
    }

    private var filtered: [InstalledApp] {
        let inDock = dockPaths
        return library.apps.filter { app in
            (search.isEmpty || app.name.localizedCaseInsensitiveContains(search))
                && (!hideInDock || !inDock.contains(app.url.standardizedFileURL.path))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("App suchen", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.6)))

                Toggle("Nur Apps, die nicht im Dock sind", isOn: $hideInDock)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)

            Divider()

            if library.isLoading && library.apps.isEmpty {
                ProgressView().frame(maxHeight: .infinity)
            } else {
                let inDock = dockPaths
                List(filtered) { app in
                    LibraryRow(app: app, inDock: inDock.contains(app.url.standardizedFileURL.path))
                }
                .listStyle(.plain)
            }

            Divider()
            Text("Klick auf ＋ fügt hinzu · oder in die Liste ziehen")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(6)
        }
        .onAppear { if library.apps.isEmpty { library.scan() } }
    }
}

private struct LibraryRow: View {
    @EnvironmentObject var store: DockStore
    let app: InstalledApp
    let inDock: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 26, height: 26)
            Text(app.name).lineLimit(1)
            Spacer()
            if inDock {
                Button {
                    let path = app.url.standardizedFileURL.path
                    store.apps.removeAll { $0.url?.standardizedFileURL.path == path }
                } label: {
                    Image(systemName: hovering ? "minus.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(hovering ? Color.red : Color.green)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Ist im Dock – klicken zum Entfernen")
            } else {
                Button {
                    store.add(urls: [app.url])
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Zum Dock hinzufügen")
            }
        }
        .padding(.vertical, 2)
        .padding(.trailing, 14) // Abstand zum Scrollbalken
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if !inDock { store.add(urls: [app.url]) } }
        .draggable(app.url) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 48, height: 48)
        }
    }
}
