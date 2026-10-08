import SwiftUI

/// Hilfe, Änderungen und rechtliche Hinweise — **direkt aus dem Bundle gelesen**,
/// nicht als Swift-Strings gepflegt.
///
/// Warum das der Kern der Sache ist: Tippis Hilfe hing an einem Tag fünf
/// Versionen hinterher, weil sie im Code stand und beim Release niemand
/// mitzog. Eine Prosa-Doku im Quelltext driftet immer — sie ist eine Kopie,
/// und Kopien veralten.
///
/// Hier liegen `HILFE.md`, `CHANGELOG.md` und `THIRD-PARTY-LICENSES.md` als Ressourcen
/// im App-Bundle. `make build` kopiert sie bei **jedem** Durchlauf frisch aus
/// dem Repo. Damit kann die angezeigte Hilfe gar nicht älter sein als der Build,
/// und die Versionsnummer kommt aus der `Info.plist` statt aus einer Konstante.
struct HelpView: View {

    enum Doc: String, CaseIterable, Identifiable {
        case help = "Hilfe"
        case changes = "Änderungen"
        // Muss in der App erreichbar sein, nicht nur im Repo: Sparkles
        // MIT-Lizenz verlangt, dass Urheberhinweis und Lizenztext der
        // AUSLIEFERUNG beigefügt werden. Das ausgelieferte Sparkle.framework
        // enthält selbst keine Lizenzdatei — gemessen am 2026-09-22.
        case thirdParty = "Fremdcode"
        var id: String { rawValue }

        var resource: String {
            switch self {
            case .help: "HILFE"
            case .changes: "CHANGELOG"
            case .thirdParty: "THIRD-PARTY-LICENSES"
            }
        }
    }

    @State private var doc: Doc = .help

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(v) (Build \(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $doc) {
                ForEach(Doc.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                MarkdownView(source: text(for: doc))
                    .textSelection(.enabled)
                    .padding(.trailing, 4)
            }
            .frame(height: 380)

            // Das App-Symbol hat sonst keinen Ort: Seam ist eine
            // LSUIElement-App ohne Dock-Symbol und ohne "Über"-Fenster.
            HStack(spacing: 8) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 34, height: 34)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Seam").font(.callout.weight(.semibold))
                    Text(version).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    /// Liest die Datei aus dem Bundle.
    ///
    /// Fehlt sie, steht das sichtbar da — statt einer leeren Fläche, die wie
    /// „keine Änderungen" aussieht. Ein fehlendes Dokument ist ein Build-Fehler,
    /// kein Anzeigezustand.
    private func text(for doc: Doc) -> String {
        guard let url = Bundle.main.url(forResource: doc.resource, withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return "## Dokument fehlt\n\n`\(doc.resource).md` liegt nicht im "
                 + "App-Bundle. Das ist ein Fehler beim Bauen, keine leere Datei."
        }
        return raw
    }
}
