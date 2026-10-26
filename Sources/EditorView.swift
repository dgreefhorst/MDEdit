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
        config.userContentController.add(context.coordinator, name: "links")
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
        web.configuration.userContentController.removeScriptMessageHandler(forName: "links")
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
        var lastOpen = Date.distantPast

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

        // Het document in dit venster is leidend: na het wisselen van document
        // (link in hetzelfde venster) loopt parent.fileURL achter.
        private var document: NSDocument? {
            guard let controller = web?.window?.windowController else { return nil }
            return controller.document as? NSDocument
        }

        private var currentURL: URL? {
            document?.fileURL ?? parent.fileURL
        }

        // Swift -> editor (nieuw document, terugzetten, wijziging op schijf):
        // tekst én soort (.md of .mmd) gaan in één call, zodat diagrammen nooit op de verkeerde tekst renderen
        func push(_ text: String) {
            guard loaded, text != lastFromJS else { return }
            let kind = (currentURL?.pathExtension ?? "").lowercased() == "mmd" ? "mmd" : "md"
            let name = currentURL?.lastPathComponent ?? ""
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
                if payload["kind"] as? String == "pdf" {
                    exportPDF(filename: filename,
                              width: payload["width"] as? Double ?? 800,
                              height: payload["height"] as? Double ?? 600)
                    return
                }
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
            if message.name == "links" {
                if let payload = message.body as? [String: Any], let href = payload["href"] as? String {
                    handleLink(href, newWindow: (payload["mode"] as? String) == "new")
                } else if let href = message.body as? String {
                    handleLink(href, newWindow: true)
                }
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

        // Diagram -> vector-PDF op het formaat van het diagram (via WKWebView.createPDF,
        // asynchroon, zodat de hoofdthread niet blokkeert)
        private func exportPDF(filename: String, width: Double, height: Double) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            panel.canCreateDirectories = true
            let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let web = self?.web else { return }
                guard response == .OK, let url = panel.url else { self?.finishPDF(); return }
                let config = WKPDFConfiguration()
                config.rect = CGRect(x: 0, y: 0, width: max(24, width), height: max(24, height))
                web.createPDF(configuration: config) { [weak self] result in
                    defer { self?.finishPDF() }
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: url)
                            self?.notify("Geëxporteerd: " + url.lastPathComponent)
                        } catch {
                            self?.notify("PDF opslaan mislukt")
                        }
                    case .failure:
                        self?.notify("PDF maken mislukt")
                    }
                }
            }
            if let window = web?.window {
                panel.beginSheetModal(for: window, completionHandler: handle)
            } else {
                handle(panel.runModal())
            }
        }

        // Editor laten weten dat de PDF-export klaar is (herstelt de normale weergave)
        private func finishPDF() {
            web?.callAsyncJavaScript("window.__pdfDone && __pdfDone()", arguments: [:], in: nil, in: .page, completionHandler: nil)
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

        // Klik op een link: webadressen gaan naar de standaardapp, bestanden worden
        // geopend ten opzichte van de map van het document — maar alleen als ze bestaan.
        // Zonder Cmd vervangt een document het huidige document in dit venster.
        private func handleLink(_ rawHref: String, newWindow: Bool) {
            let href = rawHref.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, !href.hasPrefix("#") else { return }
            lastOpen = Date()

            if let url = URL(string: href), let scheme = url.scheme?.lowercased(), !scheme.isEmpty {
                switch scheme {
                case "http", "https", "mailto":
                    NSWorkspace.shared.open(url)
                case "file":
                    openTarget(url, newWindow: newWindow)
                default:
                    if !NSWorkspace.shared.open(url) { notify("Kan deze link niet openen") }
                }
                return
            }

            guard let base = currentURL?.deletingLastPathComponent() else {
                notify("Sla het document eerst op om relatieve links te openen")
                return
            }
            let path = href.split(separator: "#", maxSplits: 1)[0].split(separator: "?", maxSplits: 1)[0]
            let decoded = path.removingPercentEncoding ?? String(path)
            guard !decoded.isEmpty else { return }
            openTarget(URL(fileURLWithPath: decoded, relativeTo: base), newWindow: newWindow)
        }

        private func openTarget(_ url: URL, newWindow: Bool) {
            let target = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
                notify("Bestand niet gevonden: " + (target.lastPathComponent.isEmpty ? target.path : target.lastPathComponent))
                return
            }
            if !newWindow, !isDirectory.boolValue, canOpenInEditor(target) {
                swapInThisWindow(target)
            } else if !NSWorkspace.shared.open(target) {
                notify("Kan bestand niet openen")
            }
        }

        /// Alleen de soorten die deze editor zelf aankan komen in hetzelfde venster.
        private func canOpenInEditor(_ url: URL) -> Bool {
            ["md", "markdown", "mmd", "txt"].contains(url.pathExtension.lowercased())
        }

        /// Vervangt het document in dit venster: eerst het huidige document opslaan
        /// (of navragen), dan de inhoud van het doel laden en het document daarheen verhuizen.
        private func swapInThisWindow(_ target: URL) {
            guard let doc = document,
                  let text = try? String(contentsOf: target, encoding: .utf8) else {
                if !NSWorkspace.shared.open(target) { notify("Kan bestand niet openen") }
                return
            }
            confirmChanges(destination: target.lastPathComponent) { [weak self] in
                guard let self else { return }
                let type = doc.fileType ?? "net.daringfireball.markdown"
                self.parent.text = text
                doc.save(to: target, ofType: type, for: .saveAsOperation) { error in
                    if let error { self.notify("Wisselen van document mislukt: " + error.localizedDescription) }
                }
            }
        }

        /// Zijn er wijzigingen die nog niet in het bestand staan?
        private var hasUnsavedChanges: Bool {
            guard let doc = document else { return false }
            if doc.isDocumentEdited { return true }
            guard let url = doc.fileURL,
                  let onDisk = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return onDisk != parent.text
        }

        /// Vraagt om wijzigingen te bewaren voordat er genavigeerd wordt.
        private func confirmChanges(destination: String, proceed: @escaping () -> Void) {
            guard hasUnsavedChanges else { proceed(); return }
            let name = currentURL?.lastPathComponent ?? "Het document"
            let alert = NSAlert()
            alert.messageText = "Wijzigingen opslaan?"
            alert.informativeText = "\(name) is gewijzigd. Als je zonder opslaan naar \(destination) gaat, gaan die wijzigingen verloren."
            alert.addButton(withTitle: "Opslaan")
            alert.addButton(withTitle: "Niet opslaan")
            alert.addButton(withTitle: "Annuleren")
            let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:
                    self.saveCurrentDocument { saved in if saved { proceed() } }
                case .alertSecondButtonReturn:
                    proceed()
                default:
                    break
                }
            }
            if let window = web?.window {
                alert.beginSheetModal(for: window, completionHandler: handle)
            } else {
                handle(alert.runModal())
            }
        }

        /// Schrijft het huidige document weg; vraagt eerst om een bestandsnaam als het nog geen bestand is.
        private func saveCurrentDocument(completion: @escaping (Bool) -> Void) {
            guard let doc = document else {
                completion(false)
                return
            }
            let type = doc.fileType ?? "net.daringfireball.markdown"
            if let url = doc.fileURL {
                doc.save(to: url, ofType: type, for: .saveOperation) { error in
                    completion(error == nil)
                }
                return
            }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "document.md"
            panel.canCreateDirectories = true
            let handle: (NSApplication.ModalResponse) -> Void = { response in
                guard response == .OK, let url = panel.url else {
                    completion(false)
                    return
                }
                doc.save(to: url, ofType: type, for: .saveAsOperation) { error in
                    completion(error == nil)
                }
            }
            if let window = web?.window {
                panel.beginSheetModal(for: window, completionHandler: handle)
            } else {
                handle(panel.runModal())
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            push(parent.text)
            DispatchQueue.main.async { webView.window?.makeFirstResponder(webView) }
        }


        // Klik op een link: nooit in de webweergave zelf navigeren. De editor stuurt
        // de ruwe href via de brug; deze route is de vangnet-variant.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if url.scheme == "file" && url.path == webView.url?.path { return }
            guard Date().timeIntervalSince(lastOpen) > 0.75 else { return }
            if ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
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
