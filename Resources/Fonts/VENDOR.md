# Bundled font provenance

## Roboto Mono (UI theme)

| File | Source | Version |
|------|--------|---------|
| `RobotoMono-Regular.ttf` | [googlefonts/RobotoMono](https://github.com/googlefonts/RobotoMono) `fonts/ttf/RobotoMono-Regular.ttf` | v3.001 |
| `RobotoMono-Medium.ttf` | [googlefonts/RobotoMono](https://github.com/googlefonts/RobotoMono) `fonts/ttf/RobotoMono-Medium.ttf` | v3.001 |
| `RobotoMono-SemiBold.ttf` | Generated locally (see below) | v3.001 base |
| `RobotoMono-LICENSE.txt` | [googlefonts/RobotoMono](https://github.com/googlefonts/RobotoMono) `OFL.txt` | v3.001 |

License: SIL Open Font License 1.1 (`RobotoMono-LICENSE.txt`). Retain the license text in app distributions.

### SemiBold static face

Upstream v3.001 ships static TTFs for Regular, Medium, Bold, Light, Thin, and italics under `fonts/ttf/`, but **no static SemiBold**. Searched:

- `https://github.com/googlefonts/RobotoMono` tag `v3.001` — no `*SemiBold*` under `fonts/ttf/` or `fonts/otf/`
- Google Fonts `ofl/robotomono` static export — same set (no SemiBold)

`RobotoMono-SemiBold.ttf` is therefore instanced from the official variable font
`fonts/variable/RobotoMono[wght].ttf` at `wght=600`, with the PostScript name set to
`RobotoMono-SemiBold` and `usWeightClass` 600. Regenerate reproducibly:

```bash
cd scripts
./generate-robotomono-semibold.sh
```

## JetBrains Mono (Classic skin)

Existing bundled faces; unchanged by Task 3. See JetBrains Mono project for upstream license terms.
