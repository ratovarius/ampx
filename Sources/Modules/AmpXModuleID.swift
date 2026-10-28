enum AmpXModuleID: String, CaseIterable, Codable {
    case player
    case equalizer
    case playlist
    case enthea
    /// Music Library window: never part of the stack, snaps like any module (Library Module spec).
    case library
}
