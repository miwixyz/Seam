import AppKit
import SwiftUI

/// Browser-Auswahl bei gedrückter Fn-Taste (docs/SECURE-DESIGN.md E16g). Eigenes Fenster:
/// Tasten wirken nur, solange es den Fokus hat. Escape oder Fokusverlust → Link wird nicht
/// geöffnet. Kein Bedienungshilfen-Zugriff (Lint-Regel `link_weg_ohne_ax`).
@MainActor
final class BrowserPickerPanel: NSPanel, NSWindowDelegate {

    enum Choice {
        case cancel
        case open(Browsers.Browser, remember: Bool)
    }

    private var onChoice: ((Choice) -> Void)?
    private let browsers: [Browsers.Browser]
    private let canRemember: Bool
    /// Eingaben in den ersten 0,4 s ignorieren: Ein Fenster, das eine fremde App per Link
    /// aufpoppen lässt, soll keinen Tastendruck abfangen, der für etwas anderes gedacht war
    /// (Rafter-Review 10.10.).
    private var shownAt = Date.distantFuture
    static let inputDelay: TimeInterval = 0.4

    init(url: URL, browsers: [Browsers.Browser], fallback: String?, onChoice: @escaping (Choice) -> Void) {
        self.onChoice = onChoice
        self.browsers = browsers
        self.canRemember = !url.isFileURL && LinkRules.urlHost(url) != nil
        // Gemessen 10.10.: Als normales Panel blieb das Fenster unsichtbar (onscreen=false), weil
        // macOS einer Hintergrund-App das Aktivieren verweigert und ein NSPanel sich bei
        // inaktiver App versteckt. Nicht aktivierend wie Spotlight: nimmt Tasten an, ohne Seam
        // nach vorn zu holen.
        super.init(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        title = "Link öffnen mit"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        delegate = self
        let view = BrowserPickerView(url: url, browsers: browsers, fallback: fallback) { [weak self] c in
            self?.choose(c)
        }
        contentView = NSHostingView(rootView: view)
        setContentSize(contentView?.fittingSize ?? NSSize(width: 360, height: 300))
    }

    override var canBecomeKey: Bool { true }

    /// ⌘-Ziffer: öffnen und Website merken. SwiftUIs `onKeyPress` bekommt ⌘-Kombinationen nicht,
    /// sie laufen als Tastenäquivalent durchs Fenster (gemessen 10.10.).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods == .command, let s = event.charactersIgnoringModifiers, let n = Int(s),
              n >= 1, n <= min(9, browsers.count) else { return super.performKeyEquivalent(with: event) }
        choose(.open(browsers[n - 1], remember: canRemember))
        return true
    }

    func present() {
        // Auf dem Bildschirm mit dem Mauszeiger, mittig.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: vf.midX - frame.width / 2, y: vf.midY - frame.height / 2 + vf.height / 8))
        }
        shownAt = Date()
        makeKeyAndOrderFront(nil)
    }

    /// Auswahl aus dem Fenster: Abbrechen geht immer, Öffnen erst nach der Sperrzeit.
    private func choose(_ c: Choice) {
        if case .open = c, Date().timeIntervalSince(shownAt) < Self.inputDelay { return }
        finish(c)
    }

    /// Genau eine Antwort, danach weg.
    private func finish(_ c: Choice) {
        guard let done = onChoice else { return }
        onChoice = nil
        orderOut(nil)
        done(c)
    }

    override func cancelOperation(_ sender: Any?) { finish(.cancel) }
    func windowDidResignKey(_ notification: Notification) { finish(.cancel) }
    func windowWillClose(_ notification: Notification) { finish(.cancel) }
}

private struct BrowserPickerView: View {
    let url: URL
    let browsers: [Browsers.Browser]
    let fallback: String?
    let onChoice: (BrowserPickerPanel.Choice) -> Void

    @FocusState private var focused: Bool

    /// Höchstens 9 Einträge mit Zifferntaste; weitere nur per Klick.
    private var host: String? { url.isFileURL ? nil : LinkRules.urlHost(url) }

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: host ?? (url.isFileURL ? url.lastPathComponent : url.host() ?? ""))
                    .font(FamilyTheme.font(.headline))
                    .foregroundStyle(FamilyTheme.textPrimary)
                Text(verbatim: String(url.absoluteString.prefix(300)))
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            VStack(spacing: 2) {
                ForEach(Array(browsers.enumerated()), id: \.element.id) { i, b in
                    Button { pick(b) } label: {
                        BrowserRow(browser: b, key: i < 9 ? "\(i + 1)" : nil, isDefault: b.id == fallback)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(FamilyTheme.Space.xs)
            .familyCard(radius: FamilyTheme.Radius.field)
            Text(host != nil ? "1–9 oder Klick · mit ⌘ für \(host ?? "") merken · Esc bricht ab"
                             : "1–9 oder Klick · Esc bricht ab")
                .font(FamilyTheme.font(.caption))
                .foregroundStyle(FamilyTheme.textSecondary)
        }
        .padding(FamilyTheme.Space.l)
        .padding(.top, FamilyTheme.Space.s)
        .frame(width: 360)
        .familyBackground()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) { onChoice(.cancel); return .handled }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let n = Int(press.characters), n >= 1, n <= min(9, browsers.count) else { return .ignored }
            pick(browsers[n - 1], remember: press.modifiers.contains(.command))
            return .handled
        }
    }

    private func pick(_ b: Browsers.Browser, remember: Bool? = nil) {
        let cmd = remember ?? NSEvent.modifierFlags.contains(.command)
        onChoice(.open(b, remember: cmd && host != nil))
    }
}

private struct BrowserRow: View {
    let browser: Browsers.Browser
    let key: String?
    let isDefault: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: FamilyTheme.Space.m) {
            Image(nsImage: Browsers.icon(for: browser))
                .resizable()
                .frame(width: 24, height: 24)
            Text(verbatim: browser.name)
                .foregroundStyle(FamilyTheme.textPrimary)
            if isDefault {
                Text("Standard")
                    .font(FamilyTheme.font(.caption))
                    .foregroundStyle(FamilyTheme.textSecondary)
            }
            Spacer()
            if let key {
                Text(key)
                    .font(FamilyTheme.font(.callout, weight: .semibold))
                    .foregroundStyle(hovered ? FamilyTheme.accent : FamilyTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(FamilyTheme.cardStroke.opacity(0.6)))
            }
        }
        .font(FamilyTheme.font(.body))
        .padding(.horizontal, FamilyTheme.Space.s)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(hovered ? FamilyTheme.accent.opacity(0.14) : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}
