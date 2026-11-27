// FamilyGlassKit.swift — Glas-Sprache der App-Familie (Liquid Glass, schwebende Inseln,
// lebender Hintergrund, leuchtende gleitende Akzent-Pille)
//
// HERKUNFT
//   Aus Knippi 0.7.0 (veröffentlicht 2026-11-26, „Glas-Umbau“ Phase 1–3) app-neutral
//   herausgezogen. Quellen im Repo ~/Coding/Knippi: Theme/FamilyTheme.swift (Ergänzungen),
//   Theme/AmbientBackdrop.swift, Preferences/Components/PreferencesGlassStyle.swift,
//   Capture/CaptureGlassKit.swift, Preferences/PreferencesView.swift (Seitenleisten-Insel),
//   AnnotationEditor/AnnotationToolbar.swift (Werkzeug-Pille), MenuBar/MenuBarPopover.swift
//   (Glas-Panel), History/HistoryView.swift (unsichtbare Titelleiste).
//   Regeln, Fotos, Fallen: „App-Familie Design-System.md“, Abschnitt „Glas-Sprache“.
//
// EINBAU
//   1. Diese Datei NEBEN die FamilyTheme.swift der App kopieren (nicht hineinkopieren).
//   2. Wie immer nur `FamilyTheme.app` setzen. Der Akzent der App steuert Pille und Glühen
//      automatisch, sonst wird nichts pro App abgewandelt.
//   3. Teil A (Token-Ergänzungen) und Teil B (familyLiquidGlass, familyAnimation,
//      familyFloatingSurface) WEGLASSEN, soweit die FamilyTheme-Kopie der App diese Namen schon
//      hat (Knippi: alle). Sonst meldet der Compiler „invalid redeclaration“. Geprüft 26.11.:
//      Kit ohne Teil A+B kompiliert mit Knippis Kopie. Kopien weichen voneinander ab, deshalb
//      nichts pauschal ersetzen, nur gezielt übertragen.
//   4. Neuer Akzent (z. B. Knippi Petrol) braucht einen `case` in `FamilyTheme.App` plus Werte in
//      `accent`/`accentFill` der Kopie – das kann eine Erweiterung nicht nachrüsten.
//   5. Die Vorlage-Funktion `familyGlass` hört noch nicht auf „Transparenz reduzieren“
//      (Knippis Kopie schon). Für Neues deshalb `familyLiquidGlass` bzw. `floatingGlassIsland`
//      nehmen, die beide selbst ausweichen.
//
// VORAUSSETZUNG
//   Mindestziel macOS 26 / iOS 26 (Liquid Glass: `glassEffect`, `Glass`, `GlassEffectContainer`;
//   MeshGradient und `Color.mix` ab macOS 15). Typgeprüft gegen die Vault-Vorlage
//   FamilyTheme.swift mit `xcrun swiftc -typecheck -target arm64-apple-macos26.0`.
//   Die AppKit-Teile (Panel, Fenster) gibt es nur unter macOS.
//
// GEMESSENE FALLEN (Knippi 0.7.0, 2026-11-26)
//   a) Offscreen-Renders (ImageRenderer, cacheDisplay) zeigen KEIN Liquid Glass. Optik nur am
//      echten Fenster abnehmen: `screencapture -l <fenster-id>` bzw. `-R x,y,b,h`.
//   b) `screencapture -l` eines transparenten Fensters zeigt das Glas grau ohne Schreibtisch.
//      Für schwebende Panels den Bildschirmbereich aufnehmen (`-R`).
//   c) macOS 27 zeichnet die System-Seitenleiste flach. Glas-Seitenleiste deshalb als eigene
//      Insel (`floatingGlassIsland`), nicht über NavigationSplitView.
//   d) TimelineView-Hintergrund kostete 12–17 % CPU, auch im Hintergrund. `AmbientBackdrop`
//      pausiert bei inaktivem Fenster (gemessen danach 0–0,4 %, vorne ca. 8 %), 12 Bilder/s.
//   e) Der transparente Schattenrand eines schwebenden Fensters fängt Klicks ab.
//      `Floating.edge` höchstens halb so groß wie der Abstand gestapelter Fenster.
//   f) Schwebende Panels mit `sharingType = .none` und vor einer Aufnahme schließen
//      (`FamilyFloatingPanel.closeBeforeCapture`), sonst landen sie im Bildschirmfoto.
//   g) Unsichtbare Titelleiste (`applyFamilyGlassChrome`): Klickziele am echten Fenster prüfen
//      (Hit-Test). Knöpfe neben den Ampelknöpfen liegen sonst im Zieh-Bereich des Fensters.

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Teil A: Token-Ergänzungen (weglassen, wenn die FamilyTheme-Kopie sie schon hat)

extension FamilyTheme {
    /// Leichte Tönung für kleines echtes Liquid Glass (Vorschaukarte, Hinweis, Aufnahmeleiste):
    /// nimmt dem Schreibtisch die Farbe, lässt aber Lichtbrechung und Rand sichtbar.
    static let glassLightTint = Color(light: 0xF3F5F9, dark: 0x161A25).opacity(0.42)
    /// Kräftigere Tönung für Glas, auf dem Text steht: bleibt auch über dunklen Fenstern lesbar
    /// (gemessen 26.11.: 0,42 über dunklem Fenster nur mittelgrau).
    static let glassReadableTint = Color(light: 0xF3F5F9, dark: 0x161A25).opacity(0.66)

    /// Schwebende Fenster (Panel, HUD, Hinweis, Vorschaukarte): ein gemeinsamer Satz.
    /// Halbtransparentes Glas → Fensterschatten aus (`hasShadow = false`), Schatten in der Ansicht
    /// zeichnen und das Fenster ringsum um `edge` größer machen. `edge` > `shadowRadius + shadowY`,
    /// sonst schneidet die Fenstergrenze den Schatten rechteckig ab (Verbote, 15.11.).
    /// Und `edge` ≤ halber Abstand gestapelter Fenster, sonst fängt der Rand Klicks ab (Falle e).
    enum Floating {
        static let radius: CGFloat = 14
        static let edge: CGFloat = 24
        static let shadowRadius: CGFloat = 10
        static let shadowY: CGFloat = 5
        static let shadowColor = Color(light: 0x1E2846, dark: 0x000000).opacity(0.22)
    }

    /// Bewegung der Familie: ruhige Federn ohne Nachwippen. Bei „Bewegung reduzieren“ nehmen
    /// die Bausteine `reduced` (nur kurze Überblendung), siehe `familyAnimation`.
    enum Motion {
        /// Auswahl wechselt, Pille gleitet (Werkzeug, Seitenleiste, Umschalter).
        static let select = Animation.spring(response: 0.34, dampingFraction: 0.86)
        /// Schwebendes erscheint (Panel, Vorschaukarte, Hinweis).
        static let appear = Animation.spring(response: 0.46, dampingFraction: 0.8)
        /// Hover hebt an.
        static let hover = Animation.spring(response: 0.28, dampingFraction: 0.9)
        /// Ersatz bei „Bewegung reduzieren“.
        static let reduced = Animation.easeOut(duration: 0.15)
    }

    /// Ruhiger Fensterverlauf für Inhaltsbereiche neben einer Glas-Insel: diagonal, kaum
    /// sichtbar, damit das Glas darüber etwas zum Brechen hat (ohne lebenden Hintergrund).
    static var calmGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundMiddle], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Arbeitsfläche hinter Bild/Leinwand (Editor): hell im Hellen, dunkel im Dunklen. Fest,
    /// darüber schweben die Glas-Kapseln.
    static let canvasBackdrop = Color(light: 0xDCE0E9, dark: 0x10131B)

    #if os(macOS)
    /// Dasselbe als NSColor (für NSScrollView/NSView-Hintergründe).
    static let canvasBackdropNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x10 / 255.0, green: 0x13 / 255.0, blue: 0x1B / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xDC / 255.0, green: 0xE0 / 255.0, blue: 0xE9 / 255.0, alpha: 1)
    }

    /// Übergang für alte Aufrufer mit NSColor-Systemfarben (Toasts): Grün → `success`,
    /// Gelb/Orange → `warning`, Rot → `danger`.
    static func statusColor(for color: NSColor) -> Color {
        switch color {
        case .systemGreen: success
        case .systemYellow, .systemOrange: warning
        case .systemRed: danger
        default: Color(nsColor: color)
        }
    }
    #endif
}

// MARK: - Teil B: Liquid Glass mit Bedienungshilfen

/// Echtes Liquid Glass für Schwebendes, das selbst auf die Bedienungshilfen hört:
/// „Transparenz reduzieren“ → feste Fläche (`card`), „Kontrast erhöhen“ → sichtbarer Rand.
private struct FamilyLiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let increased = contrast == .increased
        if reduceTransparency {
            // Feste Fläche; eine halbdurchsichtige Tönung liegt deckend darauf, nie über dem Schreibtisch.
            content
                .background { if let tint { shape.fill(tint) } }
                .background(shape.fill(FamilyTheme.card))
                .overlay(shape.stroke(FamilyTheme.cardStroke, lineWidth: increased ? 1 : 0.8))
        } else {
            content
                .glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
                .overlay {
                    if increased { shape.stroke(FamilyTheme.cardStroke, lineWidth: 1) }
                }
        }
    }
}

/// Animation, die „Bewegung reduzieren“ achtet: dann nur eine kurze Überblendung.
private struct FamilyAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? FamilyTheme.Motion.reduced : animation, value: value)
    }
}

extension View {
    /// Liquid Glass der Familie für schwebende Bedienelemente (Kapseln, runde Knöpfe, Hinweise).
    /// `tint`: z. B. `FamilyTheme.glassReadableTint`, wenn Text darauf steht. `interactive`:
    /// Glas reagiert auf Zeiger und Klick. Nie für Inhaltsflächen (Regel G1).
    func familyLiquidGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(FamilyLiquidGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }

    /// `.animation(_:value:)` mit Rücksicht auf „Bewegung reduzieren“.
    func familyAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(FamilyAnimationModifier(animation: animation, value: value))
    }

    /// Schwebende Fläche für ein eigenes Fenster (Menüleisten-Panel, HUD): getöntes Glas, feiner
    /// Rand, weicher Schatten, ringsum `Floating.edge` transparenter Rand für den Schatten.
    /// Das Fenster muss um 2 × `edge` größer sein als die Fläche und `hasShadow = false` haben.
    func familyFloatingSurface<S: Shape>(in shape: S) -> some View {
        familyTintedGlass(in: shape)
            .overlay { shape.stroke(FamilyTheme.cardStroke.opacity(0.9), lineWidth: 0.5) }
            .compositingGroup()
            .shadow(color: FamilyTheme.Floating.shadowColor,
                    radius: FamilyTheme.Floating.shadowRadius, y: FamilyTheme.Floating.shadowY)
            .padding(FamilyTheme.Floating.edge)
    }
}

// MARK: - Teil C: Schwebende Glas-Insel (Seitenleiste, Umschalter, Nebenfenster)

/// Schwebende Glas-Insel. Hell wirkte `Glass.regular` milchig-weiß, das Akzent-Licht dahinter
/// kam kaum durch (Foto 26.11.). Darum hell das klarere Glas mit leichter weißer Tönung, dazu ein
/// heller Innenrand (oben kräftig, unten verlaufend) und ein weicher Schatten, der nur AUSSERHALB
/// der Insel liegt (innen würde ihn das Glas mitbrechen und grau färben).
struct FloatingGlassIsland<S: InsettableShape>: ViewModifier {
    let shape: S
    /// Leichte Färbung des Glases, sonst neutral.
    var tint: Color?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let light = colorScheme == .light
        let increased = contrast == .increased
        if reduceTransparency {
            content
                .background(shape.fill(FamilyTheme.card))
                .overlay(shape.strokeBorder(FamilyTheme.cardStroke, lineWidth: increased ? 1 : 0.8))
        } else {
            content
                .glassEffect(glass(light: light), in: shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(light ? 0.9 : 0.24),
                                                .white.opacity(light ? 0.28 : 0.04)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                    .allowsHitTesting(false)
                }
                .overlay {
                    if increased { shape.strokeBorder(FamilyTheme.cardStroke, lineWidth: 1) }
                }
                .background {
                    shape.fill(Color(light: 0x1E2846, dark: 0x000000).opacity(light ? 0.16 : 0.45))
                        .blur(radius: 18)
                        .offset(y: 8)
                        .mask {
                            Rectangle().padding(-80)
                                .overlay { shape.fill(.black).blendMode(.destinationOut) }
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)
                }
        }
    }

    private func glass(light: Bool) -> Glass {
        if let tint { return Glass.regular.tint(tint) }
        return light ? Glass.clear.tint(Color.white.opacity(0.22)) : Glass.regular
    }
}

extension View {
    /// Schwebende Glas-Insel (Seitenleiste der Einstellungen, Umschalter-Leiste, Effekte-Spalte).
    func floatingGlassIsland<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(FloatingGlassIsland(shape: shape, tint: tint))
    }
}

// MARK: - Teil D: Leuchtende Akzent-Pille + Hover

/// Leuchtende Akzent-Pille hinter dem aktiven Element. Weiße Schrift/Symbole darauf
/// (`accentFill` ist für Weiß gerechnet, ≥ 4,6 : 1). Die Farbe kommt aus `FamilyTheme.app`.
struct FamilyAccentPill<S: InsettableShape>: View {
    var shape: S
    /// Leichter Verlauf in der Pille (Seitenleiste, Umschalter). Werkzeugleiste: flach.
    var gradient: Bool = true
    /// Glühen um die Pille.
    var glow: Bool = true
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if gradient { shape.fill(FamilyTheme.accentFill.gradient) } else { shape.fill(FamilyTheme.accentFill) }
        }
        .overlay(shape.strokeBorder(.white.opacity(contrast == .increased ? 0.6 : 0.22), lineWidth: 0.6))
        .shadow(color: FamilyTheme.accentFill.opacity(glow ? 0.5 : 0), radius: 8, y: 2)
        .accessibilityHidden(true)
    }
}

extension FamilyAccentPill where S == Capsule {
    init(gradient: Bool = true, glow: Bool = true) {
        self.init(shape: Capsule(style: .continuous), gradient: gradient, glow: glow)
    }
}

/// Leise Hover-Hervorhebung (neutrale Fläche), Element hebt sich leicht an (1,06 ×, 1 pt hoch);
/// bei „Bewegung reduzieren“ nur die Fläche.
private struct FamilyHoverLiftModifier<S: Shape>: ViewModifier {
    let shape: S
    var isEnabled: Bool
    var lift: Bool
    var onChange: ((Bool) -> Void)?
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let active = isEnabled && isHovered
        let moves = active && lift && !reduceMotion
        content
            .background { shape.fill(FamilyTheme.textPrimary.opacity(active ? 0.08 : 0)) }
            .contentShape(shape)
            .scaleEffect(moves ? 1.06 : 1)
            .offset(y: moves ? -1 : 0)
            .onHover { hovering in
                isHovered = hovering
                onChange?(hovering)
            }
            .familyAnimation(FamilyTheme.Motion.hover, value: isHovered)
    }
}

extension View {
    /// Hover hebt an. `lift: false` = nur neutrale Fläche (Listenzeilen, Seitenleiste).
    func familyHoverLift<S: Shape>(in shape: S = Capsule(style: .continuous), isEnabled: Bool = true,
                                   lift: Bool = true, onChange: ((Bool) -> Void)? = nil) -> some View {
        modifier(FamilyHoverLiftModifier(shape: shape, isEnabled: isEnabled, lift: lift, onChange: onChange))
    }

    /// Schwebende Glas-Kapsel um eine Knopfgruppe (Werkzeugleiste, Aufnahmeleiste).
    /// `readable`: getönt, damit Beschriftung über unruhigem Untergrund lesbar bleibt.
    func familyGlassPill(readable: Bool = false) -> some View {
        padding(.horizontal, 5)
            .padding(.vertical, 4)
            .familyLiquidGlass(in: Capsule(), tint: readable ? FamilyTheme.glassReadableTint : nil)
    }

    /// Erscheinen schwebender Inseln: leicht verkleinert und unscharf → scharf. Mit
    /// `.familyAnimation(FamilyTheme.Motion.appear, value: appeared)` kombinieren.
    func familyAppear(_ appeared: Bool, reduceMotion: Bool, anchor: UnitPoint = .center) -> some View {
        scaleEffect(appeared || reduceMotion ? 1 : 0.94, anchor: anchor)
            .blur(radius: appeared || reduceMotion ? 0 : 4)
            .opacity(appeared ? 1 : 0)
    }
}

// MARK: - Teil E: GlassPillBar (waagerechter Umschalter mit gleitender Pille)

/// Glas-Kapsel mit gleitender, leuchtender Akzent-Pille: Umschalter in Nebenfenstern
/// (Hilfe · Neuigkeiten · Fremdcode, Schritte eines Assistenten). `isEnabled(i) == false` →
/// Eintrag nicht anklickbar (z. B. künftige Schritte).
struct GlassPillBar<Item: Hashable>: View {
    let items: [Item]
    let selection: Item
    let label: (Item) -> Text
    var icon: ((Item) -> String?)? = nil
    var isEnabled: (Item) -> Bool = { _ in true }
    let onSelect: (Item) -> Void

    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                GlassPillSegment(label: label(item), icon: icon?(item), isSelected: item == selection,
                                 isEnabled: isEnabled(item), space: space) {
                    guard item != selection else { return }
                    withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.select) {
                        onSelect(item)
                    }
                }
            }
        }
        .padding(4)
        .floatingGlassIsland(in: Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct GlassPillSegment: View {
    let label: Text
    let icon: String?
    let isSelected: Bool
    let isEnabled: Bool
    let space: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                label
                    .font(FamilyTheme.font(12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : FamilyTheme.textPrimary.opacity(isEnabled ? 1 : 0.42))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                if isSelected {
                    FamilyAccentPill().matchedGeometryEffect(id: "pill", in: space)
                } else if isHovered && isEnabled {
                    Capsule(style: .continuous).fill(FamilyTheme.textPrimary.opacity(0.07))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .familyAnimation(FamilyTheme.Motion.hover, value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Teil F: Glas-Seitenleiste (senkrecht, gleitende Pille, Pfeiltasten)

/// Einträge einer schwebenden Glas-Seitenleiste (Einstellungen). Die Insel selbst legt der
/// Aufrufer an, damit oben App-Symbol/Name Platz haben:
///
///     VStack(alignment: .leading) {
///         Color.clear.frame(height: 40)          // Platz für die Ampelknöpfe
///         header                                  // App-Symbol + Name
///         GlassSidebarList(items: …, selection: $tab, label: { Text($0.title) }, icon: { $0.icon })
///         Spacer(minLength: 0)
///     }
///     .frame(width: 216).frame(maxHeight: .infinity)
///     .floatingGlassIsland(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
///     .padding(10)                                // Abstand der Insel zum Fensterrand
struct GlassSidebarList<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> Text
    var icon: ((Item) -> String)? = nil

    @Namespace private var space
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                GlassSidebarRow(label: label(item), icon: icon?(item), isSelected: item == selection,
                                space: space) { select(item) }
            }
        }
        .padding(.horizontal, 8)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -1) }
        .accessibilityElement(children: .contain)
    }

    private func select(_ item: Item) {
        guard item != selection else { return }
        withAnimation(reduceMotion ? FamilyTheme.Motion.reduced : FamilyTheme.Motion.select) { selection = item }
    }

    private func move(by step: Int) -> KeyPress.Result {
        guard let index = items.firstIndex(of: selection) else { return .ignored }
        let next = index + step
        guard items.indices.contains(next) else { return .handled }
        select(items[next])
        return .handled
    }
}

private struct GlassSidebarRow: View {
    let label: Text
    let icon: String?
    let isSelected: Bool
    let space: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).frame(width: 20)
                }
                label
                    .font(FamilyTheme.font(13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : FamilyTheme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background {
                if isSelected {
                    FamilyAccentPill().matchedGeometryEffect(id: "selection", in: space)
                } else if isHovered {
                    Capsule(style: .continuous).fill(FamilyTheme.textPrimary.opacity(0.07))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .familyAnimation(FamilyTheme.Motion.hover, value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Weiches Licht hinter einer Glas-Insel links (Akzent) und ein kühler Gegenpol unten rechts
/// (Iris): das Glas hat etwas zum Brechen, die Fläche bekommt Tiefe. Über `AmbientBackdrop`
/// legen. Bei „Transparenz reduzieren“ / „Kontrast erhöhen“ leer.
struct FamilyIslandLights: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if !reduceTransparency && contrast != .increased {
            let light = colorScheme == .light
            ZStack(alignment: .topLeading) {
                Ellipse()
                    .fill(FamilyTheme.accent.opacity(light ? 0.66 : 0.46))
                    .frame(width: 280, height: 500)
                    .blur(radius: light ? 60 : 80)
                    .offset(x: -50, y: 50)
                Ellipse()
                    .fill(FamilyTheme.iris.opacity(light ? 0.46 : 0.30))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: 20, y: 400)
                Ellipse()
                    .fill(FamilyTheme.iris.opacity(light ? 0.26 : 0.24))
                    .frame(width: 420, height: 300)
                    .blur(radius: 100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 120, y: 90)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Teil G: Glas-Kapselgruppe mit gleitender Werkzeug-Pille

/// Werkzeugreihe in einer Glas-Kapsel mit EINER Akzent-Pille, die beim Wechsel hinübergleitet.
/// Bewusst Versatz statt `matchedGeometryEffect`: In `ViewThatFits` existieren mehrere Varianten
/// der Leiste gleichzeitig, dieselbe Geometrie-ID gäbe es dann mehrfach (Knippi-Editor).
/// Mehrere Gruppen nebeneinander in einen `GlassEffectContainer(spacing: 10)` legen, damit
/// benachbarte Kapseln wie ein Glas wirken.
struct GlassToolGroup<Item: Hashable, Label: View>: View {
    let items: [Item]
    @Binding var selection: Item
    var buttonSize = CGSize(width: 30, height: 26)
    var spacing: CGFloat = 4
    /// Tooltip/Bedienungshilfen-Name je Werkzeug.
    let title: (Item) -> String
    /// Symbol je Werkzeug; `isActive` → weiß färben (liegt auf der Pille).
    @ViewBuilder let label: (Item, _ isActive: Bool) -> Label

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(items, id: \.self) { item in
                let active = item == selection
                Button { selection = item } label: {
                    label(item, active)
                        .foregroundStyle(active ? Color.white : FamilyTheme.textPrimary)
                        .frame(width: buttonSize.width, height: buttonSize.height)
                        .familyHoverLift(isEnabled: !active)
                }
                .buttonStyle(.plain)
                .help(title(item))
                .accessibilityLabel(Text(verbatim: title(item)))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .background(alignment: .leading) {
            if let index = items.firstIndex(of: selection) {
                FamilyAccentPill(gradient: false)
                    .frame(width: buttonSize.width, height: buttonSize.height)
                    .offset(x: CGFloat(index) * (buttonSize.width + spacing))
                    .familyAnimation(FamilyTheme.Motion.select, value: index)
            }
        }
        .familyGlassPill()
    }
}

// MARK: - Teil H: AmbientBackdrop (lebender Mesh-Hintergrund)

/// Ruhig lebender Fensterhintergrund: MeshGradient aus den Schiefer-Tönen mit weichem Glühen im
/// App-Akzent. Ein Zyklus ~24 s, 12 Bilder/s. Läuft nur, solange das Fenster aktiv ist
/// (`appearsActive`), sonst steht das Bild still (Falle d). Inhalte liegen weiter auf festen
/// Karten (Regel G1).
/// Bedienungshilfen: „Bewegung reduzieren“ → stillstehend; „Transparenz reduzieren“ oder
/// „Kontrast erhöhen“ → einfacher fester Familien-Verlauf.
struct AmbientBackdrop: View {
    /// Stärke des Akzent-Glühens (0 … ~1,3). Einstellungen mit Insel-Lichtern ~1,3, Verlauf ~1.
    var glow: Double = 0.55

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        if reduceTransparency || contrast == .increased {
            LinearGradient(colors: base, startPoint: .top, endPoint: .bottom)
        } else if reduceMotion {
            mesh(phase: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !appearsActive)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                mesh(phase: t.truncatingRemainder(dividingBy: 24) / 24 * 2 * .pi)
            }
        }
    }

    private var base: [Color] {
        colorScheme == .dark
            ? [Color(kitHex: 0x0D1019), Color(kitHex: 0x161A25), Color(kitHex: 0x1F2433)]
            : [Color(kitHex: 0xF3F5F9), Color(kitHex: 0xE7E9F1), Color(kitHex: 0xD9DDE8)]
    }

    private func mesh(phase: Double) -> some View {
        let dx = Float(sin(phase)) * 0.08
        let dy = Float(cos(phase)) * 0.06
        // Randpunkte wandern leicht gegenläufig mit: der Verlauf atmet, statt nur in der Mitte zu kreisen.
        let ex = Float(cos(phase)) * 0.05
        let dark = colorScheme == .dark
        let glowColor = FamilyTheme.accent.opacity((dark ? 0.46 : 0.26) * glow)
        // Dunkel ein satteres Indigo (sonst wirkt der Verlauf flach), hell ein kühles Blau statt Grau.
        let coolColor = Color(kitHex: dark ? 0x2C3A6E : 0xBFCDF0).opacity(dark ? 0.95 : 0.9)
        let irisColor = FamilyTheme.iris.opacity(dark ? 0.34 : 0.20).mix(with: base[2], by: 0.4)
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5 + ex, 0], [1, 0],
                [0, 0.5 - ex], [0.5 + dx, 0.5 + dy], [1, 0.5 + ex],
                [0, 1], [0.5 - ex, 1], [1, 1],
            ],
            colors: [
                base[0], base[0], coolColor,
                base[1], glowColor.mix(with: base[1], by: 0.35), base[1],
                coolColor, base[2], irisColor,
            ],
            smoothsColors: true
        )
    }
}

private extension Color {
    /// Eigener Name, damit es nicht mit einem `Color(hex:)` der App kollidiert.
    init(kitHex hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

// MARK: - Teil I: in Seam bewusst weggelassen

// Das schwebende Glas-Panel der Vorlage (`FamilyFloatingPanel`) fängt `keyDown` im eigenen Fenster
// ab. Seams Sicherheitsregel E1/E2 (SwiftLint `keine_synthetischen_ereignisse`) verbietet jedes
// Mitlesen von Tastatur außerhalb der freigegebenen Dateien, und Seam braucht das Panel nicht
// (Menüleistenfenster ist `MenuBarExtra`). Beim nächsten Sync aus der Vorlage wieder entfernen.
