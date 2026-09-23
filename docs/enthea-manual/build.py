#!/usr/bin/env python3
"""Generate docs/enthea-manual/index.html. Run from this directory."""
from pathlib import Path

OUT = Path(__file__).with_name("index.html")

MODES = [
    dict(
        id="form",
        file="mode-00-form-constants.jpg",
        idx="00",
        name="Form Constants",
        strip="FORM CONSTANTS",
        family="Cortical / hallucination",
        tag="Inverse retino-cortical map of cortical plane waves",
        engineer="""Think of primary visual cortex as a 2-D GPU framebuffer whose pixels are orientation-tuned neurons. Simple plane waves on that buffer — stripes, squares, hexagons — are what a Turing instability actually produces. The optic nerve does not deliver a 1:1 picture: ganglion density falls off with eccentricity, so the retina→V1 map is approximately a complex logarithm (Schwartz). Invert that map and a vertical cortical stripe becomes a tunnel, a horizontal stripe becomes a fan, an oblique stripe becomes a spiral, and a superposition becomes a honeycomb. This mode synthesises those cortical planforms and runs them backward through the log map. It is the same transform you would write as <code>z ↦ log(z)</code> if you were sending a texture through a polar warp.""",
        papers=[
            ("Bressloff, Cowan, Golubitsky, Thomas & Wiener (2001)", "Geometric visual hallucinations, Euclidean symmetry and the functional architecture of striate cortex", "https://doi.org/10.1098/rstb.2000.0769"),
            ("Klüver (1966)", "Mescal and Mechanisms of Hallucinations — the four form-constant families", "https://press.uchicago.edu/ucp/books/book/chicago/M/bo3635086.html"),
        ],
        flag="The exact even/odd planform → specific-Klüver-constant table is treated as model interpretation, not a verified lookup table.",
    ),
    dict(
        id="neural",
        file="mode-01-neural-field.jpg",
        idx="01",
        name="Neural Field",
        strip="NEURAL FIELD",
        family="Cortical / hallucination",
        tag="Live Wilson–Cowan field · Turing bifurcation",
        engineer="""This is not a texture. It is a PDE on a 2-D grid, integrated on the GPU every frame: each cell’s activity decays, is convolved with a Mexican-hat kernel (short-range excitation minus long-range inhibition — a difference of Gaussians), then passed through a sigmoid. Below a critical coupling the flat rest state is stable; above it a non-zero spatial frequency goes unstable and stripes/spots appear spontaneously. That is a Turing bifurcation, the same class of instability that makes spots on a leopard. Dose in this app is a gain/coupling knob on that field. Reseed drops a new perturbation so the pattern can settle into a different basin.""",
        papers=[
            ("Ermentrout & Cowan (1979)", "A mathematical theory of visual hallucination patterns", "https://doi.org/10.1007/BF00337467"),
            ("Coombes", "Neural fields — Scholarpedia", "http://www.scholarpedia.org/article/Neural_fields"),
            ("Bressloff et al. (2001)", "The same V1 model, now simulated rather than drawn", "https://doi.org/10.1098/rstb.2000.0769"),
        ],
    ),
    dict(
        id="turing",
        file="mode-02-turing-flux.jpg",
        idx="02",
        name="Turing Flux",
        strip="TURING FLUX",
        family="Reaction–diffusion",
        tag="Gray–Scott morphogenesis",
        engineer="""Two scalar fields U and V live on the same pixel grid. They react (U is consumed to make V) and they diffuse at different rates. Because the inhibitor spreads farther than the activator, a uniform mixture cannot stay uniform: spots, stripes, and labyrinths nucleate from noise. This is Gray–Scott, a well-studied instance of Turing’s 1952 morphogenesis. The shader runs several PDE steps per video frame; nothing is a pre-baked loop. Reseed injects fresh noise. If you have ever implemented a reaction–diffusion demo, this is that demo driving the visualizer.""",
        papers=[
            ("Turing (1952)", "The chemical basis of morphogenesis", "https://doi.org/10.1098/rstb.1952.0012"),
            ("Pearson (1993)", "Complex patterns in a simple system (Gray–Scott phenomenology)", "https://doi.org/10.1126/science.261.5118.189"),
        ],
    ),
    dict(
        id="mandala",
        file="mode-03-sacred-geom.jpg",
        idx="03",
        name="Sacred Geometry",
        strip="SACRED GEOM",
        family="Geometry / symmetry",
        tag="Phyllotaxis · dihedral Dₙ",
        engineer="""Dihedral group Dₙ is the symmetry of a kaleidoscope: n mirrors around a point. Inside that fold sits a Fermat spiral of seeds at the golden angle ψ = 2π(1 − 1/φ) ≈ 137.5°, the same packing sunflowers use because it maximises packing density. You can think of it as instantiating n copies of a point set under rotation, then placing points at radius √k and angle k·ψ. Audio nudges n and the spiral scale so the mandala breathes with the track.""",
        papers=[
            ("Vogel (1979)", "A better way to construct the sunflower head", "https://doi.org/10.1016/0025-5564(79)90080-4"),
            ("Douady & Couder (1992)", "Phyllotaxis as a physical self-organizing process", "https://doi.org/10.1103/PhysRevLett.68.2098"),
        ],
    ),
    dict(
        id="flow",
        file="mode-04-breathing-walls.jpg",
        idx="04",
        name="Breathing Walls",
        strip="BREATHING WALLS",
        family="Flow / texture",
        tag="Domain-warped fractional Brownian motion",
        engineer="""Domain warping is the graphics trick of feeding a noise field back into its own sample coordinates: <code>fBm(p + fBm(p + fBm(p)))</code>. One octave of noise looks like clouds; warping it twice makes slow, coherent spatial folds — the “walls breathing” percept. Persistence (motion trails) is just a feedback buffer, the same idea as a video delay. There is no cortex simulation here; it is a procedural texture that happens to match a commonly reported visual. Inigo Quílez popularised the technique; Mandelbrot supplied the fBm.""",
        papers=[
            ("Quílez", "Domain warping", "https://iquilezles.org/articles/warp/"),
            ("Mandelbrot (1982)", "The Fractal Geometry of Nature", "https://en.wikipedia.org/wiki/The_Fractal_Geometry_of_Nature"),
        ],
    ),
    dict(
        id="hyper",
        file="mode-05-hyperspace.jpg",
        idx="05",
        name="Hyperspace",
        strip="HYPERSPACE",
        family="Geometry / fractal",
        tag="Phenomenological tunnel composite",
        engineer="""A log-polar tunnel (the deepest Klüver constant: radius becomes depth) is kaleidoscoped, then iterated with fractal detail and video feedback. In graphics terms: polar warp + dihedral fold + fBm + a feedback texture. It is a composite of primitives already in the engine, not a new physical model. High dose / high complexity make the chamber denser. ENTHEA flags this as phenomenological, not a pharmacological claim.""",
        papers=[
            ("Strassman (2001)", "DMT: The Spirit Molecule — breakthrough phenomenology (report literature)", "https://www.innertraditions.com/dmt-the-spirit-molecule"),
            ("Shanon (2002)", "The Antipodes of the Mind — ayahuasca visual motifs", "https://academic.oup.com/book/32831"),
        ],
        flag="Artistic composite of reported “breakthrough” geometry, not a measured brain state.",
    ),
    dict(
        id="hyperbolic",
        file="mode-06-hyperbolic.jpg",
        idx="06",
        name="Hyperbolic",
        strip="HYPERBOLIC",
        family="Geometry / fractal",
        tag="Poincaré disk · speculative",
        engineer="""Hyperbolic geometry is the geometry of a saddle: area grows exponentially with radius. The Poincaré disk model packs that infinite plane into a Euclidean unit disk via circle inversions (the isometries of the model). {p,q} tilings shrink toward the boundary exactly because of that exponential area. If you have inverted a point through a circle in a shader, you have the generator. The Qualia Research Institute hypothesised that some DMT geometry is negatively curved; ENTHEA includes the tiling as a frontier idea and labels it unverified.""",
        papers=[
            ("Gomez-Emilsson / QRI", "Hyperbolic Geometry of DMT Experiences (hypothesis, blog-level)", "https://qri.org/blog/hyperbolic-geometry-dmt"),
            ("Schwarz triangle reflections", "Standard construction of hyperbolic {p,q} tilings", "https://en.wikipedia.org/wiki/Schwarz_triangle"),
        ],
        flag="Unverified theoretical hypothesis. Implemented because the math is real; the DMT mapping is not established science.",
    ),
    dict(
        id="entoptic",
        file="mode-07-entoptic.jpg",
        idx="07",
        name="Entoptic",
        strip="ENTOPTIC",
        family="Cortical / hallucination",
        tag="Visual snow · Scheerer’s blue-field",
        engineer="""Entoptic phenomena are generated inside the eye or visual pathway, not out in the world. Visual snow is high-frequency spatiotemporal noise — a dither field. Scheerer’s blue-field effect is white blood cells in retinal capillaries becoming visible against blue light as bright dots on looping paths. This mode is a particle/noise shader: a hashed snow field plus corpuscles advected along capillary-like arcs. It is the “static on the CRT” of the visual system.""",
        papers=[
            ("Scheerer (1924)", "Blue-field entoptic phenomenon", "https://en.wikipedia.org/wiki/Blue_field_entoptic_phenomenon"),
            ("Tyler", "Entoptic vision reviews", "https://en.wikipedia.org/wiki/Entoptic_phenomenon"),
        ],
    ),
    dict(
        id="quasi",
        file="mode-08-quasicrystal.jpg",
        idx="08",
        name="Quasicrystal",
        strip="QUASICRYSTAL",
        family="Waves / tilings",
        tag="N-fold plane-wave interference",
        engineer="""Sum N plane waves at evenly spaced angles: <code>Σ cos(p · uᵢ + φ)</code>. For N = 4 you get a periodic lattice. For N = 5, 7, … you get quasiperiodic order: sharp diffraction peaks, no repeating unit cell, forbidden rotational symmetry. That is the same interference that produces Penrose-like patterns and, in metallurgy, Shechtman’s quasicrystals. Bass shifts φ so the lattice breathes. Symmetry in the host is the LOOKS / dose path into N.""",
        papers=[
            ("de Bruijn (1981)", "Algebraic theory of Penrose’s non-periodic tilings", "https://doi.org/10.1016/1385-7258(81)90016-0"),
            ("Shechtman et al. (1984)", "Metallic phase with long-range orientational order and no translational symmetry", "https://doi.org/10.1103/PhysRevLett.53.1951"),
        ],
    ),
    dict(
        id="cymatics",
        file="mode-09-cymatics.jpg",
        idx="09",
        name="Cymatics",
        strip="CYMATICS",
        family="Waves / tilings",
        tag="Chladni nodal sets",
        engineer="""Chladni figures are the zeros of a vibrating plate: sand gathers where amplitude is zero. On a square plate the eigenmodes look like <code>cos(nπx)cos(mπy) − cos(mπx)cos(nπy) = 0</code>. Mid and treble bands pick (n, m), so the track is literally selecting which standing-wave mode you see. It is the most honest audio visualizer in the set — a plot of the wave equation, not a metaphor.""",
        papers=[
            ("Chladni (1787)", "Entdeckungen über die Theorie des Klanges", "https://en.wikipedia.org/wiki/Ernst_Chladni"),
            ("Wave-equation eigenmodes", "Nodal sets of rectangular membranes / plates", "https://en.wikipedia.org/wiki/Vibrations_of_a_rectangular_membrane"),
        ],
    ),
    dict(
        id="image",
        file="mode-10-image-warp.jpg",
        idx="10",
        name="Image Warp",
        strip="IMAGE WARP",
        family="Instrument",
        tag="Album art → kaleidoscope + palette",
        engineer="""The host loads embedded cover art natively, downscales it, and pushes a JPEG data URL into the WebView. ENTHEA uploads it as a GL texture, kaleidoscopes and domain-warps it, and extracts a 6-colour palette (sampled as a 6×1 blit, converted to linear). If the current track has no artwork the texture stays empty and this mode is quiet. Switching here is automatic when art arrives; you can still land on it with ◀ / ▶.""",
        papers=[
            ("This host", "TrackArtworkLoader → winampEnthea.setCoverArt — no paper; texture + palette pipeline", "https://github.com/elder-plinius/ENTHEA"),
        ],
    ),
    dict(
        id="voronoi",
        file="mode-11-cellular.jpg",
        idx="11",
        name="Cellular",
        strip="CELLULAR",
        family="Flow / texture",
        tag="Worley F1 / F2−F1",
        engineer="""Scatter feature points. Every pixel belongs to its nearest point — that partition is a Voronoi diagram (1908). Worley’s SIGGRAPH trick is to also use the second-nearest distance: F1 shades each cell into a dome (scales); F2−F1 lights the walls (veins). Swapping the metric (L² / L¹ / L∞) reshapes the lattice from round to diamond to square. Bass drives site density. Same primitive as every “cellular noise” node in a shader graph.""",
        papers=[
            ("Worley (1996)", "A cellular texture basis function, SIGGRAPH", "https://doi.org/10.1145/237170.237267"),
            ("Voronoi (1908)", "Nouvelles applications des paramètres continus…", "https://en.wikipedia.org/wiki/Voronoi_diagram"),
        ],
    ),
    dict(
        id="phasor",
        file="mode-12-vines.jpg",
        idx="12",
        name="Vines",
        strip="VINES",
        family="Flow / texture",
        tag="Phasor noise · Gabor kernels",
        engineer="""Sum many oriented Gabor packets as complex numbers, take the argument of the sum, and sine-wave that phase. Contrast never washes out because you are looking at phase, not amplitude — the same reason a PLL stays locked. An fBm orientation field bends the filaments so they branch. This is phasor noise (Tricard et al., SIGGRAPH 2019), a real-time approximation of the spectral construction. Mids/treble twist frequency; it is procedural signal processing, not a vine texture atlas.""",
        papers=[
            ("Tricard et al. (2019)", "Procedural phasor noise, SIGGRAPH", "https://doi.org/10.1145/3306346.3322990"),
            ("Lagae et al. (2009)", "Gabor noise", "https://doi.org/10.1145/1576246.1531396"),
        ],
        flag="Per-pixel kernel sum, not the full spectral phasor-noise construction.",
    ),
    dict(
        id="lizard",
        file="mode-13-dragonscales.jpg",
        idx="13",
        name="Dragonscales",
        strip="DRAGONSCALES",
        family="Reaction–diffusion / life",
        tag="Living cellular automaton on a hex lattice",
        engineer="""The ocellated lizard’s skin was shown in Nature (2017) to be a living cellular automaton: each hexagonal scale flips green/black from its neighbours and settles into a labyrinth — the discrete form of a Turing system. This mode runs that rule on the GPU (short-range agreement, long-range opposition, stochastic flips) and bevels each hex. It is Conway-adjacent, but the neighbourhood and the published biology are specific. Dose is how fast the skin equilibrates; reseed regrows it.""",
        papers=[
            ("Manukyan, Montandon, Fofonjka, Smirnov & Milinkovitch (2017)", "A living mesoscopic cellular automaton made of skin scales", "https://doi.org/10.1038/nature22031"),
            ("Kondo & Miura (2010)", "Reaction-diffusion model as a framework for understanding biological pattern formation", "https://doi.org/10.1126/science.1179047"),
        ],
    ),
    dict(
        id="waveform",
        file="mode-14-waveform.jpg",
        idx="14",
        name="Waveform",
        strip="WAVEFORM",
        family="Instrument",
        tag="Time-domain vectorscope",
        engineer="""Every other mode reads the FFT. This one plots raw PCM: left on X, right on Y — a Lissajous / analog vectorscope. Mono collapses to a diagonal; a wide stereo mix opens into a blob; phase between channels twists it. The host already sends 2048 float samples per channel in the same push as the 512 FFT bins. If you have used a hardware goniometer on a mix bus, this is that display, driven by Winamp’s tap rather than a sound card.""",
        papers=[
            ("Lissajous (1857)", "Parametric X/Y figures of two harmonic signals", "https://en.wikipedia.org/wiki/Lissajous_curve"),
            ("Web Audio AnalyserNode", "getFloatTimeDomainData — the API ENTHEA impersonates", "https://developer.mozilla.org/en-US/docs/Web/API/AnalyserNode/getFloatTimeDomainData"),
        ],
    ),
    dict(
        id="fractal",
        file="mode-15-fractal.jpg",
        idx="15",
        name="Fractal",
        strip="FRACTAL",
        family="Geometry / fractal",
        tag="Raymarched Mandelbox",
        engineer="""A Mandelbox is an iterated map: box-fold (reflect outside a cube), sphere-fold (invert through a sphere), then scale. Distance-estimate the result and sphere-trace a camera through it — the same technique as every shadertoy Mandelbulb flythrough. Bass morphs the fold scale so the architecture breathes. It is escape-time geometry, not a video of a fractal; the camera is a ray marching loop in the uber-shader.""",
        papers=[
            ("Lomas (2010)", "Mandelbox — fractalforums construction", "https://en.wikipedia.org/wiki/Mandelbox"),
            ("Hart et al. (1996)", "Sphere tracing / distance estimators", "https://doi.org/10.1007/s003710050084"),
        ],
    ),
    dict(
        id="particles",
        file="mode-16-particle-flow.jpg",
        idx="16",
        name="Particle Flow",
        strip="PARTICLE FLOW",
        family="Flow / texture",
        tag="50k GPU particles · ABC flow",
        engineer="""Fifty thousand points are advected on the GPU via transform feedback through the Arnold–Beltrami–Childress field, an exact divergence-free solution of Euler’s equations that is chaotic: streamlines braid and never pile up because ∇·u = 0. It is a particle system with a physically honest velocity field, not a curl-noise approximation. Level is speed; bass fattens points; a drop scatters the swarm.""",
        papers=[
            ("Arnold (1965); Childress (1970)", "ABC flow as a Beltrami field", "https://en.wikipedia.org/wiki/Arnold%E2%80%93Beltrami%E2%80%93Childress_flow"),
            ("Dombre et al. (1986)", "Chaotic streamlines of the ABC flow, JFM", "https://doi.org/10.1017/S0022112086002777"),
        ],
    ),
    dict(
        id="weier",
        file="mode-17-weier-wells.jpg",
        idx="17",
        name="Weierstrass Wells",
        strip="WEIER WELLS",
        family="Complex analysis",
        tag="Domain colouring of ℘(z)",
        engineer="""Domain colouring paints a complex function on the plane: hue = arg f, brightness ~ log|f|. The Weierstrass ℘-function is elliptic (doubly periodic) with one double pole per lattice cell, so the phase winds −2 around every lattice point — a theorem, not a style. The shader truncates the Eisenstein sum (a 7×7 neighbourhood). Music shears the lattice modulus τ. If you have ever plotted a meromorphic function in MATLAB with a colour wheel, this is that plot, live.""",
        papers=[
            ("Whittaker & Watson", "A Course of Modern Analysis — ℘", "https://en.wikipedia.org/wiki/Weierstrass_elliptic_function"),
            ("Wegert (2012)", "Visual Complex Functions — phase plots", "https://link.springer.com/book/10.1007/978-3-0348-0180-5"),
            ("DLMF §23", "NIST Digital Library of Mathematical Functions, elliptic functions", "https://dlmf.nist.gov/23"),
        ],
    ),
    dict(
        id="blaschke",
        file="mode-18-blaschke.jpg",
        idx="18",
        name="Blaschke Rosette",
        strip="BLASCHKE",
        family="Complex analysis",
        tag="Finite Blaschke product, coloured by arg B′",
        engineer="""A finite Blaschke product is a holomorphic map of the unit disk to itself: a product of disk automorphisms, one per zero. |B| = 1 on the circle; arg B winds n times; there are n−1 critical points. Colouring arg B′ (angular velocity of the conformal map) is unusual — most portraits colour B itself. Zeros orbit by disk automorphisms, so the flower rotates in the hyperbolic metric. Treat it as a phase portrait of a proper holomorphic map, not a kaleidoscope filter.""",
        papers=[
            ("Garcia, Mashreghi & Ross (2018)", "Finite Blaschke Products and Their Connections", "https://link.springer.com/book/10.1007/978-3-319-78247-8"),
            ("Heins (1941)", "n−1 critical points of a finite Blaschke product", "https://en.wikipedia.org/wiki/Blaschke_product"),
        ],
    ),
    dict(
        id="indra",
        file="mode-19-indra.jpg",
        idx="19",
        name="Indra’s Necklace",
        strip="INDRA",
        family="Geometry / fractal",
        tag="Schottky / Kleinian limit set",
        engineer="""A Schottky group is a free discrete group of Möbius transformations generated by circle inversions. Its limit set is a Cantor necklace of tangent circles — the subject of Mumford, Series & Wright’s Indra’s Pearls. Classically you orbit-plot on the CPU; here each pixel inverse-iterates until escape and uses the running derivative as a distance estimate to light the filament. Same family as Apollonian gaskets and Kleinian-group IFS.""",
        papers=[
            ("Mumford, Series & Wright (2002)", "Indra’s Pearls: The Vision of Felix Klein", "https://en.wikipedia.org/wiki/Indra%27s_Pearls_(book)"),
            ("Maskit (1988)", "Kleinian Groups", "https://link.springer.com/book/10.1007/978-1-4612-1021-4"),
        ],
    ),
    dict(
        id="arnold",
        file="mode-20-arnold.jpg",
        idx="20",
        name="Arnold Tongues",
        strip="ARNOLD",
        family="Dynamics / physics",
        tag="Sine circle map · devil’s staircase",
        engineer="""The sine circle map θ ↦ θ + Ω − (K/2π) sin(2πθ) is the textbook model of two coupled oscillators (drive vs. natural frequency). In the (Ω, K) plane, the winding number locks to rationals p/q on wedge-shaped Arnold tongues; at K = 1 the locked intervals fill measure one (complete devil’s staircase). Horizontal is Ω (the track), vertical is K (loudness). You are looking at a parameter-plane plot of a 1-D iterated map, the same object Strogatz draws in lecture notes.""",
        papers=[
            ("Arnol’d (1961)", "Small denominators and the circle map", "https://en.wikipedia.org/wiki/Arnold_tongue"),
            ("Jensen, Bak & Bohr (1984)", "Complete devil’s staircase, transition to chaos", "https://doi.org/10.1103/PhysRevLett.50.1637"),
        ],
        flag="Winding number estimated from a few dozen iterates; high-order tongues are undersampled. Heaviest mode on weak GPUs.",
    ),
    dict(
        id="gauss",
        file="mode-21-gaussian-halo.jpg",
        idx="21",
        name="Gaussian Halo",
        strip="GAUSSIAN HALO",
        family="Number theory",
        tag="Primes of ℤ[i]",
        engineer="""Gaussian integers are the lattice ℤ[i]. A point a+bi is prime (up to units) iff its norm a²+b² is a rational prime — except on the axes, where it must be a prime ≡ 3 mod 4. Plotting those points gives the famous 4- and 8-fold scatter. Each prime is drawn as a ring whose spatial frequency tracks the norm, so you get number-theoretic moiré. Primality is tested live per pixel (trial division in the truncated window). It is a plot of a ring, not a noise texture.""",
        papers=[
            ("Gauss (1832)", "Biquadratic residues / Gaussian integers", "https://en.wikipedia.org/wiki/Gaussian_integer"),
            ("Hardy & Wright, §12", "An Introduction to the Theory of Numbers — Gaussian primes", "https://en.wikipedia.org/wiki/An_Introduction_to_the_Theory_of_Numbers"),
        ],
    ),
    dict(
        id="defect",
        file="mode-22-defect-gas.jpg",
        idx="22",
        name="Defect Gas",
        strip="DEFECT GAS",
        family="Reaction–diffusion / life",
        tag="Analytic spiral waves around phase defects",
        engineer="""A topological defect of charge ±1 is a point where phase winds by 2π — a branch cut of arg(z − c). Sum several of them, then take cos(θ + radius − ωt), and you get rotating spiral waves around each core, the same geometry as Belousov–Zhabotinsky rotors or cardiac scroll waves. This is closed-form, not a PDE solve: cheap, exact singularities, interacting as the cores wander. Winfree’s rotors, not a reaction–diffusion simulation.""",
        papers=[
            ("Winfree (1972)", "Spiral waves of chemical activity", "https://doi.org/10.1126/science.175.4022.634"),
            ("Mermin (1979)", "The topological theory of defects in ordered media", "https://doi.org/10.1103/RevModPhys.51.591"),
        ],
        flag="Geometry of excitable-media spirals, not the FitzHugh–Nagumo chemistry.",
    ),
    dict(
        id="pentagrid",
        file="mode-23-pentagrid-loom.jpg",
        idx="23",
        name="Pentagrid Loom",
        strip="PENTAGRID LOOM",
        family="Waves / tilings",
        tag="de Bruijn pentagrid · Penrose dual",
        engineer="""Five families of equally spaced lines at 72°. Each cell of the arrangement is named by five integers Kⱼ = ⌊p·eⱼ + γⱼ⌋; the dual of that grid is the Penrose rhombus tiling. Unlike the smooth N-wave QUASICRYSTAL, this is the actual multigrid construction: aperiodic 5-fold order with two rhombus classes. If γⱼ sums away from zero you get a genuine Penrose tiling rather than a periodic approximant.""",
        papers=[
            ("de Bruijn (1981)", "Pentagrid / algebraic Penrose tilings, Indag. Math.", "https://doi.org/10.1016/1385-7258(81)90016-0"),
            ("Penrose (1974)", "Pentaplexity — aperiodic rhombs", "https://en.wikipedia.org/wiki/Penrose_tiling"),
        ],
    ),
    dict(
        id="orbital",
        file="mode-24-atomic-beat.jpg",
        idx="24",
        name="Atomic Beat",
        strip="ATOMIC BEAT",
        family="Dynamics / physics",
        tag="Hydrogenic ψ · quantum beat",
        engineer="""A 2-D slice of hydrogenic orbitals ψₙₗₘ = Rₙₗ(r) Yₗₘ(θ,φ), with associated Laguerre radials and Legendre angular parts. Superpose two stationary states with a relative phase e^{iωt} and |ψ|² sloshes — a real quantum beat (the cross term). Hue is arg ψ, brightness |ψ|², nodes go dark. Bass maps to ω artistically; it is not a physical energy gap. uSym raises ℓ (more lobes); complexity adds shells.""",
        papers=[
            ("Griffiths & Schroeter", "Introduction to Quantum Mechanics, Ch. 4 — hydrogen atom", "https://en.wikipedia.org/wiki/Hydrogen_atom"),
            ("DLMF §14 / §18", "Legendre and Laguerre functions", "https://dlmf.nist.gov/14"),
        ],
        flag="φ = 0 cut of real eigenstates; audio→ω is artistic.",
    ),
    dict(
        id="denom",
        file="mode-25-denom-descent.jpg",
        idx="25",
        name="Denominator Descent",
        strip="DENOM DESCENT",
        family="Number theory",
        tag="Modular group · Farey / Stern–Brocot",
        engineer="""PSL(2,ℤ) is generated by translation T: z ↦ z+1 and inversion S: z ↦ −1/z. Reducing a point of the upper half-plane into the fundamental domain counts continued-fraction length — depth in the Stern–Brocot tree. The walls are Farey arcs to every rational on the real axis (the Dedekind tessellation). Depth colours cells; flux lights the arcs. It is a picture of the modular surface, the same tiling that shows up in complex analysis and in Ford circles.""",
        papers=[
            ("Stern (1858) / Brocot (1861)", "The Stern–Brocot tree", "https://en.wikipedia.org/wiki/Stern%E2%80%93Brocot_tree"),
            ("Series (1985)", "The modular surface and continued fractions", "https://doi.org/10.1112/jlms/s2-31.1.69"),
        ],
    ),
    dict(
        id="wave",
        file="mode-26-wave-crystal.jpg",
        idx="26",
        name="Wave Crystal",
        strip="WAVE CRYSTAL",
        family="Waves / tilings",
        tag="Sine-Gordon breather lattice",
        engineer="""The sine-Gordon equation u_tt − u_xx + sin u = 0 has exact breathers — solitons that stay put and pulse: <code>u = 4 arctan[(κ/ω) sin(ωt) / cosh(κx)]</code> with κ = √(1−ω²). Tile that 1-D profile on a lattice and you get a crystal of oscillating energy knots. Distinct from cymatics (standing linear waves) and from plane-wave interference. Bass rides ω so the cores flash with the low end.""",
        papers=[
            ("Ablowitz et al. (1973)", "Method for solving the sine-Gordon equation", "https://doi.org/10.1103/PhysRevLett.30.1262"),
            ("Lamb (1980)", "Elements of Soliton Theory", "https://en.wikipedia.org/wiki/Sine-Gordon_equation"),
        ],
        flag="Tiled 1-D breather profiles — an evocation of a breather crystal, not an exact 2-D sine-Gordon solution.",
    ),
    dict(
        id="phase",
        file="mode-27-phase-portal.jpg",
        idx="27",
        name="Phase Portal",
        strip="PHASE PORTAL",
        family="Complex analysis",
        tag="Continued-fraction phase portrait",
        engineer="""Evaluate a finite continued fraction f = b₁ + a₂/(b₂ + a₃/(…)) with the Wallis recurrence, coefficients depending on z. The result is a rational function; zeros and poles are counter-rotating pinwheels under domain colouring. Iso-modulus shells telescope. Audio drifts the denominators so singularities migrate and annihilate. The phase portrait is exact for whatever f the coefficients define; the coefficient path itself is an artistic construction (one of the workflow-invented modes).""",
        papers=[
            ("Wegert (2012)", "Visual Complex Functions — phase plots", "https://link.springer.com/book/10.1007/978-3-0348-0180-5"),
            ("Wallis (1656)", "Continued fractions", "https://en.wikipedia.org/wiki/Continued_fraction"),
        ],
        flag="Coefficient drift is artistic; the rendered phase of the resulting meromorphic f is exact.",
    ),
    dict(
        id="vortex",
        file="mode-28-vortex-field.jpg",
        idx="28",
        name="Vortex Condensate",
        strip="VORTEX FIELD",
        family="Dynamics / physics",
        tag="Abrikosov lattice",
        engineer="""In a type-II superconductor or a rotating BEC, magnetic field / angular momentum is quantized into vortices: |ψ| → 0 at each core and arg ψ winds +1. They pack into a triangular (Abrikosov) lattice. This mode builds ψ as a product over nearby cores (tanh amplitude, summed arguments) — a neighbourhood of the lattice, not a solved Gross–Pitaevskii ground state. Dark cores, phase fringes, beat-synced glints.""",
        papers=[
            ("Abrikosov (1957)", "On the magnetic properties of superconductors of the second group (Nobel 2003)", "https://doi.org/10.1016/S0022-3697(57)80091-0"),
            ("Pethick & Smith (2008)", "Bose–Einstein Condensation in Dilute Gases — vortex lattices", "https://doi.org/10.1017/CBO9780511802850"),
        ],
        flag="Finite vortex neighbourhood, not a numerical GP ground state.",
    ),
]

LOOKS = [
    ("lsd", "Electric Lattices", "Bright crisp geometry and colour enhancement", "Form Constants", "Bressloff et al. 2001; Klüver form constants"),
    ("psilo", "Breathing Organic", "Warm melting surfaces over Turing flux", "Breathing Walls (come-up via Turing Flux)", "Domain-warped fBm; Kondo & Miura 2010"),
    ("dmt", "Hyperbolic Chamber", "Dense saturated kaleidoscopic lattices", "Hyperbolic", "Strassman 2001; QRI hyperbolic hypothesis (speculative)"),
    ("mescaline", "Honeycomb Form", "Slow honeycombs and form constants", "Neural Field", "Klüver 1966 — mescaline was the substance he studied"),
    ("aya", "Serpentine Vines", "Deep vine-like phasor filaments", "Vines", "Shanon 2002 — serpentine / vine motifs"),
    ("2cb", "Neon Quasicrystal", "Sharp neon N-fold interference", "Quasicrystal", "Phenomenological SEI; Shulgin PiHKAL"),
    ("ket", "Dissociative Drift", "Slow hyperspace / tunnel drift", "Hyperspace", "Dissociative phenomenology, not serotonergic geometry"),
    ("salvia", "Planar Fold", "Sudden warped planar folds", "Sacred Geometry + shear", "κ-opioid phenomenology; “sheets tearing” reports"),
    ("mdma", "Soft Glow Pulse", "Warm pulsing colour wash", "Breathing Walls (gentle)", "Empathogen: enhancement, not lattice hallucinations"),
    ("cannabis", "Hazy Trails", "Soft trails and mild warp", "Breathing Walls + Entoptic", "Mild tracers over a snow field"),
    ("n2o", "Wobble Spike", "Short wobbling intensity spikes", "Hyperspace (pulsed)", "Brief rhythmic “wah-wah”; hypoxia is a real-world risk, not a visual"),
    ("5meo", "Whiteout Field", "High-energy near-featureless field", "Hyperspace toward void", "Uthaug et al. 2019 — ego-dissolution literature; mostly non-visual"),
    ("amanita", "Dream Lattice", "Dreamlike soft lattice motion", "Wave Crystal", "GABAergic oneirogen; macropsia mapped to breathers"),
    ("iboga", "Nocturnal Geometry", "Dark slow nocturnal geometry", "Breathing Walls (slow)", "Alper 2001; oneirogen / life-review reports, not 5-HT2A lattices"),
]

DROPS = [
    ("Wormhole", "Log-polar punch through the field"),
    ("Supernova", "Exposure blowout + bloom"),
    ("Kaleido shatter", "Dihedral fold snaps to a new n"),
    ("Negative", "Push the grade through inversion"),
    ("Zoom punch", "Transient camera dolly"),
    ("Glitch", "Displacement / slice artifacts"),
    ("Shockwave", "Radial ripple from centre"),
    ("Mandala burst", "Brief Dₙ explosion"),
    ("Time echo", "Feedback delay smear"),
]


def paper_html(papers, flag=None):
    items = "\n".join(
        f'<li><a href="{url}" rel="noopener noreferrer">{title}</a> — {detail}</li>'
        for title, detail, url in papers
    )
    flag_html = f'<p class="flag">{flag}</p>' if flag else ""
    return f"""<aside class="paper">
        <h4>Paper trail</h4>
        <ul>{items}</ul>
        {flag_html}
      </aside>"""


def mode_article(m):
    flag = m.get("flag")
    return f"""
    <article class="mode" id="mode-{m['id']}">
      <figure>
        <img src="shots/{m['file']}" alt="{m['name']} visualization" width="1000" height="1000">
        <figcaption>Mode {m['idx']} · {m['strip']}</figcaption>
      </figure>
      <div class="mode-body">
        <p class="eyebrow">{m['family']}</p>
        <h3>{m['name']}</h3>
        <p class="tag">{m['tag']}</p>
        <p>{m['engineer']}</p>
        {paper_html(m['papers'], flag)}
      </div>
    </article>"""


look_rows = "\n".join(
    f"<tr><td><code>{i}</code></td><td>{title}</td><td>{blurb}</td><td>{mode}</td><td>{paper}</td></tr>"
    for i, title, blurb, mode, paper in LOOKS
)

drop_items = "\n".join(f"<li><strong>{n}.</strong> {d}</li>" for n, d in DROPS)

mode_nav = "\n".join(
    f'<a href="#mode-{m["id"]}">{m["idx"]} {m["strip"]}</a>' for m in MODES
)

mode_articles = "\n".join(mode_article(m) for m in MODES)

HTML = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ENTHEA — User manual (Winamp for macOS)</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:ital,wght@0,400;0,500;0,600;1,400&family=Syne:wght@700;800&display=swap" rel="stylesheet">
  <style>
    :root {{
      --void: #07080d;
      --steel: #242533;
      --chrome: #3a425a;
      --lcd: #00ee00;
      --lcd-dim: #0b4a18;
      --gold: #d4bc58;
      --gold-dark: #8a7328;
      --paper: #e4d7b0;
      --ink: #1a1710;
      --mist: #c8cdd8;
      --warn: #ff6a3d;
      --rule: #3d4458;
    }}
    * {{ box-sizing: border-box; }}
    html {{ scroll-behavior: smooth; }}
    body {{
      margin: 0;
      background: var(--void);
      color: var(--mist);
      font: 400 17px/1.55 "IBM Plex Sans", sans-serif;
    }}
    a {{ color: var(--gold); }}
    a:focus-visible {{ outline: 2px solid var(--lcd); outline-offset: 3px; }}
    code, .mono {{ font-family: "IBM Plex Mono", ui-monospace, monospace; }}
    .wrap {{ max-width: 1080px; margin: 0 auto; padding: 0 1.25rem 4rem; }}
    header.hero {{
      border-bottom: 1px solid var(--rule);
      background:
        linear-gradient(180deg, #12141c 0%, var(--void) 100%);
      padding: 2.2rem 0 1.6rem;
    }}
    .kicker {{
      font-family: "IBM Plex Mono", monospace;
      font-size: 0.72rem;
      letter-spacing: 0.18em;
      text-transform: uppercase;
      color: var(--gold);
      margin: 0 0 0.6rem;
    }}
    h1 {{
      font-family: Syne, sans-serif;
      font-weight: 800;
      font-size: clamp(2.4rem, 6vw, 4.2rem);
      line-height: 0.95;
      color: #f4f1ea;
      margin: 0 0 0.6rem;
      letter-spacing: -0.03em;
    }}
    h1 span {{ color: var(--lcd); }}
    .lede {{ max-width: 46rem; font-size: 1.08rem; color: #d5d8e2; }}
    nav.toc {{
      position: sticky; top: 0; z-index: 5;
      background: rgba(7,8,13,0.92);
      backdrop-filter: blur(8px);
      border-bottom: 1px solid var(--rule);
    }}
    nav.toc .wrap {{
      display: flex; flex-wrap: wrap; gap: 0.55rem 1.1rem;
      padding: 0.65rem 1.25rem;
      font-family: "IBM Plex Mono", monospace;
      font-size: 0.72rem;
      letter-spacing: 0.04em;
    }}
    nav.toc a {{ color: var(--mist); text-decoration: none; }}
    nav.toc a:hover {{ color: var(--lcd); }}
    h2, article.mode, section {{
      scroll-margin-top: 3.2rem;
    }}
    h2 {{
      font-family: Syne, sans-serif;
      font-size: 1.85rem;
      color: #f4f1ea;
      margin: 2.8rem 0 0.8rem;
      letter-spacing: -0.02em;
    }}
    h3 {{ font-size: 1.25rem; color: #f4f1ea; margin: 0 0 0.35rem; }}
    h4 {{ margin: 0 0 0.4rem; font-size: 0.78rem; letter-spacing: 0.12em; text-transform: uppercase; color: var(--gold-dark); }}
    figure {{ margin: 0; }}
    figure img {{
      width: 100%; height: auto; display: block;
      background: #000;
    }}
    figcaption {{
      font-family: "IBM Plex Mono", monospace;
      font-size: 0.72rem;
      color: #8b93a7;
      padding: 0.4rem 0 0;
    }}
    .shot {{
      border: 1px solid var(--rule);
      background: #000;
      margin: 1rem 0 1.4rem;
    }}
    .callouts {{
      position: relative;
      margin: 1.2rem 0 1.6rem;
    }}
    .pins {{
      display: grid;
      grid-template-columns: repeat(6, 1fr);
      gap: 0.4rem;
      margin-top: 0.6rem;
      font-size: 0.88rem;
    }}
    .pin {{
      border: 1px solid var(--rule);
      background: var(--steel);
      padding: 0.55rem 0.6rem 0.65rem;
    }}
    .pin b {{
      font-family: "IBM Plex Mono", monospace;
      color: var(--lcd);
      display: block;
      font-size: 0.72rem;
      margin-bottom: 0.2rem;
    }}
    table {{
      width: 100%; border-collapse: collapse; font-size: 0.92rem;
      margin: 0.8rem 0 1.4rem;
    }}
    th, td {{
      text-align: left; vertical-align: top;
      padding: 0.45rem 0.5rem;
      border-bottom: 1px solid var(--rule);
      overflow-wrap: anywhere;
    }}
    th {{
      font-family: "IBM Plex Mono", monospace;
      font-size: 0.7rem;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--gold);
    }}
    .warn, .pact {{
      border-left: 3px solid var(--warn);
      background: #1a100c;
      padding: 0.85rem 1rem;
      margin: 1rem 0;
    }}
    .pact {{ border-color: var(--gold); background: #14120c; }}
    .paper {{
      background: var(--paper);
      color: var(--ink);
      padding: 0.85rem 1rem 0.7rem;
      margin: 1rem 0 0;
      box-shadow: 3px 3px 0 #000;
    }}
    .paper a {{ color: #5c3b00; }}
    .paper ul {{ margin: 0.2rem 0 0; padding-left: 1.1rem; }}
    .flag {{
      font-size: 0.88rem;
      font-style: italic;
      margin: 0.55rem 0 0;
    }}
    .mode {{
      display: grid;
      grid-template-columns: minmax(0, 42%) minmax(0, 1fr);
      gap: 1.2rem;
      padding: 1.4rem 0;
      border-top: 1px solid var(--rule);
    }}
    .eyebrow {{
      font-family: "IBM Plex Mono", monospace;
      font-size: 0.68rem;
      letter-spacing: 0.16em;
      text-transform: uppercase;
      color: var(--lcd);
      margin: 0 0 0.25rem;
    }}
    .tag {{ color: #9aa3b8; font-size: 0.92rem; margin-top: 0; }}
    .mode-index {{
      display: flex; flex-wrap: wrap; gap: 0.35rem;
      margin: 0.6rem 0 1.2rem;
    }}
    .mode-index a {{
      font-family: "IBM Plex Mono", monospace;
      font-size: 0.68rem;
      text-decoration: none;
      color: var(--mist);
      border: 1px solid var(--rule);
      padding: 0.2rem 0.4rem;
    }}
    .mode-index a:hover {{ border-color: var(--lcd); color: var(--lcd); }}
    .pipe {{
      font-family: "IBM Plex Mono", monospace;
      font-size: 0.78rem;
      background: #0e1018;
      border: 1px solid var(--rule);
      padding: 0.9rem 1rem;
      overflow-x: auto;
      color: var(--lcd);
      line-height: 1.45;
    }}
    .two {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 1rem;
    }}
    footer.site {{
      border-top: 1px solid var(--rule);
      margin-top: 3rem;
      padding-top: 1.2rem;
      font-size: 0.85rem;
      color: #8b93a7;
    }}
    @media (max-width: 820px) {{
      .mode, .two, .pins {{ grid-template-columns: 1fr; }}
    }}
    @media (prefers-reduced-motion: reduce) {{
      html {{ scroll-behavior: auto; }}
    }}
  </style>
</head>
<body>
  <header class="hero">
    <div class="wrap">
      <p class="kicker">Winamp for macOS · visualizer panel</p>
      <h1>ENTHEA <span>manual</span></h1>
      <p class="lede">
        A field guide to the ENTHEA visualizer hosted inside this Classic Winamp player.
        Every control on the pledit chrome, every look, every one of the 29 GPU modes —
        with the neuroscience and mathematics behind it explained the way you would explain
        a shader and a signal path to another computer engineer.
      </p>
    </div>
  </header>
  <nav class="toc" aria-label="Sections">
    <div class="wrap">
      <a href="#open">Open</a>
      <a href="#anatomy">Anatomy</a>
      <a href="#controls">Controls</a>
      <a href="#signal">Signal path</a>
      <a href="#drops">Drops</a>
      <a href="#looks">Looks</a>
      <a href="#modes">Modes</a>
      <a href="#host">This host vs upstream</a>
      <a href="#refs">Bibliography</a>
    </div>
  </nav>

  <main class="wrap">
    <section id="pact">
      <h2>Read this first</h2>
      <div class="warn">
        <p><strong>Photosensitivity.</strong> ENTHEA draws bright, rapidly changing patterns.
        The first time you open the panel, the app shows a notice. Flicker drive stays
        <em>off</em> in this host. If you have photosensitive epilepsy or migraine, close the Visualizer.</p>
      </div>
      <div class="pact">
        <p><strong>Simulator only.</strong> Looks are artistic interpretations of reported visual
        phenomenology — not dosing advice, not sourcing, not medical advice.
        Upstream ENTHEA’s own pact, which this host inherits:</p>
        <p style="margin-bottom:0">“This is a simulator — visual phenomenology rendered from math.”
        — <a href="https://github.com/elder-plinius/ENTHEA">elder-plinius/ENTHEA</a></p>
      </div>
      <p>
        The visualizer is a vendored copy of <a href="https://github.com/elder-plinius/ENTHEA">ENTHEA</a>
        (© Pliny / elder-plinius, AGPL-3.0), pinned at commit
        <code>f8eaf39d</code>, running in a <code>WKWebView</code>. The research backbone is
        <a href="https://github.com/elder-plinius/ENTHEA/blob/main/SCIENCE.md">SCIENCE.md</a>
        in that repository. The model at the centre of the cortical modes is
        <strong>Bressloff–Cowan–Golubitsky–Thomas–Wiener (2001)</strong>.
      </p>
    </section>

    <section id="open">
      <h2>Opening the panel</h2>
      <p>
        ENTHEA is not an inline widen of the main player. It is a separate managed window
        in the same docking system as the equalizer and playlist. It starts <strong>closed</strong>.
      </p>
      <div class="two">
        <figure class="shot">
          <img src="shots/main.jpg" alt="Classic main player with mini spectrum">
          <figcaption>Main player. The 76×16 mini spectrum is the ENTHEA door.</figcaption>
        </figure>
        <figure class="shot">
          <img src="shots/spectrum.jpg" alt="Mini FFT spectrum on the main window">
          <figcaption>Mini LCD — Metal, not WebKit. Double-click opens ENTHEA.</figcaption>
        </figure>
      </div>
      <table>
        <thead><tr><th>Action</th><th>What happens</th></tr></thead>
        <tbody>
          <tr><td>Double-click the mini spectrum (main window or shade strip)</td><td>Show / hide the Visualizer panel</td></tr>
          <tr><td>Title-bar options menu (left of “WINAMP” / “RE:AMP”) → <strong>Show Visualizer</strong></td><td>Same toggle</td></tr>
          <tr><td>Close box on the ENTHEA title bar, or <strong>Hide Visualizer</strong></td><td>Tears down the WebView (WebContent process exits)</td></tr>
        </tbody>
      </table>
      <p>
        The mini spectrum stays Metal on purpose. Embedding a second WebView in a 76×16 slot
        would be absurd; double-click is the handoff into the real panel.
      </p>
    </section>

    <section id="anatomy">
      <h2>Anatomy of the window</h2>
      <figure class="shot">
        <img src="shots/overview.jpg" alt="Winamp Classic layout with ENTHEA docked to the right">
        <figcaption>Default dock: main + EQ + playlist in a column; ENTHEA to the right of main.</figcaption>
      </figure>
      <figure class="shot">
        <img src="shots/panel.jpg" alt="ENTHEA panel showing Hyperspace">
        <figcaption>The panel body is ENTHEA’s WebGL2 canvas. Classic pledit chrome wraps it.</figcaption>
      </figure>
      <p>Three chrome bands, from top to bottom:</p>
      <ol>
        <li><strong>Title bar</strong> — drag the window; theater / shade / close on the right.</li>
        <li><strong>Control strip</strong> — every live visualizer command lives here.</li>
        <li><strong>Bottom bar</strong> — pledit footer; resize from the bottom-right grip.</li>
      </ol>
      <figure class="shot">
        <img src="shots/titlebar.jpg" alt="ENTHEA title bar">
        <figcaption>Title bar. The three right-hand hits are theater, shade, close (clear hit targets on the skin squares).</figcaption>
      </figure>
    </section>

    <section id="controls">
      <h2>Every control</h2>
      <figure class="callouts">
        <div class="shot">
          <img src="shots/strip.jpg" alt="ENTHEA control strip">
        </div>
        <div class="pins">
          <div class="pin"><b>1 · ◀</b> Previous mode. Hold ⇧ to lower dose instead.</div>
          <div class="pin"><b>2 · Title</b> Click: autopilot on/off. Double-click: reseed.</div>
          <div class="pin"><b>3 · LOOKS</b> Artistic visual signatures. Disables autopilot.</div>
          <div class="pin"><b>4 · 💥</b> Force a drop effect from the nine-effect arsenal.</div>
          <div class="pin"><b>5 · ⛶</b> Theater (fill the display). Icon becomes ▣ while there.</div>
          <div class="pin"><b>6 · ▶</b> Next mode. Hold ⇧ to raise dose instead.</div>
        </div>
      </figure>

      <h3>1–6 · Mode previous / next</h3>
      <p>
        Cycles the 29-mode list (see <a href="#modes">Modes</a>). Clicking either arrow
        <strong>turns autopilot off</strong> so you keep the mode you picked.
        The strip title then reads <code>ENTHEA • MODE NAME</code> instead of
        <code>ENTHEA • AUTOPILOT</code>.
      </p>

      <h3>⇧ + ◀ / ▶ · Dose</h3>
      <p>
        Dose is a 0…1 scalar inside ENTHEA. In cortical modes it is coupling/gain
        (how hard the Turing instability is driven). In others it scales warp, saturation,
        void, or pulse. Each nudge is ±0.05. There is no on-screen dose readout in this host;
        you feel it. Upstream ENTHEA binds this to the arrow keys — those keys are
        <strong>neutered</strong> here so they stay with volume / playlist.
      </p>

      <h3>2 · Strip title · Autopilot</h3>
      <p>
        Autopilot (upstream “journey”) crossfades through modes like a directed show,
        with scene transitions, rather than a hard cut. It defaults <strong>on</strong>
        and is persisted. Click the title to toggle. Pick a LOOK or a manual mode and
        autopilot turns off so it cannot yank you away.
      </p>

      <h3>2 · Double-click title · Reseed</h3>
      <p>
        Sets <code>S.reseed = 2</code>. Reaction–diffusion, neural-field, and lizard-scale
        modes are initial-value problems: they remember their grid. Reseed drops a new
        perturbation so the PDE can fall into a different pattern. Harmless on modes that
        are pure closed-form functions.
      </p>

      <h3>3 · LOOKS</h3>
      <p>
        Fourteen phenomenological presets. Each one is an ENTHEA <code>SUBSTANCES</code>
        profile applied as a <em>visual signature only</em> (mode + palette + dose + FX).
        This host does <strong>not</strong> start the timed come-up→peak “trip arc”
        (<code>beginTrip</code> is never called). Copy in the menu is deliberately
        non-medical: “Electric Lattices”, not “LSD”. Full table under <a href="#looks">Looks</a>.
      </p>

      <h3>4 · 💥 · Force drop</h3>
      <p>
        Fires one of nine festival-grade effects immediately, without waiting for the
        predictive timeline. Same entry point as a detected drop. See <a href="#drops">Drops</a>.
      </p>

      <h3>5 · Theater</h3>
      <p>
        Expands the panel to the display frame (including the menu-bar / notch band),
        hides pledit chrome, keeps the same WebView (so in-page state survives).
        This is <em>not</em> <code>NSWindow.toggleFullScreen</code> — the window is borderless.
      </p>
      <table>
        <thead><tr><th>Enter</th><th>Exit</th></tr></thead>
        <tbody>
          <tr><td>⛶ on the strip, title-bar theater hit, or <kbd>F</kbd> while the visualizer is key</td>
              <td><kbd>Escape</kbd>, <kbd>F</kbd> again, or ▣ on the strip</td></tr>
        </tbody>
      </table>

      <h3>Title bar · Shade / close / drag</h3>
      <table>
        <thead><tr><th>Control</th><th>Behaviour</th></tr></thead>
        <tbody>
          <tr><td>Drag the title (not the three right buttons)</td><td>Move the panel; docking / snapping still apply</td></tr>
          <tr><td>Shade (middle square) or double-click title</td><td>Windowshade: body unmounts, WebView tears down, strip of pledit shade remains</td></tr>
          <tr><td>Close (X)</td><td><code>showVisualizer = false</code></td></tr>
        </tbody>
      </table>

      <h3>Resize grip</h3>
      <p>
        Bottom-right of the pledit footer. Width cannot go below the Classic main width
        (275 × Zoom); height has a minimum so the strip stays usable. Backing resolution
        is clamped to a ~2.0 megapixel budget so theater does not drop to 24 fps on heavy modes.
      </p>

      <h3>Keys that still work — and keys that do not</h3>
      <p>
        ENTHEA’s own keyboard (space cycles mode, <kbd>A</kbd> autopilot, <kbd>D</kbd> drop,
        <kbd>1</kbd>–<kbd>8</kbd>, …) is killed at capture phase so Space stays play/pause
        and playlist hotkeys keep working. The host remaps a subset onto the strip and <kbd>F</kbd> / Escape.
      </p>
    </section>

    <section id="signal">
      <h2>Signal path</h2>
      <p>
        ENTHEA is worth vendoring because of its analysis chain, not because of a skin.
        The host does <em>not</em> invent a feature contract. It impersonates a Web Audio
        <code>AnalyserNode</code> and lets ENTHEA’s own DSP run unmodified.
      </p>
      <pre class="pipe">AVAudioEngine
  → FFTSpectrumAnalyzer          1024-point FFT, 512 linear bins
  → AudioFeatureBus              raw bins + 2048 PCM L/R  (unsmoothed)
  → EntheaAudioBridge            ~30 Hz small panel, ~60 Hz large/theater
  → bridge.js fake AnalyserNode
  → ENTHEA updateAudio()         7 bands, centroid, flux, onsets, BPM,
                                 beat grid, build envelope, drop detect,
                                 crest, zero-crossing rate
  → GLSL uber-shader             29 modes, one program, uMode branches</pre>
      <p>
        Why 512 linear bins instead of the 32 log bands the Metal mini-viz uses:
        ENTHEA indexes frequency linearly and computes spectral flux as a bin-wise
        frame difference. Upsampling 32 log bands would stair-step; flux would be
        ~zero except at the handful of step edges; beat lock would fail silently
        while the picture still “moved.”
      </p>
      <p>
        Playback stopped, panel shaded/hidden, or window occluded: render loop goes to
        0 fps and audio IPC pauses. Showing the panel again reboots the WebView in
        a few hundred milliseconds.
      </p>
      <h3>The Bressloff–Cowan pipeline (cortical modes)</h3>
      <p>
        For Form Constants / Neural Field, the research story is a pipeline you can
        read as a graphics graph:
      </p>
      <pre class="pipe">Wilson–Cowan / Amari neural field on a 2-D cortical grid
  → Turing instability → stripes / squares / hexagons
  → inverse Schwartz complex-log map  (retina ← V1)
  → Klüver’s four form constants
      tunnels/funnels · spirals · lattices/honeycombs · cobwebs</pre>
      <p>
        Schwartz’s map is the reason a stripe on cortex does not look like a stripe
        in the world: ganglion density <code>ρ ∝ 1/(w₀ + ε r)²</code> (Drasdo 1977;
        w₀ = 0.087, ε = 0.051). Far from the fovea it is just <code>log(z)</code> —
        circles on the retina become vertical V1 stripes, rays become horizontal,
        log-spirals become oblique. Invert that, and the zoo of geometric hallucination
        falls out. Full equations:
        <a href="https://github.com/elder-plinius/ENTHEA/blob/main/SCIENCE.md">SCIENCE.md</a>.
      </p>
    </section>

    <section id="drops">
      <h2>Drops</h2>
      <p>
        Two clocks feed the same 💥 arsenal.
      </p>
      <h3>Predictive (automatic)</h3>
      <p>
        When a track starts, <code>EntheaTrackAnalyzer</code> reads the file natively
        in Swift (never handed to WebKit), walks a hop-framed energy envelope, and
        emits drop times plus low/high energy sections. That object is assigned to
        ENTHEA’s <code>S.timeline</code>; a shim <code>AUDIO.fileEl.currentTime</code>
        follows the real playhead. ENTHEA can therefore ramp tension <em>before</em>
        the downbeat — the same idea as a DAW locator, not a reactive threshold on
        the live FFT.
      </p>
      <h3>Forced (💥)</h3>
      <p>Bypasses the timeline and fires immediately. AUTO picks a fresh effect each time:</p>
      <ul>{drop_items}</ul>
    </section>

    <section id="looks">
      <h2>Looks</h2>
      <p>
        Menu label → visual signature. Ids in <code>EntheaLookPreset</code> match
        upstream <code>SUBSTANCES</code>. Receptor→feature mapping is
        <strong>not</strong> established science (ENTHEA’s own SCIENCE.md marks it
        refuted / phenomenological). These are shader presets with research-flavoured names.
      </p>
      <table>
        <thead>
          <tr><th>Id</th><th>Menu</th><th>Looks like</th><th>Lands on</th><th>Why that mapping</th></tr>
        </thead>
        <tbody>
          {look_rows}
        </tbody>
      </table>
      <p class="pact" style="margin-top:0">Artistic visual interpretations only — not dosing advice, not medical advice; simulator only.</p>
    </section>

    <section id="modes">
      <h2>The 29 modes</h2>
      <p>
        One GLSL uber-shader, 29 <code>uMode</code> branches. Ten of the later modes
        were proposed by a multi-agent “math-mining” workflow in the original project
        and then turned into shaders — they are honest mathematical objects, not stock
        MilkDrop presets. Screenshots below are the live WebGL canvas.
      </p>
      <div class="mode-index">{mode_nav}</div>
      {mode_articles}
    </section>

    <section id="host">
      <h2>This host vs original ENTHEA</h2>
      <p>
        Upstream is a single HTML file meant to run in Chrome with mic, tab capture,
        MIDI, and its own HUD.
        <a href="https://github.com/elder-plinius/ENTHEA">github.com/elder-plinius/ENTHEA</a>.
        This app hides that HUD on boot and drives the engine from native playback.
      </p>
      <table>
        <thead><tr><th>Upstream control</th><th>In this Winamp host</th></tr></thead>
        <tbody>
          <tr><td>Mic / file / tab audio</td><td>Native AVAudioEngine tap only. No mic, no drone, no tab capture.</td></tr>
          <tr><td>Keyboard (space, A, D, 1–8, …)</td><td>Disabled. Collides with play/pause and playlist keys.</td></tr>
          <tr><td>Flicker ~10 Hz</td><td>Forced off. Alpha-band photic drive is real science (Ganzflicker) and also a seizure risk.</td></tr>
          <tr><td>Wallpaper lens (17 wallpaper groups)</td><td>Not exposed.</td></tr>
          <tr><td>Breath pacer, math HUD, MIDI-learn, snapshots</td><td>Not exposed.</td></tr>
          <tr><td>Begin trip arc (timed come-up)</td><td>Not started. LOOKS apply the visual signature only.</td></tr>
          <tr><td>Upload image</td><td>Automatic from embedded album art → Image Warp.</td></tr>
          <tr><td>Fullscreen</td><td>Host theater on the panel window, not the page’s <code>requestFullscreen</code>.</td></tr>
        </tbody>
      </table>
      <figure class="shot">
        <img src="shots/playlist.jpg" alt="Playlist panel">
        <figcaption>Playlist stays a Classic pledit. ENTHEA never sees the files; Swift analyses them offline.</figcaption>
      </figure>
    </section>

    <section id="refs">
      <h2>Bibliography</h2>
      <p>
        Canonical write-up, with verified vs speculative called out in situ:
        <a href="https://github.com/elder-plinius/ENTHEA/blob/main/SCIENCE.md">ENTHEA SCIENCE.md</a>.
        Vendor pin and patch list: <code>Resources/Enthea/VENDOR.md</code>.
      </p>
      <ul>
        <li>Bressloff, Cowan, Golubitsky, Thomas &amp; Wiener (2001). <em>Phil. Trans. R. Soc. B</em> 356:299–330. <a href="https://doi.org/10.1098/rstb.2000.0769">doi:10.1098/rstb.2000.0769</a></li>
        <li>Ermentrout &amp; Cowan (1979). <em>Biol. Cybernetics</em> 34:137.</li>
        <li>Turing (1952). The chemical basis of morphogenesis. <a href="https://doi.org/10.1098/rstb.1952.0012">doi:10.1098/rstb.1952.0012</a></li>
        <li>Pearson (1993). Complex patterns in a simple system. <a href="https://doi.org/10.1126/science.261.5118.189">doi:10.1126/science.261.5118.189</a></li>
        <li>Klüver (1966). <em>Mescal and Mechanisms of Hallucinations</em>.</li>
        <li>Manukyan et al. (2017). A living mesoscopic cellular automaton made of skin scales. <a href="https://doi.org/10.1038/nature22031">doi:10.1038/nature22031</a></li>
        <li>Kondo &amp; Miura (2010). Reaction-diffusion model as a framework for understanding biological pattern formation. <a href="https://doi.org/10.1126/science.1179047">doi:10.1126/science.1179047</a></li>
        <li>Shenyan et al. (2024). Ganzflicker. <em>Scientific Reports</em>. <a href="https://doi.org/10.1038/s41598-024-52372-1">doi:10.1038/s41598-024-52372-1</a></li>
        <li>Ottosson (2020). OKLab. <a href="https://bottosson.github.io/posts/oklab/">bottosson.github.io/posts/oklab</a></li>
        <li>de Bruijn (1981). Algebraic theory of Penrose’s non-periodic tilings.</li>
        <li>Shechtman et al. (1984). Quasicrystals. <a href="https://doi.org/10.1103/PhysRevLett.53.1951">doi:10.1103/PhysRevLett.53.1951</a></li>
        <li>Worley (1996). A cellular texture basis function. SIGGRAPH.</li>
        <li>Tricard et al. (2019). Procedural phasor noise. SIGGRAPH.</li>
        <li>Mumford, Series &amp; Wright (2002). <em>Indra’s Pearls</em>.</li>
        <li>Arnol’d (1961); Jensen, Bak &amp; Bohr (1984). Circle map / devil’s staircase.</li>
        <li>Abrikosov (1957). Vortex lattice in type-II superconductors.</li>
        <li>Winfree (1972). Spiral waves of chemical activity.</li>
        <li>Vogel (1979); Douady &amp; Couder (1992). Phyllotaxis.</li>
        <li>Chladni (1787). Theory of sound / nodal figures.</li>
        <li>Strassman (2001); Shanon (2002) — phenomenological sources, not V1 models.</li>
      </ul>
    </section>

    <footer class="site">
      <p>
        Manual generated for this private Winamp macOS fork. ENTHEA is
        <a href="https://github.com/elder-plinius/ENTHEA">elder-plinius/ENTHEA</a>, AGPL-3.0.
        Screenshots of the Classic chrome are from a live Debug build; mode plates are
        the vendored WebGL canvas.
      </p>
    </footer>
  </main>
</body>
</html>
"""

OUT.write_text(HTML, encoding="utf-8")
print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
