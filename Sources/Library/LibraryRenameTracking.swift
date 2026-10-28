import Foundation

/// Spec: "Rename-tracking allowlist". Moves are allowed only on volume types (`volumeTypeNameKey`) whose
/// rename evidence passed the L1 gate: a rename and a same-volume move preserved the enumerator's size and
/// modification date. Failed, unmeasured (SMB at the 2026-09-27 gate) and unknown types index without moves.
enum LibraryRenameTracking {
    static let verifiedVolumeTypes: Set<String> = ["apfs", "hfs", "exfat"]

    static func isEnabled(volumeType: String) -> Bool {
        self.verifiedVolumeTypes.contains(volumeType)
    }
}
