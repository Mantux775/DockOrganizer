import AppKit
import UniformTypeIdentifiers

@MainActor
final class DockStore: ObservableObject {
    static let shared = DockStore()

    @Published var apps: [DockItem] = [] { didSet { track() } }
    @Published var others: [DockItem] = [] { didSet { track() } }
    @Published var settings = DockSettings() { didSet { if settings != oldValue { track() } } }
    @Published var profiles: [DockProfile] = []
    @Published var hasChanges = false
    @Published var activeProfileID: UUID? {
        didSet {
            UserDefaults.standard.set(activeProfileID?.uuidString, forKey: "activeProfile")
            syncSwitcherFiles()
        }
    }

    /// Auswahl im Editor (geteilt, damit Kontextmenüs mehrere Einträge kennen)
    @Published var selection = Set<DockItem.ID>()
    /// Gesetzt → Sheet „Neuer Ordner“ wird angezeigt
    @Published var folderRequest: FolderRequest?
    /// Kurze Rückmeldung unten im Fenster
    @Published var toast: Toast?

    private var tracking = true

    init() {
        activeProfileID = UserDefaults.standard.string(forKey: "activeProfile").flatMap(UUID.init(uuidString:))
        reload()
        loadProfiles()
        if profiles.isEmpty {
            let p = saveProfile(name: "Original (Backup)")
            setLocked(p.id, true)
        }
    }

    private func track() { if tracking && !hasChanges { hasChanges = true } }

    private func untracked(_ f: () -> Void) {
        tracking = false
        f()
        tracking = true
    }

    // MARK: - Dock lesen / schreiben

    func reload() {
        DockPrefs.sync()
        untracked {
            apps = (DockPrefs.get("persistent-apps") as? [[String: Any]] ?? []).map { DockItem(raw: $0) }
            others = (DockPrefs.get("persistent-others") as? [[String: Any]] ?? []).map { DockItem(raw: $0) }
            settings = DockSettings.current()
        }
        hasChanges = false
    }

    var activeProfile: DockProfile? { profiles.first { $0.id == activeProfileID } }

    /// Wird beim Anwenden in dieses Profil gespeichert?
    var savesIntoActiveProfile: Bool { activeProfile.map { !$0.locked } ?? false }

    func showToast(_ text: String, error: Bool = false) {
        let t = Toast(text: text, isError: error)
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }

    func apply(message: String? = nil) {
        if savesIntoActiveProfile, let id = activeProfileID { updateProfile(id) }
        let expectedApps = apps.count, expectedOthers = others.count
        let msg = message ?? (savesIntoActiveProfile ? "Dock aktualisiert · gespeichert in „\(activeProfile!.name)“" : "Dock aktualisiert")
        DockPrefs.set("persistent-apps", apps.map(\.raw))
        DockPrefs.set("persistent-others", othersForWriting().map(\.raw))
        for (k, v) in settings.dict { DockPrefs.set(k, v) }
        DockPrefs.sync()
        DockPrefs.restartDock()
        hasChanges = false
        // Das Dock schreibt nach dem Neustart GUIDs etc. zurück → danach neu einlesen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, !self.hasChanges else { return }
            self.reload()
            if self.apps.count == expectedApps && self.others.count == expectedOthers {
                self.showToast(msg)
            } else {
                self.showToast("Das Dock hat die Änderung nicht vollständig übernommen – bitte erneut anwenden.", error: true)
            }
        }
    }

    func setAutohideNow(_ on: Bool) {
        untracked { settings.autohide = on }
        DockPrefs.set("autohide", on)
        DockPrefs.sync()
        DockPrefs.restartDock()
    }

    // MARK: - Bearbeiten

    func add(urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if url.pathExtension == "app" {
                guard !apps.contains(where: { $0.url?.standardizedFileURL.path == url.standardizedFileURL.path }) else { continue }
                apps.append(.app(url))
            } else if isDir.boolValue {
                others.append(.folder(url))
            } else {
                others.append(.document(url))
            }
        }
    }

    func pickApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Hinzufügen"
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func pickFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Hinzufügen"
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func addSpacer(small: Bool, after id: DockItem.ID? = nil) {
        let s = DockItem.spacer(small: small)
        if let id, let i = apps.firstIndex(where: { $0.id == id }) {
            apps.insert(s, at: i + 1)
        } else if let id, let i = others.firstIndex(where: { $0.id == id }) {
            others.insert(s, at: i + 1)
        } else {
            apps.append(s)
        }
    }

    func remove(ids: Set<DockItem.ID>) {
        guard !ids.isEmpty else { return }
        apps.removeAll { ids.contains($0.id) }
        others.removeAll { ids.contains($0.id) }
    }

    func update(_ id: DockItem.ID, _ change: (inout DockItem) -> Void) {
        if let i = apps.firstIndex(where: { $0.id == id }) { change(&apps[i]) }
        else if let i = others.firstIndex(where: { $0.id == id }) { change(&others[i]) }
    }

    /// Sortiert alphabetisch – aber nur innerhalb der durch Abstände getrennten Gruppen.
    func sortAlphabetically() {
        func sortGroups(_ items: [DockItem]) -> [DockItem] {
            var result: [DockItem] = [], group: [DockItem] = []
            let sorter: (DockItem, DockItem) -> Bool = { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            for item in items {
                if item.isSpacer {
                    result += group.sorted(by: sorter); result.append(item); group = []
                } else {
                    group.append(item)
                }
            }
            return result + group.sorted(by: sorter)
        }
        apps = sortGroups(apps)
        others = sortGroups(others)
    }

    func removeDuplicates() {
        func dedupe(_ items: [DockItem]) -> [DockItem] {
            var seen = Set<String>()
            return items.filter { item in
                guard let p = item.url?.standardizedFileURL.absoluteString else { return true }
                return seen.insert(p).inserted
            }
        }
        apps = dedupe(apps)
        others = dedupe(others)
    }

    func removeMissing() {
        apps.removeAll(where: \.isMissing)
        others.removeAll(where: \.isMissing)
    }

    func removeSpacers() {
        apps.removeAll(where: \.isSpacer)
        others.removeAll(where: \.isSpacer)
    }

    var missingCount: Int { (apps + others).filter(\.isMissing).count }

    // MARK: - Profile

    private var profilesURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DockOrganizer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.plist")
    }

    private func loadProfiles() {
        guard let data = try? Data(contentsOf: profilesURL),
              let arr = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]
        else { return }
        profiles = arr.compactMap(DockProfile.init(plist:))
    }

    private func saveProfiles() {
        if let data = try? PropertyListSerialization.data(fromPropertyList: profiles.map(\.plist), format: .binary, options: 0) {
            try? data.write(to: profilesURL, options: .atomic)
        }
        syncSwitcherFiles()
    }

    @discardableResult
    func saveProfile(name: String) -> DockProfile {
        let p = DockProfile(name: name, apps: apps, others: others, settings: settings)
        profiles.append(p)
        saveProfiles()
        activeProfileID = p.id
        return p
    }

    func updateProfile(_ id: UUID) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].apps = apps
        profiles[i].others = others
        profiles[i].settings = settings
        saveProfiles()
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].name = name
        saveProfiles()
    }

    func duplicateProfile(_ id: UUID) -> DockProfile? {
        guard let p = profiles.first(where: { $0.id == id }) else { return nil }
        var copy = DockProfile(name: p.name + " Kopie", apps: p.apps, others: p.others, settings: p.settings)
        copy.created = Date()
        profiles.append(copy)
        saveProfiles()
        return copy
    }

    func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = nil }
        saveProfiles()
    }

    // MARK: Echtes Dock (so wie es gerade auf dem Bildschirm ist) ins Profil übernehmen

    private func realDockSnapshot() -> (apps: [DockItem], others: [DockItem], settings: DockSettings) {
        DockPrefs.sync()
        return ((DockPrefs.get("persistent-apps") as? [[String: Any]] ?? []).map { DockItem(raw: $0) },
                (DockPrefs.get("persistent-others") as? [[String: Any]] ?? []).map { DockItem(raw: $0) },
                DockSettings.current())
    }

    func saveRealDock(into id: UUID) {
        guard let i = profiles.firstIndex(where: { $0.id == id }), !profiles[i].locked else { return }
        let snap = realDockSnapshot()
        profiles[i].apps = snap.apps
        profiles[i].others = snap.others
        profiles[i].settings = snap.settings
        saveProfiles()
        activeProfileID = id
        if !hasChanges { reload() }
        showToast("Aktuelles Dock in „\(profiles[i].name)“ gespeichert")
    }

    func saveRealDockAsNewProfile(name: String) {
        let snap = realDockSnapshot()
        let p = DockProfile(name: name, apps: snap.apps, others: snap.others, settings: snap.settings)
        profiles.append(p)
        saveProfiles()
        activeProfileID = p.id
        if !hasChanges { reload() }
        showToast("Profil „\(name)“ angelegt")
    }

    func moveProfiles(from: IndexSet, to: Int) {
        profiles.move(fromOffsets: from, toOffset: to)
        saveProfiles()
    }

    func loadIntoEditor(_ p: DockProfile) {
        apps = p.apps.map { DockItem(raw: $0.raw) }
        others = p.others.map { DockItem(raw: $0.raw) }
        if let s = p.settings { settings = s }
    }

    func applyProfile(_ p: DockProfile) {
        loadIntoEditor(p)
        activeProfileID = p.id
        apply(message: "Profil „\(p.name)“ angewendet")
    }

    func setLocked(_ id: UUID, _ locked: Bool) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].locked = locked
        saveProfiles()
    }

    func exportProfile(_ id: UUID) {
        guard let p = profiles.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.propertyList]
        panel.nameFieldStringValue = "\(p.name).plist"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? PropertyListSerialization.data(fromPropertyList: p.plist, format: .xml, options: 0)
        else { return }
        try? data.write(to: url)
    }

    @discardableResult
    func importProfile() -> DockProfile? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let d = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              var p = DockProfile(plist: d)
        else { return nil }
        p.id = UUID()
        p.locked = false
        profiles.append(p)
        saveProfiles()
        return p
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}
