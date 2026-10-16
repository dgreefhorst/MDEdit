import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownDoc = UTType(importedAs: "net.daringfireball.markdown")
}

extension Notification.Name {
    static let mdSetMode = Notification.Name("mdSetMode")
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownDoc, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownDoc, .plainText] }

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
            EditorView(text: file.$document.text)
                .frame(minWidth: 600, minHeight: 400)
                .background(WindowAccessor())
        }
        .commands {
            CommandMenu("Weergave") {
                Button("Editor") { NotificationCenter.default.post(name: .mdSetMode, object: "wysiwyg") }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Gesplitst") { NotificationCenter.default.post(name: .mdSetMode, object: "split") }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Markdown-bron") { NotificationCenter.default.post(name: .mdSetMode, object: "source") }
                    .keyboardShortcut("3", modifiers: [.command, .option])
            }
        }
    }
}
