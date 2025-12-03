import Cocoa
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Note Model
struct Note: Codable, Identifiable {
    var id: UUID
    var title: String
    var fileURL: URL
    var savedAt: Date
}

// MARK: - Notes Manager
class NotesManager: ObservableObject {
    @Published var notes: [Note] = []
    
    private let notesKey = "savedNotesReferences"
    
    init() {
        loadNotes()
    }
    
    func loadNotes() {
        if let data = UserDefaults.standard.data(forKey: notesKey),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
            persist()
        }
    }
    
    func addNote(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.insert(note, at: 0)
        }
        persist()
    }
    
    func removeFromRecent(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        persist()
    }
    
    func deleteFromDevice(_ note: Note) {
        try? FileManager.default.removeItem(at: note.fileURL)
        notes.removeAll { $0.id == note.id }
        persist()
    }
    
    func clearAll() {
        notes.removeAll()
        persist()
    }
    
    private func persist() {
        if let encoded = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(encoded, forKey: notesKey)
        }
    }
}

// MARK: - Main Content View
struct NotesContentView: View {
    @ObservedObject var notesManager: NotesManager
    @State private var showingLibrary = false
    @State private var currentNote: Note?
    @State private var noteContent = ""
    @State private var autoSaveTimer: Timer?
    
    var body: some View {
        if showingLibrary {
            LibraryView(
                notesManager: notesManager,
                showingLibrary: $showingLibrary,
                currentNote: $currentNote,
                noteContent: $noteContent
            )
        } else {
            EditorView(
                notesManager: notesManager,
                showingLibrary: $showingLibrary,
                currentNote: $currentNote,
                noteContent: $noteContent,
                autoSaveTimer: $autoSaveTimer
            )
        }
    }
}

// MARK: - Editor View
struct EditorView: View {
    @ObservedObject var notesManager: NotesManager
    @Binding var showingLibrary: Bool
    @Binding var currentNote: Note?
    @Binding var noteContent: String
    @Binding var autoSaveTimer: Timer?
    
    var body: some View {
        ZStack {
            Color(NSColor.textBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: saveDocument) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 12))
                            Text("Save Document")
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.accentColor)
                    
                    Button(action: importDocument) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12))
                            Text("Import Document")
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: newDocument) {
                        HStack(spacing: 4) {
                            Text("New Document")
                                .font(.system(size: 13))
                            Image(systemName: "plus")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                Divider()
                
                // Editor
                ScrollView {
                    TextEditor(text: $noteContent)
                        .font(.system(size: 16))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 500)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 20)
                        .onChange(of: noteContent) { _ in
                            scheduleAutoSave()
                        }
                }
                
                Divider()
                
                // Bottom bar
                HStack {
                    Button(action: { showingLibrary = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 12))
                            Text("Open Previous Documents")
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 650, height: 600)
    }
    
    // MARK: - Auto-save
    func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        guard let note = currentNote else { return }
        
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            autoSaveToFile(note: note)
        }
    }
    
    func autoSaveToFile(note: Note) {
        try? noteContent.write(to: note.fileURL, atomically: true, encoding: .utf8)
        var updatedNote = note
        updatedNote.title = extractTitle(from: noteContent)
        updatedNote.savedAt = Date()
        notesManager.addNote(updatedNote)
    }
    
    // MARK: - Save Document (.txt, select folder every time)
    func saveDocument() {
        let panel = NSOpenPanel()
        panel.prompt = "Select Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let folderURL = panel.url {
            saveTXT(to: folderURL)
        }
    }
    
    private func saveTXT(to folderURL: URL) {
        let baseName = extractTitle(from: noteContent)
        var fileURL = folderURL.appendingPathComponent(baseName).appendingPathExtension("txt")
        
        var counter = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = folderURL
                .appendingPathComponent("\(baseName) (\(counter))")
                .appendingPathExtension("txt")
            counter += 1
        }
        
        do {
            try noteContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let note = Note(
                id: currentNote?.id ?? UUID(),
                title: baseName,
                fileURL: fileURL,
                savedAt: Date()
            )
            
            notesManager.addNote(note)
            currentNote = note
        } catch {
            NSLog("Save failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Save Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    
    // MARK: - Import Document
    func importDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowedFileTypes = ["txt", "rtf", "md"]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let fileURL = panel.url {
            let didStart = fileURL.startAccessingSecurityScopedResource()
            defer { if didStart { fileURL.stopAccessingSecurityScopedResource() } }
            
            do {
                var importedContent = ""
                
                if fileURL.pathExtension.lowercased() == "rtf" {
                    let data = try Data(contentsOf: fileURL)
                    let attr = try NSAttributedString(
                        data: data,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    )
                    importedContent = attr.string
                } else {
                    importedContent = try String(contentsOf: fileURL, encoding: .utf8)
                }
                
                // Set editor content
                noteContent = importedContent
                
                // Add to notesManager to show in Library
                let note = Note(
                    id: UUID(),
                    title: extractTitle(from: importedContent),
                    fileURL: fileURL,
                    savedAt: Date()
                )
                notesManager.addNote(note)
                currentNote = note
                
            } catch {
                NSLog("Import failed: \(error)")
            }
        }
    }

    
    // MARK: - Other helpers
    func newDocument() {
        currentNote = nil
        noteContent = ""
        autoSaveTimer?.invalidate()
    }
    
    func extractTitle(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        let firstLine = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        return firstLine.isEmpty ? "Untitled" : String(firstLine.prefix(50))
    }
}

// MARK: - Library View
struct LibraryView: View {
    @ObservedObject var notesManager: NotesManager
    @Binding var showingLibrary: Bool
    @Binding var currentNote: Note?
    @Binding var noteContent: String
    @State private var showingClearAlert = false
    @State private var noteToDelete: Note?
    @State private var showingDeleteOptions = false

    var body: some View {
        ZStack {
            Color(NSColor.textBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: { showingClearAlert = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                            Text("Clear All")
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.red)

                    Spacer()
                    
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 12))
                            Text("Quit App")
                                .font(.system(size: 13))
                            
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.primary)

                    Button(action: { showingLibrary = false }) {
                        HStack(spacing: 4) {
                            Text("Back")
                                .font(.system(size: 13))
                            Image(systemName: "arrow.left")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()
                // Notes list
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Previous Documents")
                            .font(.system(size: 24, weight: .light))
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                        
                        if notesManager.notes.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("No saved documents")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        } else {
                            ForEach(notesManager.notes) { note in
                                HStack(spacing: 12) {
                                    Button(action: { openNote(note) }) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(note.title)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.primary)
                                            
                                            Text(note.fileURL.path)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary.opacity(0.7))
                                                .lineLimit(1)
                                            
                                            Text(formatDate(note.savedAt))
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    Button(action: {
                                        noteToDelete = note
                                        showingDeleteOptions = true
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(14)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .cornerRadius(8)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 10)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 650, height: 600)
        .alert(isPresented: $showingClearAlert) {
            Alert(
                title: Text("Clear All Documents"),
                message: Text("This will remove all documents from recent files (files will not be deleted from your device)."),
                primaryButton: .destructive(Text("Clear All")) {
                    notesManager.clearAll()
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showingDeleteOptions) {
            Alert(
                title: Text("Delete Note"),
                message: Text("Choose how to delete this note"),
                primaryButton: .destructive(Text("Delete from Recent Files")) {
                    if let note = noteToDelete {
                        notesManager.removeFromRecent(note)
                    }
                },
                secondaryButton: .destructive(Text("Delete from Device")) {
                    if let note = noteToDelete {
                        notesManager.deleteFromDevice(note)
                    }
                }
            )
        }
    }
    
    func openNote(_ note: Note) {
        if let content = try? String(contentsOf: note.fileURL, encoding: .utf8) {
            currentNote = note
            noteContent = content
            showingLibrary = false
        }
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var notesManager: NotesManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        notesManager = NotesManager()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Quicknotes")
            button.action = #selector(togglePopover)
        }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 650, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: NotesContentView(notesManager: notesManager))
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

// MARK: - Main App
@main
struct QuicknotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

