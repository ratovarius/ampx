#!/usr/bin/env python3
"""Generate auditable, manually measured Player landmarks and annotations.
Run from scripts/: uv run python measure_reference.py ../screenshots/AmpX.png
No automatic-design claims, unmeasured EQ/Playlist values, or canonical overrides.
"""
import argparse
import hashlib
import json
from pathlib import Path
from statistics import median
from PIL import Image, ImageDraw, ImageFont

SCALE = 2
PANEL = (10, 7, 980, 447)  # Excludes only the soft outer fringe.
ORIGIN = (10, 64)  # Content origin; header/frame seam starts at y=62.
# group | name | visible source x,y,w,h; ±2 source-pixel edge uncertainty.
LANDMARK_TEXT = '''frame|panel|10,7,980,447
frame|content.frame|24,62,952,379
header|header|10,7,980,57
header|header.brand|449,19,100,36
header|header.gripGlyph|29,21,36,32
header|header.leftLine.top|85,26,325,7
header|header.leftLine.bottom|85,38,325,7
header|header.rightLine.top|582,26,238,7
header|header.rightLine.bottom|582,38,238,7
header|header.minimize|834,17,40,40
header|header.collapse|886,17,40,40
header|header.close|937,17,40,40
display|display.well|37,84,336,190
display|display.blackInterior|41,89,328,181
display|display.playGlyph|80,106,28,36
display|display.timer|179,100,164,51
timer|display.timer.digit0|179,101,29,50
timer|display.timer.digit1|229,101,9,49
timer|display.timer.colon|253,112,13,28
timer|display.timer.digit5|282,101,28,50
timer|display.timer.last1|331,101,12,49
display|display.spectrum|76,178,275,82
display|display.channelL|48,192,18,27
display|display.channelR|48,234,18,27
metadata|track.well|385,84,577,63
metadata|track.text|397,100,429,28
metadata|metadata.bitrateWell|385,156,79,50
metadata|metadata.bitrateInk|397,168,51,25
metadata|metadata.kbps|474,171,53,27
metadata|metadata.sampleRateWell|558,157,66,49
metadata|metadata.sampleRateInk|574,168,33,25
metadata|metadata.kHz|635,171,41,23
metadata|metadata.mono|791,175,60,18
metadata|metadata.stereo|871,171,82,22
sliders|volume.track|387,235,211,22
sliders|volume.coloredInterior|393,240,199,12
sliders|volume.thumb|515,230,43,40
sliders|balance.track|615,235,134,22
sliders|balance.coloredInterior|622,240,120,12
sliders|balance.thumb|661,230,43,40
sliders|toggle.eq|763,218,93,57
sliders|toggle.eq.indicator|776,234,20,24
sliders|toggle.eq.label|807,235,26,24
sliders|toggle.pl|866,218,95,57
sliders|toggle.pl.indicator|878,234,21,24
sliders|toggle.pl.label|911,235,27,24
sliders|position.well|37,287,925,39
sliders|position.trackInterior|46,296,908,22
sliders|position.thumb|451,292,95,32
transport|transport.previous|38,343,88,77
transport|transport.play|132,343,92,77
transport|transport.pause|229,343,84,77
transport|transport.stop|321,343,87,77
transport|transport.next|417,343,87,77
transport|transport.eject|515,343,94,77
transport|transport.shuffle|617,343,168,77
transport|transport.repeat|791,343,85,77
transport|transport.menu|893,348,67,71
glyphs|transport.previous.glyph|67,365,29,32
glyphs|transport.play.glyph|166,366,27,31
glyphs|transport.pause.glyph|259,367,24,29
glyphs|transport.stop.glyph|353,369,25,25
glyphs|transport.next.glyph|448,365,28,32
glyphs|transport.eject.glyph|547,368,30,29
glyphs|transport.shuffle.indicator|634,366,21,25
glyphs|transport.shuffle.label|668,372,93,20
glyphs|transport.repeat.glyph|815,365,37,32
glyphs|transport.menu.glyph|911,369,31,28'''
PATCHES = {
    'display.black': (51,152,5,5), 'panel.interior': (700,210,5,5),
    'button.face': (145,352,5,5), 'button.topHighlight': (142,346,10,1),
    'button.leftHighlight': (135,355,1,10), 'button.bottomShadow': (145,416,10,1),
    'frame.highlight': (50,64,10,1), 'frame.darkEdge': (50,66,10,1),
    'thumb.steelFace': (522,237,5,5), 'thumb.steelHighlight': (522,233,10,1),
    'thumb.goldFace': (475,312,10,3), 'thumb.goldHighlight': (467,295,20,1),
}


def converted(rect, origin):
    x,y,w,h = rect
    return [(x-origin[0])/SCALE,(y-origin[1])/SCALE,w/SCALE,h/SCALE]


def lit_runs(im, x):
    runs, start = [], None
    for y in range(205,261):
        r,g,b = im.getpixel((x,y)) if y < 260 else (0,0,0)
        lit = g > 130 and g > b*1.8
        if lit and start is None:
            start = y
        elif not lit and start is not None:
            runs.append([start,y-start])
            start = None
    return runs


def generate(path, output):
    im = Image.open(path).convert('RGB')
    if im.size != (998,1576):
        raise ValueError('Remeasure landmarks for any other source dimensions.')
    output.mkdir(parents=True,exist_ok=True)
    records = []
    for i,line in enumerate(LANDMARK_TEXT.splitlines(),1):
        group,name,raw = line.split('|')
        rect = list(map(int,raw.split(',')))
        x,y,w,h = rect
        assert w > 0 and h > 0 and 0 <= x < x+w <= im.width and 0 <= y < y+h <= im.height
        records.append(dict(id=i,name=name,sourceRect=rect,group=group,
            moduleRect=converted(rect,PANEL[:2]),contentRect=converted(rect,ORIGIN),
            method='manual visible-edge/ink measurement; inspect annotation',edgeUncertaintySourcePx=2))
    colors = {}
    for name,(x,y,w,h) in PATCHES.items():
        values = list(im.crop((x,y,x+w,y+h)).get_flattened_data())
        rgb = [round(median(p[c] for p in values)) for c in range(3)]
        colors[name] = dict(sourcePatch=[x,y,w,h],rgb=rgb,hex='#'+''.join(f'{c:02X}' for c in rgb))
    # Pixel profiles preserve layer widths/gradients without pretending one color
    # sample specifies an entire material. Coordinates are source pixels.
    profiles = {}
    for name,x,y,w,h in (
        ('button.topEdge',150,342,1,12),
        ('button.bottomEdge',150,409,1,12),
        ('frame.topEdge',100,5,1,14),
        ('well.topEdge',400,81,1,12),
        ('steelThumb.topEdge',530,228,1,16),
        ('goldThumb.topEdge',480,290,1,22),
    ):
        profiles[name] = dict(sourcePatch=[x,y,w,h],
            rgb=[list(im.getpixel((x,y+dy))) for dy in range(h)])
    scans = {str(x):lit_runs(im,x) for x in (81,99,116,134)}
    heights = [h for runs in scans.values() for _,h in runs]
    gaps = [b[0]-a[0]-a[1] for runs in scans.values() for a,b in zip(runs,runs[1:])]
    spectrum = dict(sourceRuns=scans,medianLitHeightSourcePx=median(heights) if heights else None,
        medianGapSourcePx=median(gaps) if gaps else None,
        note='Thresholded bright cores at y=205..259; glow excluded. No fallback or canonical override.')
    by_name = {r['name']:r for r in records}
    travel = {}
    for prefix,track in [('volume','volume.coloredInterior'),('balance','balance.coloredInterior'),('position','position.trackInterior')]:
        x,y,w,h = by_name[track]['sourceRect']
        tw = by_name[prefix+'.thumb']['sourceRect'][2]
        travel[prefix] = dict(sourceCenterEndpoints=[x+tw/2,x+w-tw/2],
            method='derived inset-travel proposal; NOT observable from this single pose',
            hitBounds='not observable; define during implementation without enlarging artwork')
    payload = dict(version='ReferenceMeasurementsV2',scope='Player only',
        source='screenshots/AmpX.png',sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        imageSize=list(im.size),sourceScale=SCALE,panelSourceRect=list(PANEL),
        moduleOrigin=list(PANEL[:2]),contentOrigin=list(ORIGIN),headerHeightLogical=28.5,
        convention='x,y,width,height; right/bottom exclusive. Frame includes bevel, excludes soft fringe.',
        records=records,colorSamples=colors,edgeProfiles=profiles,spectrum=spectrum,proposedTravel=travel)
    (output/'player-measurements-v2.json').write_text(json.dumps(payload,indent=2)+'\n')
    font = ImageFont.load_default(size=13)
    groups = ('frame','header','display','timer','metadata','sliders','transport','glyphs')
    for group in groups:
        canvas = im.crop((0,0,998,457)).resize((1497,686))
        draw = ImageDraw.Draw(canvas)
        for r in records:
            if r['group'] == group:
                x,y,w,h = r['sourceRect']
                draw.rectangle((x*1.5,y*1.5,(x+w)*1.5-1,(y+h)*1.5-1),outline='#FF59E7',width=2)
                draw.text((x*1.5+2,y*1.5+2),str(r['id']),font=font,fill='black',stroke_width=2,stroke_fill='white')
        canvas.save(output/f'player-{group}-annotated.png')
    im.crop((10,7,990,454)).save(output/'player-source.png')
    scan = im.crop((70,170,155,263)).resize((510,558))
    draw = ImageDraw.Draw(scan)
    for x in scans:
        draw.line(((int(x)-70)*6,210,(int(x)-70)*6,540),fill='#FF59E7',width=1)
    scan.save(output/'player-spectrum-scan.png')
    material = Image.new('RGB',(1200,600),'#121923')
    draw = ImageDraw.Draw(material)
    for i,(name,box) in enumerate((
        ('Frame / well',(15,55,130,105)),
        ('Raised transport face',(128,337,228,427)),
        ('Steel thumb',(500,222,566,278)),
        ('Gold thumb',(444,284,554,332)),
    )):
        x,y=(i%2)*600,(i//2)*300
        draw.text((x+12,y+10),name,font=font,fill='white')
        crop=im.crop(box)
        crop.thumbnail((570,245))
        # Nearest-neighbor magnification makes the source edge layers explicit.
        factor=min(570/crop.width,245/crop.height)
        material.paste(crop.resize((int(crop.width*factor),int(crop.height*factor)),Image.Resampling.NEAREST),(x+12,y+36))
    material.save(output/'player-material-details.png')
    lines = ['# ReferenceMeasurementsV2 — Player','',
        'Generated by `scripts/measure_reference.py`. Source SHA-256: `'+payload['sha256']+'`.','',
        '**Scope:** Player only. Manually measured artwork bounds, ±2 source-pixel edge uncertainty (±1 pt); right/bottom exclusive. Glyph bounds are visible ink, not font layout cells. Hit areas are not visible in the PNG.','',
        '**Origins:** module `(10,7)` px; content `(10,64)` px. Player crop `980×447` px = `490×223.5` pt. Header convention `28.5` pt; the content-frame highlight begins at y=62, two pixels above that origin. Replaces the V1 inferred y=22 canvas top and 22 pt header.','',
        '## Measured rectangles','','| ID | Element | Source x,y,w,h (px) | Module x,y,w,h (pt) | Content x,y,w,h (pt) |','|---|---|---|---|---|']
    for r in records:
        lines.append(f"| {r['id']} | `{r['name']}` | {r['sourceRect']} | {r['moduleRect']} | {r['contentRect']} |")
    lines += ['','## Annotated checks','']
    for group in groups:
        lines += [f'### {group.title()}','',f'![{group} bounds](player-{group}-annotated.png)','']
    lines += ['## Material samples','','Patch medians are observations, not a uniform replacement palette. The reference has gradients, glow and multiple edge layers. Preserve these variations; coordinates allow verification.','','| Layer | Source patch | RGB | Hex |','|---|---|---|---|']
    for name,c in colors.items():
        lines.append(f"| {name} | {c['sourcePatch']} | {c['rgb']} | `{c['hex']}` |")
    lines += ['', '![Material edge details](player-material-details.png)', '',
        'The JSON `edgeProfiles` contains per-source-pixel RGB scans through frame, well, button and thumb edges. Each sample is 0.5 logical pt; preserve the sequence of highlight, face and shadow layers rather than replacing it with a one-line outline. The enlarged crops use nearest-neighbor scaling to expose source pixels.', '']
    lines += ['','## Spectrum scan','','```json',json.dumps(spectrum,indent=2),'```','',
        '![Spectrum scan](player-spectrum-scan.png)','',
        '## Non-observable properties and implementation constraints','',
        '- Thumb travel and invisible hit bounds cannot be measured from one pose. JSON records a derived inset-travel proposal separately. Validate it during control implementation; do not present it as extracted geometry.',
        '- Font point size, baseline metrics and hidden timer cell widths cannot be uniquely recovered from raster ink. Fit bundled fonts and stable digit cells to measured ink, then verify rendered overlays before freezing metrics. The visible `1` is narrow ink, not a narrower layout cell.',
        '- Keep centered Player branding; single-line track/metadata; distinct kbps, kHz, mono, stereo; EQ/PL and Shuffle optically aligned with indicators. The timer reads `01:51` and must retain its proportions for other values.',
        '- Header source order is left decoration, centered brand between paired lines, then minimize/collapse/close; behavior comes from the spec.','',
        '## V1 corrections','',
        '- Panel top is measured directly, not inferred by centering a total composition height.',
        '- Metadata includes channel labels separately from the two numeric wells.',
        '- The play triangle is outside the timer ink rectangle.',
        '- Volume/balance thumbs exceed the narrow track height. Position includes a recessed well and broad gold handle, not a four-point-high entire control.',
        '- Transport faces have individual widths; Shuffle is 84 pt wide rather than a uniform 44 pt.',
        '- Spectrum raw runs are retained without the unapproved 3 pt override.',
        '- EQ/Playlist V1 values remain unvalidated by this Player-only step.','']
    (output/'player-measurements-v2.md').write_text('\n'.join(lines))
    print(json.dumps(dict(output=str(output),rectangles=len(records),spectrum=spectrum),indent=2))


EQ_PANEL = (10, 466, 980, 451)
EQ_ORIGIN = (10, 523)  # Same 28.5 pt header convention as Player.
EQ_LANDMARK_TEXT = '''frame|panel|10,466,980,451
frame|content.frame|24,524,952,378
header|header|10,466,980,57
header|header.brand|361,483,91,32
header|header.title|497,487,156,24
header|header.leftRule|86,487,236,19
header|header.rightRule|689,487,131,19
header|header.collapseGlyph|895,486,21,21
header|header.closeGlyph|948,488,18,18
toprow|toggle.on|38,542,111,66
toprow|toggle.on.indicator|59,564,19,20
toprow|toggle.on.label|95,565,26,19
toprow|toggle.auto|161,542,141,66
toprow|toggle.auto.indicator|181,562,21,22
toprow|toggle.auto.label|221,565,56,20
toprow|presets|774,542,187,66
toprow|presets.label|801,565,97,19
toprow|presets.triangle|923,568,16,14
curve|curve.gridAndKnots|329,543,410,75
curve|curve.ink|329,564,408,26
sliders|preamp.slot|67,630,26,220
sliders|preamp.thumb|62,709,40,46
sliders|band60.slot|266,630,26,220
sliders|band60.thumb|260,700,40,48
sliders|band170.thumb|330,716,40,43
sliders|band310.thumb|397,725,40,44
sliders|band600.thumb|465,736,40,44
sliders|band1K.thumb|534,753,40,44
sliders|band3K.thumb|603,743,40,44
sliders|band6K.thumb|670,727,40,44
sliders|band12K.thumb|739,715,40,42
sliders|band14K.thumb|807,704,39,42
sliders|band16K.thumb|879,692,39,43
scale|tick.plus12.preamp|44,640,13,2
scale|tick.zero.preamp|44,736,13,2
scale|tick.minus12.preamp|44,837,13,3
scale|db.plus12|134,632,67,19
scale|db.zero|147,727,47,19
scale|db.minus12|135,823,73,19
labels|label.preamp|50,864,81,20
labels|label.60|267,864,24,20
labels|label.170|331,864,36,20
labels|label.310|397,864,38,20
labels|label.600|466,864,38,20
labels|label.1K|540,864,23,20
labels|label.3K|609,864,24,20
labels|label.6K|676,864,24,20
labels|label.12K|740,864,37,20
labels|label.14K|809,864,36,20
labels|label.16K|882,864,37,20'''


def generate_eq(path, output):
    """Equalizer landmarks: components detected by thresholded scans, then inspected on the annotations."""
    im = Image.open(path).convert('RGB')
    if im.size != (998,1576):
        raise ValueError('Remeasure landmarks for any other source dimensions.')
    output.mkdir(parents=True,exist_ok=True)
    records = []
    for i,line in enumerate(EQ_LANDMARK_TEXT.splitlines(),1):
        group,name,raw = line.split('|')
        rect = list(map(int,raw.split(',')))
        records.append(dict(id=i,name=name,sourceRect=rect,group=group,
            moduleRect=converted(rect,EQ_PANEL[:2]),contentRect=converted(rect,EQ_ORIGIN),
            method='thresholded component scan of visible ink/edges; inspect annotation',edgeUncertaintySourcePx=2))
    thumbs = [r for r in records if r['name'].endswith('.thumb')]
    zero_y, plus_y, minus_y = 107.875, 58.5, 157.25
    derived = {}
    for r in thumbs:
        cy = r['contentRect'][1] + r['contentRect'][3]/2
        derived[r['name'].split('.')[0]] = dict(thumbCenterY=cy, decibels=round((zero_y-cy)/((minus_y-plus_y)/24),2))
    payload = dict(version='ReferenceMeasurementsV2',scope='Equalizer',source='screenshots/AmpX.png',
        sha256=hashlib.sha256(path.read_bytes()).hexdigest(),panelSourceRect=list(EQ_PANEL),
        moduleOrigin=list(EQ_PANEL[:2]),contentOrigin=list(EQ_ORIGIN),headerHeightLogical=28.5,records=records,
        thumbTravel=dict(plus12CenterY=plus_y,minus12CenterY=minus_y,zeroCenterY=zero_y,
            method='±12 dB thumb centers at the measured +12/−12 tick rows; linear, centered on the slot'),
        derivedReferenceValues=derived)
    (output/'eq-measurements-v2.json').write_text(json.dumps(payload,indent=2)+'\n')
    font = ImageFont.load_default(size=13)
    groups = ('frame','header','toprow','curve','sliders','scale','labels')
    x,y,w,h = EQ_PANEL
    for group in groups:
        canvas = im.crop((0,y-4,998,y+h+4)).resize((1497,int((h+8)*1.5)))
        draw = ImageDraw.Draw(canvas)
        for r in records:
            if r['group'] == group:
                rx,ry,rw,rh = r['sourceRect']
                ry -= y-4
                draw.rectangle((rx*1.5,ry*1.5,(rx+rw)*1.5-1,(ry+rh)*1.5-1),outline='#FF59E7',width=2)
                draw.text((rx*1.5+2,ry*1.5+2),str(r['id']),font=font,fill='black',stroke_width=2,stroke_fill='white')
        canvas.save(output/f'eq-{group}-annotated.png')
    lines = ['# ReferenceMeasurementsV2 — Equalizer','',
        'Generated by `scripts/measure_reference.py --module eq`. Source SHA-256: `'+payload['sha256']+'`.','',
        '**Origins:** module `(10,466)` px; content `(10,523)` px (shared 28.5 pt header). Panel `980×451` px = `490×225.5` pt; gap to Player 12 px = 6 pt.','',
        '| ID | Element | Source x,y,w,h (px) | Module x,y,w,h (pt) | Content x,y,w,h (pt) |','|---|---|---|---|---|']
    for r in records:
        lines.append(f"| {r['id']} | `{r['name']}` | {r['sourceRect']} | {r['moduleRect']} | {r['contentRect']} |")
    lines += ['','## Annotated checks','']
    for group in groups:
        lines += [f'### {group.title()}','',f'![{group} bounds](eq-{group}-annotated.png)','']
    lines += ['## Derived reference values','',
        'Thumb travel: +12 dB center at content y 58.5 and −12 dB at 157.25 (measured tick rows); 0 dB at the midpoint 107.875. Values below are display-only fixture values derived from thumb centers.','',
        '| Slider | Thumb center y (pt) | dB |','|---|---|---|']
    for k,v in derived.items():
        lines.append(f"| {k} | {v['thumbCenterY']} | {v['decibels']} |")
    lines += ['','## Observations and non-observable properties','',
        '- No curve well: the response curve is drawn on the panel over thin vertical grid lines (content y 10–47) with gold knot dots. Knots: edges at x 161/362 and bands from 181 to 346.5 (18.39 pt pitch). A 13th grid line at x 196 does not correspond to a knot.',
        '- The drawn curve is not consistent with the thumb values (e.g. 60 Hz thumb +1.5 dB while its knot rises ~4 pt). Rendering derives the curve from values; shape differences are expected.',
        '- Track color varies by band value (green below 0 dB, yellow near 0, amber/orange above) with a vertical tint, but not as a single consistent function.',
        '- Band thumb centers are unevenly spaced (67–72 px); measured per-band centers are used. The 0 dB tick rows near some thumbs are displaced in the reference.',
        '- Header elements sit 0.5–1.5 pt lower than the Player header (rules +1, frame top +1.5); the shared header geometry is retained.',
        '- Reference EQ header shows three buttons; the spec defines two (collapse, close) for non-Player modules.','']
    (output/'eq-measurements-v2.md').write_text('\n'.join(lines))
    print(json.dumps(dict(output=str(output),rectangles=len(records),derived=derived),indent=2))


PL_PANEL = (10, 930, 980, 610)
PL_ORIGIN = (10, 987)
# Reference stack from Player top to Playlist bottom. The reference EQ→Playlist gap is 13 px (6.5 pt);
# the 6 pt layout gap makes a 1532 px composition, so the comparison crop ends one pixel early.
STACK_PANEL = (10, 7, 980, 1532)
PL_LANDMARK_TEXT = '''frame|panel|10,930,980,610
frame|content.frame|24,986,952,541
header|header.brand|380,946,86,32
header|header.title|499,951,126,20
header|header.leftRule|86,949,257,19
header|header.rightRule|657,949,163,19
header|header.collapseGlyph|895,949,20,17
header|header.closeGlyph|949,951,17,18
rows|rows.well|36,1004,890,400
rows|rows.interior|40,1007,881,393
rows|row1.number|64,1024,24,21
rows|row1.title|117,1023,421,28
rows|row1.duration|832,1025,61,21
rows|row4.selection|41,1138,879,40
rows|row4.number|63,1147,25,22
rows|row4.title|118,1147,259,22
rows|row4.duration|832,1148,62,21
rows|row7.number|65,1272,23,22
rows|row7.title|118,1271,345,23
rows|row7.duration|832,1272,62,22
scrollbar|scrollbar.outer|932,1004,31,390
scrollbar|scrollbar.up|932,1004,31,37
scrollbar|scrollbar.up.glyph|939,1013,17,19
scrollbar|scrollbar.thumb|935,1042,26,66
scrollbar|scrollbar.down|932,1352,31,42
scrollbar|scrollbar.down.glyph|939,1364,17,19
footer|footer.add|35,1420,86,88
footer|footer.rem|126,1420,88,88
footer|footer.sel|219,1420,88,88
footer|footer.misc|312,1420,91,88
footer|footer.add.label|58,1453,39,19
footer|footer.rem.label|149,1453,39,19
footer|footer.sel.label|241,1453,40,19
footer|footer.misc.label|330,1453,53,19
footer|footer.counter.well|419,1417,410,41
footer|footer.counter.text|548,1426,131,23
footer|footer.previous|419,1462,53,53
footer|footer.play|479,1462,53,53
footer|footer.pause|539,1462,52,53
footer|footer.stop|598,1462,53,53
footer|footer.next|658,1462,54,53
footer|footer.previous.glyph|436,1477,19,23
footer|footer.play.glyph|498,1477,17,24
footer|footer.pause.glyph|557,1477,16,23
footer|footer.stop.glyph|615,1478,18,21
footer|footer.next.glyph|676,1477,19,23
footer|footer.remaining.well|729,1471,100,40
footer|footer.remaining.text|742,1481,77,19
footer|footer.listOpts|848,1417,116,97
footer|footer.listOpts.line1|880,1439,51,19
footer|footer.listOpts.line2|879,1472,52,19'''


def generate_playlist(path, output):
    """Playlist landmarks from thresholded component and edge scans, inspected on the annotations."""
    im = Image.open(path).convert('RGB')
    if im.size != (998,1576):
        raise ValueError('Remeasure landmarks for any other source dimensions.')
    output.mkdir(parents=True,exist_ok=True)
    records = []
    for i,line in enumerate(PL_LANDMARK_TEXT.splitlines(),1):
        group,name,raw = line.split('|')
        rect = list(map(int,raw.split(',')))
        records.append(dict(id=i,name=name,sourceRect=rect,group=group,
            moduleRect=converted(rect,PL_PANEL[:2]),contentRect=converted(rect,PL_ORIGIN),
            method='thresholded component/edge scan of visible ink and faces; inspect annotation',edgeUncertaintySourcePx=2))
    by_name = {r['name']:r for r in records}
    tops = [by_name[f'row{n}.number']['sourceRect'][1] for n in (1,4,7)]
    pitch = (tops[2]-tops[0])/6/SCALE
    payload = dict(version='ReferenceMeasurementsV2',scope='Playlist',source='screenshots/AmpX.png',
        sha256=hashlib.sha256(path.read_bytes()).hexdigest(),panelSourceRect=list(PL_PANEL),
        moduleOrigin=list(PL_PANEL[:2]),contentOrigin=list(PL_ORIGIN),headerHeightLogical=28.5,records=records,
        rowPitchLogical=round(pitch,2),specRowHeight=22,specDurationColumnWidth=42)
    (output/'playlist-measurements-v2.json').write_text(json.dumps(payload,indent=2)+'\n')
    font = ImageFont.load_default(size=13)
    groups = ('frame','header','rows','scrollbar','footer')
    x,y,w,h = PL_PANEL
    for group in groups:
        canvas = im.crop((0,y-4,998,y+h+4)).resize((1497,int((h+8)*1.5)))
        draw = ImageDraw.Draw(canvas)
        for r in records:
            if r['group'] == group:
                rx,ry,rw,rh = r['sourceRect']
                ry -= y-4
                draw.rectangle((rx*1.5,ry*1.5,(rx+rw)*1.5-1,(ry+rh)*1.5-1),outline='#FF59E7',width=2)
                draw.text((rx*1.5+2,ry*1.5+2),str(r['id']),font=font,fill='black',stroke_width=2,stroke_fill='white')
        canvas.save(output/f'playlist-{group}-annotated.png')
    lines = ['# ReferenceMeasurementsV2 — Playlist','',
        'Generated by `scripts/measure_reference.py --module playlist`. Source SHA-256: `'+payload['sha256']+'`.','',
        '**Origins:** module `(10,930)` px; content `(10,987)` px (shared 28.5 pt header). Panel `980×610` px = `490×305` pt. The gap above is 13 px (6.5 pt) against the 6 pt layout gap.','',
        '| ID | Element | Source x,y,w,h (px) | Module x,y,w,h (pt) | Content x,y,w,h (pt) |','|---|---|---|---|---|']
    for r in records:
        lines.append(f"| {r['id']} | `{r['name']}` | {r['sourceRect']} | {r['moduleRect']} | {r['contentRect']} |")
    lines += ['','## Annotated checks','']
    for group in groups:
        lines += [f'### {group.title()}','',f'![{group} bounds](playlist-{group}-annotated.png)','']
    lines += ['## Observations and conflicts','',
        f'- **Row pitch conflict:** rows 1→7 advance {pitch:.2f} pt per row; the spec binds 22 pt rows. The spec value is kept pending a user decision. The 20 pt selection band sits in that pitch.',
        '- Row numbers form a separate column (ink x 27 pt); titles start at 53.5 pt; durations are right-aligned to 442 pt inside a 42 pt column.',
        '- Rows well interior is 196 pt tall (content y 10–206); footer faces start 9 pt below the well. Measured non-row chrome is 80.5 pt (V1: 103 pt).',
        '- The scrollbar thumb is a fixed 33 pt gold tab at the top of its slot although seven rows fit the viewport, so a proportional thumb would fill the slot.',
        '- The reference Playlist header shows three buttons; the spec defines two for non-Player modules.','']
    (output/'playlist-measurements-v2.md').write_text('\n'.join(lines))
    print(json.dumps(dict(output=str(output),rectangles=len(records),rowPitch=pitch),indent=2))


def compare(path, result_path, output, name='player', panel=PANEL):
    """Export reference crop, result, side-by-side and 50% overlay at identical panel bounds."""
    im = Image.open(path).convert('RGB')
    x,y,w,h = panel
    reference = im.crop((x,y,x+w,y+h))
    result = Image.open(result_path).convert('RGB')
    if result.size != reference.size:
        raise ValueError(f'Result {result.size} must match reference panel {reference.size}; never stretch captures.')
    output.mkdir(parents=True,exist_ok=True)
    reference.save(output/f'{name}-reference.png')
    result.save(output/f'{name}-result.png')
    side = Image.new('RGB',(w,h*2+8),'#FF59E7')
    side.paste(reference,(0,0))
    side.paste(result,(0,h+8))
    side.save(output/f'{name}-side-by-side.png')
    Image.blend(reference,result,0.5).save(output/f'{name}-overlay-50.png')
    print(json.dumps(dict(output=str(output),size=[w,h]),indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    parser.add_argument('--output',type=Path,default=Path('../docs/superpowers/plans/reference-crops/v2'))
    parser.add_argument('--compare',type=Path,help='2x module capture to compare against the reference panel')
    parser.add_argument('--module',choices=('player','eq','playlist','stack'),default='player')
    args = parser.parse_args()
    panel = dict(player=PANEL,eq=EQ_PANEL,playlist=PL_PANEL,stack=STACK_PANEL)[args.module]
    if args.compare:
        output = args.output if args.output != Path('../docs/superpowers/plans/reference-crops/v2') \
            else Path('../docs/superpowers/plans/correction-shots')
        compare(args.source,args.compare,output,name=args.module,panel=panel)
    elif args.module == 'eq':
        generate_eq(args.source,args.output)
    elif args.module == 'playlist':
        generate_playlist(args.source,args.output)
    elif args.module == 'stack':
        raise SystemExit('--module stack is only valid with --compare')
    else:
        generate(args.source,args.output)


if __name__ == '__main__':
    main()
