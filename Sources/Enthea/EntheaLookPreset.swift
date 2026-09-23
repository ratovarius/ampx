import Foundation

/// Artistic / phenomenological look presets that map to ENTHEA `SUBSTANCES` ids.
/// Display names intentionally avoid medical framing — simulator looks only.
struct EntheaLookPreset: Identifiable, Equatable, Sendable {
    let id: String
    /// Menu label (phenomenological, not a substance claim).
    let title: String
    /// One-line visual hint for help / USAGE.
    let blurb: String

    /// Core ENTHEA singles (no flip blends). Ids must match `SUBSTANCES` in vendored HTML.
    static let all: [EntheaLookPreset] = [
        .init(id: "lsd", title: "Electric Lattices", blurb: "Bright crisp geometry and colour enhancement"),
        .init(id: "psilo", title: "Breathing Organic", blurb: "Warm melting surfaces over Turing flux"),
        .init(id: "dmt", title: "Hyperbolic Chamber", blurb: "Dense saturated kaleidoscopic lattices"),
        .init(id: "mescaline", title: "Honeycomb Form", blurb: "Slow honeycombs and form constants"),
        .init(id: "aya", title: "Serpentine Vines", blurb: "Deep vine-like phasor filaments"),
        .init(id: "2cb", title: "Neon Quasicrystal", blurb: "Sharp neon N-fold interference"),
        .init(id: "ket", title: "Dissociative Drift", blurb: "Slow hyperspace / tunnel drift"),
        .init(id: "salvia", title: "Planar Fold", blurb: "Sudden warped planar folds"),
        .init(id: "mdma", title: "Soft Glow Pulse", blurb: "Warm pulsing colour wash"),
        .init(id: "cannabis", title: "Hazy Trails", blurb: "Soft trails and mild warp"),
        .init(id: "n2o", title: "Wobble Spike", blurb: "Short wobbling intensity spikes"),
        .init(id: "5meo", title: "Whiteout Field", blurb: "High-energy near-featureless field"),
        .init(id: "amanita", title: "Dream Lattice", blurb: "Dreamlike soft lattice motion"),
        .init(id: "iboga", title: "Nocturnal Geometry", blurb: "Dark slow nocturnal geometry"),
    ]

    static let disclaimer =
        "Artistic visual interpretations only — not dosing advice, not medical advice; simulator only."

    static func preset(id: String) -> EntheaLookPreset? {
        self.all.first { $0.id == id }
    }
}
