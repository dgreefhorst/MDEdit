import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownDoc = UTType(importedAs: "net.daringfireball.markdown")
    static let mermaidDiagram = UTType(importedAs: "nl.mdedit.mermaid")
}

extension Notification.Name {
    static let mdSetMode = Notification.Name("mdSetMode")
    static let mdFind = Notification.Name("mdFind")
    static let mdUndo = Notification.Name("mdUndo")
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownDoc, .mermaidDiagram, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownDoc, .mermaidDiagram, .plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

@main
struct MarkdownEditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorView(text: file.$document.text, fileURL: file.fileURL)
                .frame(minWidth: 600, minHeight: 400)
                .background(WindowAccessor())
        }
        .commands {
            // Ongedaan maken/opnieuw lopen via de eigen geschiedenis van de editor:
            // de standaard undo van WebKit is onbruikbaar omdat de editor de DOM
            // bij elke wijziging opnieuw opbouwt.
            CommandGroup(replacing: .undoRedo) {
                Button("Ongedaan maken") { NotificationCenter.default.post(name: .mdUndo, object: "undo") }
                    .keyboardShortcut("z", modifiers: [.command])
                Button("Opnieuw") { NotificationCenter.default.post(name: .mdUndo, object: "redo") }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("Weergave") {
                Button("Editor") { NotificationCenter.default.post(name: .mdSetMode, object: "wysiwyg") }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Gesplitst") { NotificationCenter.default.post(name: .mdSetMode, object: "split") }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Markdown-bron") { NotificationCenter.default.post(name: .mdSetMode, object: "source") }
                    .keyboardShortcut("3", modifiers: [.command, .option])
            }
            CommandMenu("Zoeken") {
                Button("Zoeken…") { NotificationCenter.default.post(name: .mdFind, object: "open") }
                    .keyboardShortcut("f", modifiers: [.command])
                Button("Volgende treffer") { NotificationCenter.default.post(name: .mdFind, object: "next") }
                    .keyboardShortcut("g", modifiers: [.command])
                Button("Vorige treffer") { NotificationCenter.default.post(name: .mdFind, object: "prev") }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }
}
