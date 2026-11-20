import Foundation

/// E23: Schnittstelle zwischen Seam und dem Root-Helfer SeamWake. Genau zwei Befehle, keine Pfade,
/// kein freier Text. Liegt in beiden Zielen (Seam und SeamWake), damit beide Seiten dasselbe sprechen.
enum WakeXPC {
    static let machService = "dev.mwlr.seam.wake"
    static let plistName = "dev.mwlr.seam.wake.plist"

    /// Wer den Helfer steuern darf: nur Seam, signiert vom eigenen Team (E23a).
    static let clientRequirement =
        #"anchor apple generic and identifier "dev.mwlr.seam" and certificate leaf[subject.OU] = "LTKJ6Z2VYB""#
    /// Mit wem Seam spricht: nur mit dem eigenen Helfer.
    static let helperRequirement =
        #"anchor apple generic and identifier "dev.mwlr.seam.wake" and certificate leaf[subject.OU] = "LTKJ6Z2VYB""#
}

/// Antwort beider Befehle: tatsächlicher Zustand (nach `pmset` gemessen) und ein Grund aus `WakeReason`.
@objc(SeamWakeProtocol)
protocol SeamWakeProtocol {
    func setAwake(_ on: Bool, reply: @escaping @Sendable (Bool, String) -> Void)
    func status(reply: @escaping @Sendable (Bool, String) -> Void)
}

/// Warum der Wachmodus an oder aus ist. Rohwerte gehen über XPC, deshalb fest.
enum WakeReason: String, Sendable {
    case ok
    case off = "aus"
    case battery = "akku"
    case heat = "waerme"
    case clientGone = "seam-weg"
    case restart = "neustart"
    case external = "extern"
    case pmsetFailed = "pmset-fehler"
}

/// Reine Regeln des Helfers (E23c), getestet.
enum WakeGuard {
    /// Unter dieser Ladung (ohne Netzteil) schaltet der Helfer ab bzw. gar nicht erst an.
    static let minimumBattery = 20

    /// `thermal` = `ProcessInfo.ThermalState.rawValue` (0 normal … 3 kritisch). nil = darf an bleiben.
    static func offReason(onBattery: Bool, percent: Int?, thermal: Int) -> WakeReason? {
        if thermal >= ProcessInfo.ThermalState.serious.rawValue { return .heat }
        if onBattery, let percent, percent <= minimumBattery { return .battery }
        return nil
    }

    /// Liest `SleepDisabled` aus `pmset -g`. nil = Zeile fehlt (Ausgabe unbekannt → nicht raten).
    static func sleepDisabled(inPmsetOutput output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count == 2, parts[0] == "SleepDisabled" { return parts[1] == "1" }
        }
        return nil
    }
}
