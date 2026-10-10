#if DEBUG
import AppKit
import SwiftUI

/// Nur im Debug-Build: zeichnet Popover und Einstellungen in PNG-Dateien und beendet Seam.
/// Grund: Claude darf auf Michaels Mac keine Bildschirmfotos machen; so lässt sich die Optik
/// trotzdem prüfen. Glas wird ohne Bildschirm nicht echt dargestellt (nur Aufbau, Schrift, Farben).
/// Aufruf: Seam.app/Contents/MacOS/Seam -renderPreview /pfad/zum/ordner
@MainActor
enum PreviewRenderer {

    static func runIfRequested(engine: Engine) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-renderPreview"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (name, dark) in [("hell", false), ("dunkel", true)] {
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                render(PopoverView().environment(engine).environment(engine.prefs),
                       to: dir.appendingPathComponent("popover-\(name).png"), appearance: appearance,
                       background: dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1))
                render(SettingsView().environment(engine).environment(engine.prefs),
                       to: dir.appendingPathComponent("einstellungen-\(name).png"), appearance: appearance,
                       background: dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1))
                LinkRouter.shared.refresh()
                render(LinkRulesView(router: LinkRouter.shared).padding(16).familyBackground(),
                       to: dir.appendingPathComponent("linkregeln-\(name).png"), appearance: appearance,
                       background: dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1))
            }
            NSApp.terminate(nil)
        }
    }

    private static func render<V: View>(_ view: V, to url: URL, appearance: NSAppearance?, background: NSColor) {
        let host = NSHostingView(rootView: ZStack { Color(nsColor: background); view })
        host.appearance = appearance
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.backgroundColor = background
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        do {
            guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: url)
        } catch {
            // Code-Audit 09.10. (C12): nicht still verwerfen, sonst prüft man alte Bilder.
            FileHandle.standardError.write(Data("Vorschau nicht geschrieben: \(url.path) – \(error)\n".utf8))
            exit(1)
        }
    }
}
#endif
