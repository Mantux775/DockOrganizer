import AppKit

/// „Profile“-Stapel im Dock: ein Ordner mit einer .dockprofile-Datei pro Profil.
/// Klick auf eine Datei öffnet sie mit dem Dock Organizer → Profil wird angewendet.
extension DockStore {
    static var switcherFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DockOrganizer/Profile", isDirectory: true)
    }

    var switcherEnabled: Bool { UserDefaults.standard.bool(forKey: "switcherEnabled") }

    func setSwitcherEnabled(_ on: Bool) {
        objectWillChange.send()
        UserDefaults.standard.set(on, forKey: "switcherEnabled")
        syncSwitcherFiles()
        apply(message: on ? "„Profile“-Stapel zum Dock hinzugefügt" : "„Profile“-Stapel entfernt")
    }

    private func isSwitcherTile(_ item: DockItem) -> Bool {
        guard let url = item.url else { return false }
        return url.standardizedFileURL.path == Self.switcherFolder.standardizedFileURL.path
    }

    /// Stapel beim Schreiben ergänzen bzw. entfernen – unabhängig vom jeweiligen Profil.
    func othersForWriting() -> [DockItem] {
        var result = others.filter { !isSwitcherTile($0) }
        if switcherEnabled {
            var tile = DockItem.folder(Self.switcherFolder)
            tile.setTileValue("file-label", "Profile")
            tile.setTileValue("displayas", 0)   // Stapel
            tile.setTileValue("showas", 3)      // Liste
            if let existing = others.first(where: isSwitcherTile) { tile = existing }
            result.insert(tile, at: 0)
        }
        return result
    }

    /// Dateien im Stapel an die Profile anpassen.
    func syncSwitcherFiles() {
        let fm = FileManager.default
        let dir = Self.switcherFolder
        guard switcherEnabled else {
            try? fm.removeItem(at: dir)
            return
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let existing = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var wanted = Set<String>()
        let icon = NSApp?.applicationIconImage

        for p in profiles {
            let safe = p.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let fileName = (activeProfileID == p.id ? "✓ " : "") + safe + ".dockprofile"
            wanted.insert(fileName)
            let url = dir.appendingPathComponent(fileName)
            let current = try? String(contentsOf: url, encoding: .utf8)
            if current != p.id.uuidString {
                try? p.id.uuidString.write(to: url, atomically: true, encoding: .utf8)
                if let icon { NSWorkspace.shared.setIcon(icon, forFile: url.path) }
            }
        }
        for url in existing where !wanted.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }

    func applyProfile(fromSwitcherFile url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let id = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let p = profiles.first(where: { $0.id == id })
        else { return }
        if p.id == activeProfileID && !hasChanges { return }
        applyProfile(p)
    }
}
