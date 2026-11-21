import Contacts
import EventKit
import SwiftUI

struct FolderHoverList: View {
    let folder: String
    let count: Int
    @State private var entries: [URL] = []
    @State private var loading = true
    @State private var error: String?

    private var folderURL: URL { URL(fileURLWithPath: folder, isDirectory: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                Text(folderURL.lastPathComponent).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(entries.count)/\(count)").font(.caption).foregroundStyle(Theme.secondary)
                Button {
                    NSWorkspace.shared.open(folderURL)
                } label: {
                    Image(systemName: "arrow.up.forward")
                }
                .buttonStyle(.plain)
                .help("Ordner im Finder öffnen")
            }
            .padding(.horizontal, 12)

            if loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
                    .padding(.horizontal, 12)
            } else if entries.isEmpty {
                Text("Der Ordner ist leer.").font(.caption).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entries, id: \.path) { url in
                            Button {
                                NSWorkspace.shared.open(url)
                                HoverPanel.shared.close()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(nsImage: fileIcon(url.path)).resizable().frame(width: 20, height: 20)
                                    Text(url.lastPathComponent).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: url.hasDirectoryPath ? "folder" : "arrow.up.forward")
                                        .font(.caption2).foregroundStyle(Theme.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(.vertical, 8)
        .onAppear(perform: load)
    }

    private func load() {
        let limit = min(max(count, 1), 50)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                let sorted = urls.sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
                DispatchQueue.main.async {
                    entries = Array(sorted.prefix(limit))
                    error = nil
                    loading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    entries = []
                    loading = false
                }
            }
        }
    }
}

struct FinderHoverList: View {
    let w: WidgetInstance
    @State private var recent: [URL] = []

    private var recentLimit: Int { min(max(Int(w.cfg("fileCount", "10")) ?? 10, 1), 50) }

    private var defaultFolders: [(String, String, String)] {
        [
            ("Benutzerordner", NSHomeDirectory(), "house"),
            ("Schreibtisch", NSHomeDirectory() + "/Desktop", "menubar.dock.rectangle"),
            ("Dokumente", NSHomeDirectory() + "/Documents", "doc"),
            ("Downloads", NSHomeDirectory() + "/Downloads", "arrow.down.circle"),
            ("Programme", "/Applications", "square.grid.2x2"),
        ]
    }

    private var favoriteFolders: [String] {
        w.cfg("favorites").split(separator: "\n").map { ($0 as NSString).expandingTildeInPath }
            .filter { path in
                var isDirectory = ObjCBool(false)
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app"))
                    .resizable().frame(width: 24, height: 24)
                Text("Finder").font(.headline)
                Spacer()
                Button("Öffnen") { open(NSHomeDirectory()) }.controlSize(.small)
                Button {
                    addFavoriteFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .help("Favoriten-Verzeichnis hinzufügen")
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("ORDNER").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                ForEach(defaultFolders, id: \.1) { name, path, symbol in
                    Button { open(path) } label: {
                        Label(name, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            if !favoriteFolders.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FAVORITEN").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                    ForEach(favoriteFolders, id: \.self) { path in
                        HStack {
                            Button { open(path) } label: {
                                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "star")
                                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Button {
                                removeFavoriteFolder(path)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                            .help("Aus Favoriten entfernen")
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            if !recent.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("ZULETZT GEÖFFNET").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                    ForEach(recent.prefix(recentLimit), id: \.self) { url in
                        Button { NSWorkspace.shared.open(url); HoverPanel.shared.close() } label: {
                            Label(url.lastPathComponent, systemImage: "doc")
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = AppLauncher.recentDocuments(bundleID: "com.apple.finder", limit: recentLimit)
                DispatchQueue.main.async { recent = result }
            }
        }
    }

    private func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
        HoverPanel.shared.close()
    }

    private func addFavoriteFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let paths = favoriteFolders + (favoriteFolders.contains(url.path) ? [] : [url.path])
        DockStore.shared.setConfig(w.id, "favorites", paths.joined(separator: "\n"))
    }

    private func removeFavoriteFolder(_ path: String) {
        DockStore.shared.setConfig(w.id, "favorites", favoriteFolders.filter { $0 != path }.joined(separator: "\n"))
    }
}

private struct MailPreview: Identifiable {
    let id = UUID()
    let subject: String
    let sender: String
    let received: String
}

struct MailHoverList: View {
    let count: Int
    let filter: String
    @State private var messages: [MailPreview] = []
    @State private var loading = true
    @State private var error: String?

    private var limit: Int { min(max(count, 1), 50) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Letzte \(limit) Mails", systemImage: "envelope")
                    .font(.headline)
                Spacer()
                Button("Mail öffnen") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mail.app"))
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)

            if loading {
                ProgressView().controlSize(.small).padding(.horizontal, 12)
            } else if let error {
                Text(error).font(.callout).foregroundStyle(Theme.secondary).padding(.horizontal, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(messages) { message in
                            Button {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mail.app"))
                                HoverPanel.shared.close()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(message.subject.isEmpty ? "(Ohne Betreff)" : message.subject)
                                        .font(.callout.weight(.medium)).lineLimit(1)
                                    HStack {
                                        Text(message.sender).lineLimit(1)
                                        Spacer()
                                        Text(message.received).lineLimit(1)
                                    }
                                    .font(.caption).foregroundStyle(Theme.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        loading = true
        error = nil
        if filter == "known" {
            loadKnownContactEmails { emails, failure in
                guard let emails else {
                    error = failure ?? "Kontakte konnten nicht geladen werden."
                    loading = false
                    return
                }
                fetchMessages(knownEmails: emails)
            }
        } else {
            fetchMessages(knownEmails: nil)
        }
    }

    private func fetchMessages(knownEmails: Set<String>?) {
        let scanLimit = filter == "known" ? min(max(limit * 10, 100), 500) : limit
        let source = """
        tell application "Mail"
            set sourceMessages to messages of inbox
            if "\(filter)" is "unread" then
                set sourceMessages to (messages of inbox whose read status is false)
            end if
            set amount to count of sourceMessages
            if amount > \(scanLimit) then set amount to \(scanLimit)
            set separator to character id 31
            set rowSeparator to character id 30
            set output to ""
            repeat with i from 1 to amount
                set m to item i of sourceMessages
                set output to output & (subject of m as text) & separator & (sender of m as text) & separator & ((date received of m) as text) & rowSeparator
            end repeat
            return output
        end tell
        """
        Script.run(source) { result in
            guard let raw = result?.stringValue else {
                error = "Mail-Verlauf konnte nicht geladen werden. Mail-Zugriff prüfen."
                loading = false
                return
            }
            messages = raw.split(separator: "\u{1e}", omittingEmptySubsequences: true).compactMap { row in
                let fields = row.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false)
                guard fields.count == 3 else { return nil }
                return MailPreview(subject: String(fields[0]), sender: String(fields[1]), received: String(fields[2]))
            }
            if let knownEmails {
                messages = messages.filter { message in
                    Self.emailAddresses(in: message.sender).contains { knownEmails.contains($0) }
                }
            }
            messages = Array(messages.prefix(limit))
            error = messages.isEmpty ? emptyMessage : nil
            loading = false
        }
    }

    private var emptyMessage: String {
        switch filter {
        case "unread": "Keine ungelesenen Mails."
        case "known": "Keine Mails von bekannten Kontakten."
        default: "Im Posteingang sind keine Mails."
        }
    }

    private static func emailAddresses(in sender: String) -> [String] {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(sender.startIndex..<sender.endIndex, in: sender)
        return regex.matches(in: sender, range: range).compactMap {
            guard let match = Range($0.range, in: sender) else { return nil }
            return String(sender[match]).lowercased()
        }
    }

    private func loadKnownContactEmails(completion: @escaping (Set<String>?, String?) -> Void) {
        let store = CNContactStore()
        let fetch: () -> Void = {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor])
                    var emails = Set<String>()
                    try store.enumerateContacts(with: request) { contact, _ in
                        emails.formUnion(contact.emailAddresses.map { String($0.value).lowercased() })
                    }
                    DispatchQueue.main.async { completion(emails, nil) }
                } catch {
                    DispatchQueue.main.async { completion(nil, error.localizedDescription) }
                }
            }
        }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized {
            fetch()
        } else if status == .notDetermined {
            store.requestAccess(for: .contacts) { granted, error in
                if granted {
                    fetch()
                } else {
                    DispatchQueue.main.async {
                        completion(nil, error?.localizedDescription ?? "Zugriff auf Kontakte wurde verweigert.")
                    }
                }
            }
        } else {
            completion(nil, "Kontakte-Zugriff in den Systemeinstellungen erlauben.")
        }
    }
}

// MARK: - Calendar list

struct CalendarHoverList: View {
    @ObservedObject private var ek = EventStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Nächste Termine", systemImage: "calendar").font(.headline).padding(.horizontal, 12)
            if !ek.eventsAuthorized {
                Button("Kalender erlauben") { ek.requestEvents() }.padding(.horizontal, 12)
            } else if ek.upcoming.isEmpty {
                Text("Keine Termine in den nächsten 7 Tagen").foregroundStyle(Theme.secondary).padding(.horizontal, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groups, id: \.0) { day, events in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dayTitle(day)).font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                                ForEach(events, id: \.calendarItemIdentifier) { e in row(e) }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { ek.loadUpcoming() }
    }

    private var groups: [(Date, [EKEvent])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: ek.upcoming.prefix(30)) { cal.startOfDay(for: max($0.startDate, Date())) }
        return dict.keys.sorted().map { ($0, dict[$0]!) }
    }

    private func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "HEUTE" }
        if cal.isDateInTomorrow(d) { return "MORGEN" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguageSettings.shared.locale)).uppercased()
    }

    private func row(_ e: EKEvent) -> some View {
        let f = Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguageSettings.shared.locale)
        return Button {
            open(e)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: e.calendar.color)).frame(width: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.title ?? "").font(.callout.weight(.semibold)).lineLimit(2)
                    Text(e.isAllDay ? "Ganztägig" : "\(e.startDate.formatted(f)) – \(e.endDate.formatted(f))")
                        .font(.caption).foregroundStyle(Theme.secondary)
                    if let loc = e.location, !loc.isEmpty {
                        Text(loc).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ e: EKEvent) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: e.startDate)
        Script.run("""
        tell application "Calendar"
            activate
            switch view to day view
            set d to current date
            set day of d to 1
            set year of d to \(c.year ?? 2026)
            set month of d to \(c.month ?? 1)
            set day of d to \(c.day ?? 1)
            view calendar at d
        end tell
        """)
        HoverPanel.shared.close()
    }
}

// MARK: - Reminders list

struct RemindersHoverList: View {
    @ObservedObject private var ek = EventStore.shared
    let list: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Erinnerungen", systemImage: "checklist").font(.headline)
                Spacer()
                Text("\(ek.reminders.count) offen").font(.caption).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 12)
            if !ek.remindersAuthorized {
                Button("Erinnerungen erlauben") { ek.requestReminders(list: list) }.padding(.horizontal, 12)
            } else if ek.reminders.isEmpty {
                Text("Alles erledigt ✓").foregroundStyle(Theme.secondary).padding(.horizontal, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(ek.reminders.prefix(25), id: \.calendarItemIdentifier) { r in
                            HStack(alignment: .top, spacing: 8) {
                                Button { withAnimation { ek.complete(r) } } label: {
                                    Circle().strokeBorder(Color(nsColor: r.calendar.color), lineWidth: 1.6)
                                        .frame(width: 15, height: 15)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Erledigt")
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        if r.priority == 1 { Text("!").foregroundStyle(.orange).bold() }
                                        Text(r.title ?? "").font(.callout).lineLimit(2)
                                    }
                                    HStack(spacing: 6) {
                                        if let due = r.dueDateComponents?.date {
                                            Text(dueText(due)).foregroundStyle(due < Date() ? .orange : Theme.secondary)
                                        }
                                        Text(r.calendar.title).foregroundStyle(Theme.secondary)
                                    }
                                    .font(.caption)
                                }
                                Spacer(minLength: 0)
                            }
                            .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
                HoverPanel.shared.close()
            } label: { Label("Erinnerungen öffnen", systemImage: "arrow.up.forward.app") }
                .buttonStyle(.link).padding(.horizontal, 12)
        }
        .onAppear { ek.requestReminders(list: list) }
    }

    private func dueText(_ d: Date) -> String {
        let cal = Calendar.current
        if d < Date() && !cal.isDateInToday(d) { return "Überfällig" }
        if cal.isDateInToday(d) { return "Heute \(d.formatted(date: .omitted, time: .shortened))" }
        if cal.isDateInTomorrow(d) { return "Morgen" }
        return d.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguageSettings.shared.locale))
    }
}

// MARK: - Apple Notes

struct NoteRef: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var modified: Date
}

final class NotesLibrary: ObservableObject {
    static let shared = NotesLibrary()

    @Published private(set) var notes: [NoteRef] = []
    @Published private(set) var pinned: [String] = []
    @Published private(set) var usage: [String: Int] = [:]
    @Published private(set) var loading = false
    private var lastLoad = Date.distantPast
    private let d = UserDefaults.standard

    private init() {
        if let data = d.data(forKey: "notes.cache"), let n = try? JSONDecoder().decode([NoteRef].self, from: data) { notes = n }
        pinned = d.stringArray(forKey: "notes.pinned") ?? []
        usage = d.dictionary(forKey: "notes.usage") as? [String: Int] ?? [:]
    }

    var isNotesRunning: Bool { Script.isRunning("com.apple.Notes") }

    /// Reads id, title and modification date of all notes (only when Notes runs, unless forced).
    func refresh(force: Bool = false) {
        guard force || isNotesRunning, !loading else { return }
        guard force || Date().timeIntervalSince(lastLoad) > 120 else { return }
        loading = true
        let src = """
        tell application "Notes"
            set theIDs to id of every note
            set theNames to name of every note
            set theDates to modification date of every note
            return {theIDs, theNames, theDates}
        end tell
        """
        Script.run(src) { [weak self] r in
            guard let self else { return }
            self.loading = false
            self.lastLoad = Date()
            guard let r, r.numberOfItems == 3,
                  let ids = r.atIndex(1), let names = r.atIndex(2), let dates = r.atIndex(3) else { return }
            var out: [NoteRef] = []
            let n = ids.numberOfItems
            if n > 0 {
                for i in 1...n {
                    guard let id = ids.atIndex(i)?.stringValue else { continue }
                    out.append(NoteRef(id: id, title: names.atIndex(i)?.stringValue ?? "Notiz",
                                       modified: dates.atIndex(i)?.dateValue ?? .distantPast))
                }
            }
            self.notes = out
            if let data = try? JSONEncoder().encode(out) { self.d.set(data, forKey: "notes.cache") }
        }
    }

    var pinnedNotes: [NoteRef] { pinned.compactMap { id in notes.first { $0.id == id } } }

    /// Most used: opened most often from the dock, then most recently edited.
    func mostUsed(limit: Int = 8) -> [NoteRef] {
        notes.filter { !pinned.contains($0.id) }
            .sorted { a, b in
                let ua = usage[a.id] ?? 0, ub = usage[b.id] ?? 0
                return ua != ub ? ua > ub : a.modified > b.modified
            }
            .prefix(limit).map { $0 }
    }

    func togglePin(_ n: NoteRef) {
        if let i = pinned.firstIndex(of: n.id) { pinned.remove(at: i) } else { pinned.insert(n.id, at: 0) }
        d.set(pinned, forKey: "notes.pinned")
    }

    func open(_ n: NoteRef) {
        usage[n.id, default: 0] += 1
        d.set(usage, forKey: "notes.usage")
        Script.run("""
        tell application "Notes"
            show note id \(MusicLibrary.quote(n.id))
            activate
        end tell
        """)
    }

    /// Creates a note in the Notes app; the first line becomes the title.
    func create(_ text: String, completion: @escaping (Bool) -> Void) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { completion(false); return }
        let html = t.components(separatedBy: "\n").map { line in
            "<div>" + (line.isEmpty ? "<br>" : line
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")) + "</div>"
        }.joined()
        Script.run("""
        tell application "Notes"
            set n to make new note with properties {body:\(MusicLibrary.quote(html))}
            return id of n
        end tell
        """) { [weak self] r in
            completion(r != nil)
            if r != nil { self?.refresh(force: true) }
        }
    }
}

struct NotesHoverList: View {
    @ObservedObject private var lib = NotesLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Notizen", systemImage: "note.text").font(.headline)
                Spacer()
                if lib.loading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            if lib.notes.isEmpty {
                Button("Notizen laden") { lib.refresh(force: true) }.padding(.horizontal, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !lib.pinnedNotes.isEmpty {
                            section("ANGEPINNT", lib.pinnedNotes, pinned: true)
                            Divider()
                        }
                        section("MEIST VERWENDET", lib.mostUsed(), pinned: false)
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { lib.refresh() }
    }

    private func section(_ title: String, _ items: [NoteRef], pinned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
            ForEach(items) { n in
                HStack(spacing: 8) {
                    Button {
                        lib.open(n)
                        HoverPanel.shared.close()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: pinned ? "pin.fill" : "note.text").foregroundStyle(pinned ? .orange : .yellow)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(n.title).font(.callout.weight(.medium)).lineLimit(1)
                                Text(n.modified.formatted(.relative(presentation: .named).locale(AppLanguageSettings.shared.locale)))
                                    .font(.caption).foregroundStyle(Theme.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation { lib.togglePin(n) } } label: {
                        Image(systemName: pinned ? "pin.slash" : "pin").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondary)
                    .help(pinned ? "Lösen" : "Oben anpinnen")
                }
            }
        }
    }
}

/// Small editor behind the ＋ of the notes widget.
struct NewNoteEditor: View {
    @Binding var isPresented: Bool
    @State private var text = ""
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Neue Notiz").font(.headline)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(width: 320, height: 160)
                .focused($focused)
            if failed {
                Text("Notiz konnte nicht angelegt werden – Automation für „Notizen“ erlauben.").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Text("Erste Zeile = Titel").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Abbrechen") { isPresented = false }
                Button("In Notizen anlegen") {
                    NotesLibrary.shared.create(text) { ok in
                        if ok { isPresented = false } else { failed = true }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .onAppear { NSApp.activate(ignoringOtherApps: true); focused = true }
    }
}

// MARK: - App launcher: pinned files and recent projects

struct LauncherHoverList: View {
    let w: WidgetInstance
    let app: String
    @ObservedObject private var safari = SafariBookmarks.shared
    @State private var recent: [URL] = []
    @State private var browserHistory: [BrowserVisit] = []
    @State private var browserHistoryError: String?
    @State private var loaded = false
    @State private var question = ""

    private var appPath: String { app }
    private var itemCount: Int { w.fileCount(for: app) }
    private var pinned: [String] { DockStore.shared.instance(w.id)?.pinnedFiles(for: app) ?? w.pinnedFiles(for: app) }
    private var appName: String { FileManager.default.displayName(atPath: appPath).replacingOccurrences(of: ".app", with: "") }
    private var browserBundleID: String? {
        let bundleID = Bundle(path: appPath)?.bundleIdentifier
        return ["com.apple.Safari", "org.mozilla.firefox"].contains(bundleID ?? "") ? bundleID : nil
    }
    private var aiEngine: SearchEngine? {
        switch Bundle(path: appPath)?.bundleIdentifier {
        case SearchEngine.chatGPTID: .chatgpt
        case SearchEngine.claudeID: .claude
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: fileIcon(appPath)).resizable().frame(width: 22, height: 22)
                Text(appName).font(.headline)
                Spacer()
                Button("Öffnen") { AppLauncher.open(app: appPath); HoverPanel.shared.close() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            if let aiEngine {
                HStack(spacing: 8) {
                    TextField("\(aiEngine.label) fragen …", text: $question)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(ask)
                    Button(action: ask) {
                        Image(systemName: "arrow.up.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if !pinned.isEmpty {
                        Text("ANGEHEFTET").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                        ForEach(pinned, id: \.self) { row($0, pinnedRow: true) }
                        Divider()
                    }
                    if let browserBundleID {
                        if browserBundleID == "com.apple.Safari", w.cfg("safariView", "history") == "favorites" {
                            Text("SAFARI-FAVORITEN").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                            if safari.accessDenied {
                                Text("Safari-Lesezeichen brauchen Festplattenvollzugriff.")
                                    .font(.callout).foregroundStyle(Theme.secondary)
                            } else if safari.bar.filter({ !$0.isFolder }).isEmpty {
                                Text("Keine Safari-Favoriten gefunden.").font(.callout).foregroundStyle(Theme.secondary)
                            }
                            ForEach(safari.bar.filter { !$0.isFolder }.prefix(itemCount)) { node in
                                BookmarkMenuItem(node: node)
                            }
                        } else if browserBundleID != "com.apple.Safari" || w.cfg("safariView", "history") != "favorites" {
                            Text(browserBundleID == "com.apple.Safari" ? "SAFARI-VERLAUF" : "FIREFOX-VERLAUF")
                                .font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                            if !loaded {
                                ProgressView().controlSize(.small)
                            } else if browserHistory.isEmpty {
                                Text(browserHistoryError ?? "Kein Browserverlauf gefunden.")
                                    .font(.callout).foregroundStyle(Theme.secondary)
                            }
                            ForEach(browserHistory.prefix(itemCount)) { visit in
                                browserRow(visit)
                            }
                        }
                        Divider()
                    }
                    Text("ZULETZT VERWENDET").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                    if !loaded {
                        ProgressView().controlSize(.small)
                    } else if recent.isEmpty {
                        Text("Keine zuletzt verwendeten Dokumente").font(.callout).foregroundStyle(Theme.secondary)
                    }
                    let pinnedCount = min(pinned.count, itemCount)
                    ForEach(recent.map(\.path).filter { !pinned.contains($0) }.prefix(max(0, itemCount - pinnedCount)), id: \.self) {
                        row($0, pinnedRow: false)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(maxHeight: 400)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let bid = Bundle(path: appPath)?.bundleIdentifier else { loaded = true; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let r = AppLauncher.recentDocuments(bundleID: bid, limit: itemCount)
            let history: (visits: [BrowserVisit], error: String?)?
            if let browserBundleID, browserBundleID != "com.apple.Safari" || w.cfg("safariView", "history") != "favorites" {
                history = BrowserHistory.load(bundleID: browserBundleID, limit: itemCount)
            } else {
                history = nil
            }
            DispatchQueue.main.async {
                recent = r
                browserHistory = history?.visits ?? []
                browserHistoryError = history?.error
                loaded = true
            }
        }
    }

    private func ask() {
        let value = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let aiEngine else { return }
        if aiEngine == .chatgpt { SearchEngine.askChatGPT(value) }
        else { SearchEngine.askClaude(value) }
        question = ""
    }

    private func browserRow(_ visit: BrowserVisit) -> some View {
        Button {
            NSWorkspace.shared.open(visit.url)
            HoverPanel.shared.close()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(visit.title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(visit.url.host ?? visit.url.absoluteString)
                        .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(visit.visitedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(Theme.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ path: String, pinnedRow: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                AppLauncher.open(app: appPath, files: [path])
                HoverPanel.shared.close()
            } label: {
                HStack(spacing: 8) {
                    Image(nsImage: fileIcon(path)).resizable().frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text((path as NSString).lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                        Text((path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                var l = pinned
                if pinnedRow { l.removeAll { $0 == path } } else if !l.contains(path) { l.append(path) }
                setPinnedList(l)
            } label: { Image(systemName: pinnedRow ? "pin.slash" : "pin").font(.caption) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .help(pinnedRow ? "Lösen" : "Anheften")
        }
    }

    private func setPinnedList(_ l: [String]) { LauncherStore.setPinned(w.id, app: app, l) }
}


// MARK: - Workspace: apps, windows and files

struct WorkspaceHoverList: View {
    let id: UUID
    let shortcut: String?
    @ObservedObject private var mgr = WorkspaceManager.shared

    var body: some View {
        if let ws = mgr.workspaces.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: ws.symbol).font(.title3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ws.name).font(.headline)
                        Text("\(ws.apps.count) Apps · andere: \(ws.others.label)" + (shortcut.map { " · \($0)" } ?? ""))
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button {
                        mgr.apply(ws)
                        HoverPanel.shared.close()
                    } label: { Label("Wiederherstellen", systemImage: "play.fill") }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        if ws.apps.isEmpty {
                            Text("Noch leer – Desktop anordnen und speichern.").font(.callout).foregroundStyle(Theme.secondary)
                        }
                        ForEach(ws.apps) { app in appRow(app) }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 400)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Aktuellen Desktop hier speichern") { mgr.saveDesktop(into: ws.id) }
                    Spacer()
                    Button("Bearbeiten …") {
                        HoverPanel.shared.close()
                        AppDelegate.shared.openSettings(page: .workspaces)
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.horizontal, 12)
            }
        }
    }

    private func appRow(_ app: WorkspaceApp) -> some View {
        let running = app.bundleID.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
        return VStack(alignment: .leading, spacing: 3) {
            Button {
                AppLauncher.open(app: app.path, files: app.files)
                HoverPanel.shared.close()
            } label: {
                HStack(spacing: 8) {
                    Image(nsImage: fileIcon(app.path)).resizable().frame(width: 26, height: 26)
                        .overlay(alignment: .bottomTrailing) {
                            if running { Circle().fill(.green).frame(width: 7, height: 7) }
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.name).font(.callout.weight(.medium))
                        Text(placement(app)).font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(app.files, id: \.self) { f in
                Button {
                    AppLauncher.open(app: app.path, files: [f])
                    HoverPanel.shared.close()
                } label: {
                    HStack(spacing: 5) {
                        Image(nsImage: fileIcon(f)).resizable().frame(width: 14, height: 14)
                        Text((f as NSString).lastPathComponent).font(.caption).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 34)
            }
        }
    }

    private func placement(_ app: WorkspaceApp) -> String {
        if !app.windows.isEmpty { return app.windows.count == 1 ? "1 Fenster gespeichert" : "\(app.windows.count) Fenster gespeichert" }
        if let f = app.frame { return f.presetName }
        return "Position unverändert"
    }
}

// MARK: - Music: current playlist

final class PlaylistQueue: ObservableObject {
    static let shared = PlaylistQueue()
    struct Track: Identifiable, Hashable { let index: Int; let title: String; let artist: String; var id: Int { index } }

    @Published private(set) var name = ""
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var loading = false

    /// Reads up to 60 tracks around the current one from the Music app's current playlist.
    func load() {
        guard Script.isRunning("com.apple.Music"), !loading else { return }
        loading = true
        let src = """
        tell application "Music"
            set p to current playlist
            set pn to name of p
            set ci to 0
            try
                set ci to index of current track
            end try
            set c to count of tracks of p
            if c is 0 then return {pn, {}, {}, ci, 1}
            set a to ci - 10
            if a < 1 then set a to 1
            set b to a + 59
            if b > c then set b to c
            set ns to name of tracks a thru b of p
            set ars to artist of tracks a thru b of p
            return {pn, ns, ars, ci, a}
        end tell
        """
        Script.run(src) { [weak self] r in
            guard let self else { return }
            self.loading = false
            guard let r, r.numberOfItems == 5 else { self.tracks = []; self.name = ""; return }
            self.name = r.atIndex(1)?.stringValue ?? ""
            let names = r.atIndex(2), artists = r.atIndex(3)
            self.currentIndex = Int(r.atIndex(4)?.int32Value ?? 0)
            let start = Int(r.atIndex(5)?.int32Value ?? 1)
            var out: [Track] = []
            let n = names?.numberOfItems ?? 0
            if n > 0 {
                for i in 1...n {
                    out.append(Track(index: start + i - 1, title: names?.atIndex(i)?.stringValue ?? "",
                                     artist: artists?.atIndex(i)?.stringValue ?? ""))
                }
            }
            self.tracks = out
        }
    }

    func play(_ t: Track) {
        Script.run("tell application \"Music\" to play track \(t.index) of current playlist") { [weak self] _ in
            self?.currentIndex = t.index
            NowPlaying.shared.poll()
        }
    }
}

struct MusicHoverList: View {
    @ObservedObject private var queue = PlaylistQueue.shared
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var np = NowPlaying.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "music.note.list").font(.title3)
                VStack(alignment: .leading, spacing: 0) {
                    Text(queue.name.isEmpty ? "Musik" : queue.name).font(.headline).lineLimit(1)
                    Text(np.title.isEmpty ? "Nichts wird abgespielt" : "\(np.title) – \(np.artist)")
                        .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer()
                if queue.loading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if np.player == "Music" && !queue.tracks.isEmpty {
                            ForEach(queue.tracks) { t in trackRow(t) }
                        } else {
                            fallback
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 400)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: queue.tracks) { _, _ in proxy.scrollTo(queue.currentIndex, anchor: .center) }
            }
        }
        .onAppear { queue.load() }
    }

    private func trackRow(_ t: PlaylistQueue.Track) -> some View {
        let current = t.index == queue.currentIndex
        return Button { queue.play(t) } label: {
            HStack(spacing: 8) {
                Group {
                    if current {
                        Image(systemName: np.playing ? "speaker.wave.2.fill" : "pause.fill").foregroundStyle(.pink)
                    } else {
                        Text("\(t.index)").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                    }
                }
                .frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.title).font(.callout.weight(current ? .semibold : .regular)).lineLimit(1)
                    if !t.artist.isEmpty { Text(t.artist).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(current ? Color.pink.opacity(0.15) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(t.index)
    }

    /// Spotify or no playlist: remembered and recent tracks instead.
    @ViewBuilder private var fallback: some View {
        if !lib.favorites.isEmpty {
            Text("GEMERKTE TITEL").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary).padding(.top, 2)
            ForEach(lib.favorites.prefix(12)) { t in savedRow(t) }
        }
        if !lib.recent.isEmpty {
            Text("ZULETZT GESPIELT").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary).padding(.top, 6)
            ForEach(lib.recent.prefix(12)) { t in savedRow(t) }
        }
        if lib.favorites.isEmpty && lib.recent.isEmpty {
            Text("Spiel etwas in der Musik-App ab, dann erscheint hier die aktuelle Playlist.")
                .font(.callout).foregroundStyle(Theme.secondary)
        }
    }

    private func savedRow(_ t: SavedTrack) -> some View {
        Button { lib.play(t) } label: {
            HStack(spacing: 8) {
                Image(systemName: t.player == "Spotify" ? "dot.radiowaves.left.and.right" : "music.note").frame(width: 24)
                    .foregroundStyle(Theme.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.title).font(.callout).lineLimit(1)
                    Text(t.artist).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - World clock

enum WorldClocks {
    struct Place: Hashable { let name: String; let tz: TimeZone }

    static func list(_ w: WidgetInstance) -> [Place] {
        w.cfg("worldClocks").split(separator: "\n").compactMap { line in
            let p = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard p.count == 2, let tz = TimeZone(identifier: p[1]) else { return nil }
            return Place(name: p[0], tz: tz)
        }
    }

    static func save(_ l: [Place], _ id: UUID) {
        DockStore.shared.setConfig(id, "worldClocks", l.map { "\($0.name)|\($0.tz.identifier)" }.joined(separator: "\n"))
    }

    /// Asks for a city, looks up its time zone (Open-Meteo geocoding) and adds it.
    static func add(to w: WidgetInstance) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Weltuhr-Ort hinzufügen"
        alert.informativeText = "Stadt eingeben, z. B. „New York“, „Tokio“ oder „Sydney“."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Hinzufügen")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let q = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        Task {
            var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            c.queryItems = [.init(name: "name", value: q), .init(name: "count", value: "1"), .init(name: "language", value: "de")]
            guard let (data, _) = try? await URLSession.shared.data(from: c.url!),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (j["results"] as? [[String: Any]])?.first,
                  let tzID = first["timezone"] as? String, let tz = TimeZone(identifier: tzID) else {
                await MainActor.run { Notifier.notify("Ort nicht gefunden", q) }
                return
            }
            let name = first["name"] as? String ?? q
            await MainActor.run {
                let current = DockStore.shared.instance(w.id) ?? w
                var l = list(current)
                if !l.contains(where: { $0.name == name }) { l.append(Place(name: name, tz: tz)) }
                save(l, w.id)
            }
        }
    }
}

struct ClockHoverList: View {
    let w: WidgetInstance
    @ObservedObject private var store = DockStore.shared
    @ObservedObject private var ticker = Ticker.shared

    var body: some View {
        let places = WorldClocks.list(store.instance(w.id) ?? w)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Weltuhr", systemImage: "globe.europe.africa").font(.headline)
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Clock.app"))
                    HoverPanel.shared.close()
                } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.plain).help("Uhr-App öffnen")
            }
            .padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 8) {
                row(name: "Hier", tz: .current, removable: false)
                ForEach(places, id: \.self) { p in row(name: p.name, tz: p.tz, removable: true) }
            }
            .padding(.horizontal, 12)
            Button {
                HoverPanel.shared.close()
                WorldClocks.add(to: w)
            } label: { Label("Ort hinzufügen", systemImage: "plus") }
                .buttonStyle(.link).padding(.horizontal, 12)
        }
    }

    private func row(name: String, tz: TimeZone, removable: Bool) -> some View {
        let now = ticker.now
        var cal = Calendar.current
        cal.timeZone = tz
        let hour = cal.component(.hour, from: now)
        let night = hour < 7 || hour >= 19
        let diff = (tz.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 3600
        let dayShift = cal.startOfDay(for: now) != Calendar.current.startOfDay(for: now)
            ? (cal.component(.day, from: now) > Calendar.current.component(.day, from: now) ? "Morgen" : "Gestern") : "Heute"
        let time = now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: AppLanguageSettings.shared.locale, timeZone: tz))
        return HStack(spacing: 10) {
            Image(systemName: night ? "moon.stars.fill" : "sun.max.fill")
                .foregroundStyle(night ? Color.indigo : Color.orange).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.callout.weight(.semibold))
                Text(removable ? "\(dayShift), \(diff >= 0 ? "+" : "")\(diff) Std." : "Lokale Zeit")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(time).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
            if removable {
                Button {
                    WorldClocks.save(WorldClocks.list(store.instance(w.id) ?? w).filter { $0.name != name }, w.id)
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary) }
                    .buttonStyle(.plain).help("Entfernen")
            }
        }
    }
}
