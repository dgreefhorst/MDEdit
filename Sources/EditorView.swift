import SwiftUI
import WebKit

// Maximaliseert het venster zodra het aan een scherm wordt gekoppeld.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ZoomOnAppearView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class ZoomOnAppearView: NSView {
    private var applied = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !applied, let window = window else { return }
        applied = true
        DispatchQueue.main.async {
            if !window.isZoomed { window.zoom(nil) }
        }
    }
}

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var fileURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "md")
        config.userContentController.add(context.coordinator, name: "export")
        config.userContentController.add(context.coordinator, name: "images")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        context.coordinator.web = web
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.push(text)
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "md")
        web.configuration.userContentController.removeScriptMessageHandler(forName: "export")
        web.configuration.userContentController.removeScriptMessageHandler(forName: "images")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var parent: EditorView
        weak var web: WKWebView?
        var loaded = false
        var lastFromJS: String?
        var lastPushed: String?
        var lastKind: String?
        var lastName: String?
        var modeObserver: NSObjectProtocol?

        init(_ parent: EditorView) {
            self.parent = parent
            super.init()
            modeObserver = NotificationCenter.default.addObserver(
                forName: .mdSetMode, object: nil, queue: .main
            ) { [weak self] note in
                guard let self = self, let web = self.web,
                      web.window?.isKeyWindow == true,
                      let mode = note.object as? String else { return }
                web.evaluateJavaScript("document.querySelector('#modes [data-m=\"\(mode)\"]').click()", completionHandler: nil)
            }
        }

        deinit {
            if let observer = modeObserver { NotificationCenter.default.removeObserver(observer) }
        }

        // Swift -> editor (nieuw document, terugzetten, wijziging op schijf):
        // tekst én soort (.md of .mmd) gaan in één call, zodat diagrammen nooit op de verkeerde tekst renderen
        func push(_ text: String) {
            guard loaded, text != lastFromJS else { return }
            let kind = (parent.fileURL?.pathExtension ?? "").lowercased() == "mmd" ? "mmd" : "md"
            let name = parent.fileURL?.lastPathComponent ?? ""
            guard !(text == lastPushed && kind == lastKind && name == lastName) else { return }
            lastPushed = text
            lastKind = kind
            lastName = name
            web?.callAsyncJavaScript("nativeSetDoc(k,n,t)", arguments: ["k": kind, "n": name, "t": text], in: nil, in: .page, completionHandler: nil)
        }

        // Editor -> Swift (elke wijziging of exportverzoek)
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "export" {
                guard let payload = message.body as? [String: Any],
                      let filename = payload["filename"] as? String else { return }
                let data: Data
                if let encoding = payload["encoding"] as? String, encoding == "base64",
                   let encoded = payload["data"] as? String, let decoded = Data(base64Encoded: encoded) {
                    data = decoded
                } else if let text = payload["text"] as? String {
                    data = Data(text.utf8)
                } else {
                    return
                }
                export(filename: filename, data: data)
                return
            }
            if message.name == "images" {
                guard let payload = message.body as? [String: Any],
                      let id = payload["id"] as? String,
                      let urls = payload["urls"] as? [String] else { return }
                fetchImages(id: id, urls: urls)
                return
            }
            guard let string = message.body as? String else { return }
            lastFromJS = string
            lastPushed = nil
            if parent.text != string { parent.text = string }
        }

        // Exportbestand opslaan via het standaard macOS-opslaanpaneel
        private func export(filename: String, data: Data) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            panel.canCreateDirectories = true
            let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url)
                    self?.notify("Geëxporteerd: " + url.lastPathComponent)
                } catch {
                    self?.notify("Exporteren mislukt")
                }
            }
            if let window = web?.window {
                panel.beginSheetModal(for: window, completionHandler: handle)
            } else {
                handle(panel.runModal())
            }
        }

        // Afbeeldingen downloaden voor de docx-export (omzeilt CORS)
        private func fetchImages(id: String, urls: [String]) {
            let session = URLSession(configuration: .ephemeral)
            let lock = NSLock()
            var results = [[String: Any]](repeating: ["ok": false], count: urls.count)
            let group = DispatchGroup()
            for (index, value) in urls.enumerated() {
                guard let url = URL(string: value),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { continue }
                group.enter()
                session.dataTask(with: url) { data, response, error in
                    defer { group.leave() }
                    guard let data = data, error == nil else { return }
                    let mime = response?.mimeType ?? "application/octet-stream"
                    lock.lock()
                    results[index] = ["ok": true, "mime": mime, "data": data.base64EncodedString()]
                    lock.unlock()
                }.resume()
            }
            group.notify(queue: .main) { [weak self] in
                _ = session
                self?.web?.callAsyncJavaScript("__imagesResult(id, r)", arguments: ["id": id, "r": results], in: nil, in: .page, completionHandler: nil)
            }
        }

        private func notify(_ text: String) {
            web?.callAsyncJavaScript("__toast(t)", arguments: ["t": text], in: nil, in: .page, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            push(parent.text)
            DispatchQueue.main.async { webView.window?.makeFirstResponder(webView) }
        }


        // Links openen in de standaardbrowser
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               navigationAction.navigationType == .linkActivated,
               ["http", "https", "mailto"].contains(url.scheme ?? "") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
            return nil
        }

        // Bestandskiezer voor <input type="file"> (bijv. een afbeelding invoegen)
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseFiles = true
            panel.canChooseDirectories = parameters.allowsDirectories
            let handle: (NSApplication.ModalResponse) -> Void = { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
            if let window = webView.window {
                panel.beginSheetModal(for: window, completionHandler: handle)
            } else {
                handle(panel.runModal())
            }
        }

        // prompt()/confirm()/alert() van de editor als native dialogen
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Annuleren")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = NSAlert()
            alert.messageText = prompt
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Annuleren")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            field.stringValue = defaultText ?? ""
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }
}
