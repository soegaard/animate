# Geometry example audit — v0.8.1

## Result and scope

This is an audit of the user's native review files, followed by changes to the
actual construction/library/layout source. It is not only a list of proposed
improvements. The complete replacement `geometry/` folder contains the fixes,
updated reference manual, review metadata, and regression checks.

The largest confirmed problems were **incorrect helper names in narration**,
**a cropped primary circle**, **inconsistent arc notation for equal α angles**,
**missing geometric evidence at some conclusions**, and **too many operations
inside single application steps**. Several looked like individual example
problems but originated in shared helper or annotation code.

Input: `geometry-review-upload-20260912-022955.zip`, generated with geometry
v0.8.0. The input contains **17 examples in both light and dark themes: 34 bundles,
564 review rows, 1,692 step PNGs, and 110 contact sheets**. Every contact-sheet
page in both themes was visually inspected. Selected ambiguous details were
also inspected at full image resolution. This is not a claim that every PNG was
opened separately at full resolution, or that three stills prove the whole
continuous animation is correct.

**Validation boundary:** the corrected source passes the actual headless tests
listed below. The available runtime cannot run the complete native Animate / Pict /
Draw / font stack. Consequently the supplied images are before-fix evidence;
there are no claimed after-fix native renders. A small number of conservative
transient label/curve warnings are intentionally reported for the next render.

## Shared corrections

### 1. Narration and labels use the same object identities

The old helper implementation hygienically renamed the geometry but left its
literal narration unchanged. In the SAS review, for example, the local source
angle's “through A” instruction actually referred to the caller's B. Perpendicular
helpers could create another A while the caller already displayed a different A.

Helpers now use structured captions such as:

```racket
(step (caption "Join " A " to " B ".")
  [base (segment A B)])
```

The compiler resolves those references after nested helper substitution, using
the same `label-text` as the diagram. Primed target vertices stay primed in the
caption. Distinct active private helper objects get deterministic subscripts
when necessary. Aliases/projections proven to refer to a public object reuse its
name. No numerical point merging and no global string replacement is performed.
Ordinary string captions remain exactly what the author wrote.

### 2. The angle-copy procedure shows what it asks the viewer to copy

A full-source-side compass opening often made the new circle intersection D
coincide with the source endpoint C, or made X coincide with a previously copied
endpoint. The new helper chooses an interior point U, preferably about a third
of the way along the first source segment. It obtains D on the other arm and
**draws the chord UD** before asking the viewer to transfer that chord.

The transferable-compass model and the copied angle are unchanged. Known angle
copying is used collapsed in the hexagon, where source and target share the
center and expanded reuse introduced coincident intermediate objects. Expanded
copying remains available and is demonstrated in the standalone, SAS, chain,
and gallery contexts where appropriate.

### 3. Angle notation and label position reflect the angle

The final copy-angle review showed one arc for one α and two for the other.
Single-angle indicators now start with one arc without reserving an independent
equality pattern. Equality groups still use distinct patterns when needed.
Equivalent angles are recognized from their vertex and positive ray directions,
not the arbitrary distances to the endpoint-defining points.

Automatic angle-label candidates are on the interior bisector at several radial
distances, instead of a generic eight-direction search that could put α outside
its angular sector. Explicit label hints remain available. This changes only
annotation placement, not the mathematical angle.

### 4. Primary-circle framing is explicit, helper-circle cropping stays allowed

```racket
(layout (fit-circle k))
```

This new opt-in includes the full extent of the named circle in the fixed view.
The tangent and circumcircle examples use it; the hexagon also fits its main
circle. It does not force every large auxiliary circle onto the screen.
Radius-only helper circles no longer add their synthetic eastward reveal-origin
point to the camera fit.

Captions use one consistent relative size (`0.025 × world-width`) rather than a
world-size cap that made the text small in wide views. Relevant examples get
additional padding; the distance-unit segments are moved away from the caption
band without changing their lengths.

### 5. The completed diagram gets priority without moving labels during playback

Final retained curves have more weight in label placement than transient helper
curves. The labels still keep one fixed position throughout their lifetime.
Overlaps with points/labels, the viewport, and caption area remain major costs.
This is a finite candidate heuristic, not a guarantee that every temporary
crossing can be avoided.

### 6. Repeated applications are broken into reviewable steps

Each additional unit/parallel, altitude foot, or repeated copied vertex receives
its own short mathematical instruction where the old source packed several into
one step. Final conclusions pause for 1.5 seconds. The default reading delay
remains one second. Known sub-constructions may be collapsed instead of being
retaught where their expansion obscured the purpose of the application.

## Findings for every example

Step numbers in this table refer to the **uploaded v0.8.0 review**. The new
examples have revised numbers/times. Every row was checked in both themes; the
shared failures and fixes are the same unless noted otherwise.

| Example | Before-fix evidence | Finding | Implemented correction |
|---|---|---|---|
| `equilateral-triangle` | Steps 7 | Matching side ticks and final result were readable. Preserve the accepted construction rather than redesign it. | Added light-touch label preferences and a longer final hold. Shared caption sizing applies. Circle reveal, colors, and marker dimensions are unchanged. |
| `perpendicular-bisector` | Steps 3–9 | The expanded helper drew its own base on top of the caller’s AB; private crossing labels could crowd construction arcs. | The helper now hides its private base at the conclusion, leaving the caller’s segment. Caption names follow helper substitution. The half-length ticks and right-angle size are unchanged; two transient circle-label risks remain for native review. |
| `perpendicular-through-point` | Steps 5–7 | No new mathematical error in the reviewed final diagram. Labels C/D pass near the joining line during the last construction actions. | Preserved the accepted construction and reveal behavior; added a longer final hold. The conservative C/D-versus-line warnings remain documented rather than being claimed eliminated. |
| `square-on-segment` | Steps 2–10 and final | Expanded perpendicular construction reused caller point names A/B for different local points; the line supporting its instructions was not always shown. | Helper captions and labels now agree and distinct local points use subscripts. The supporting line is shown. Corner label preferences keep the completed square legible, and the final result rests longer. |
| `circumcenter` | Steps 2–11 | Fully expanded bisector auxiliaries forced a wide static view, leaving the finished triangle/circle too small; caption scaling compounded the problem. | Use already-known bisector constructions collapsed, fit the full circumcircle, increase padding, add outward label preferences, and maintain a consistent relative caption size. The actual circumcenter/circle assertions remain. |
| `incircle` | Steps 13–22 | The conclusion compared three perpendicular distances while the feet/radius/right-angle evidence was incomplete and crowded into one step. | Each remaining foot and perpendicular radius now gets its own step. All three feet, equal radii, and right-angle markers are visible in the conclusion. Unneeded full angle-bisector rays are removed earlier. |
| `triangle-midline` | Steps 2–15 | Nested midpoint construction repeated an initial join; helper captions/labels needed hygienic naming. The conclusion could state the two halves more precisely. | Removed the redundant outer join in the midpoint helper, resolved nested names, added outward label preferences, and explicitly described M/N as dividing their respective sides into equal halves. Midline parallel/equal-half checks are retained. |
| `reflect-point` | Steps 2–15 | Expanding the dropped perpendicular already displayed the reflected point as an auxiliary Q, then the next helper constructed another Q at the same location. | Use the perpendicular foot as a known collapsed construction; expand the distance copy to teach the reflection without revealing the answer twice. Place H above-left and keep the final equal-length/right-angle evidence. |
| `copy-triangle-sas` | Steps 3–16 | The source-angle caption “through A” referred to a helper-local point that was the caller’s B. Primed target names were lost, copied AB vanished between stages, and full-side opening crowded source/target points. | Structured captions resolve A′/B′/C′ and source names correctly. The copied A′B′ segment is kept immediately after its construction. An interior compass opening and an explicitly drawn source chord replace the congested full-side opening. |
| `divide-segment-five` | Steps 2–11 | Many copied units and parallels were introduced in compound steps, so three review samples missed much of the reasoning. The initial unit was not clearly identified. | Name the source unit u, move it above AB away from the caption band, and separate each copied unit and each parallel/intersection into steps. Use P/X subscripts, show equal auxiliary intervals, and check all four parallels. Keep final five equal parts clear. |
| `tangent-at-point` | Steps 1–11 | The main circle was visibly cropped, even though the lesson is about that circle; the perpendicular helper’s supporting line was not clearly supplied. | Opt into full-circle fitting with padding, show the supporting radius line during the expanded construction, and retain the accepted right-angle size. No requirement is imposed that the auxiliary construction circles fit completely. |
| `orthocenter` | Steps 2–11 | The final altitude statement lacked the three explicit feet/right-angle markers; full infinite altitude lines made the final picture busier than needed. | Construct the feet in separate steps, label them T₁/T₂/T₃, show all three altitude segments and right-angle markers, and hide the unnecessary full lines at the conclusion. All three perpendicularities and concurrency remain checked. |
| `regular-hexagon` | Steps 3–16 | The caption claimed a 60° angle before its triangle was fully drawn; expanding angle copy at the same center generated coincident local points; the final side/radius comparison lacked a retained radius. | Draw OB and AB before the 60° statement. Reuse angle copying collapsed in this application, separate successive vertices into steps, fit the full primary circle, and retain OA in the seven-member equal-length marker (six sides plus radius). |
| `equilateral-triangle-chain` | Steps 1–19 | The seed and later repeated constructions were too compressed. Old seed circles and reused helper names obscured the copying steps. | Separate the seed construction and repetitions, remove seed circles before copying, use helper-safe names/chords, prefer clear endpoint labels, and retain equality evidence with a final hold. |
| `parallel-at-distance` | Steps 1–15 | The opening caption asked to choose A although it was already given; the unit was unnamed and the final picture did not explicitly show both right-angle connections. | Say “At A”, name the given distance d, move its displayed segment above the caption band, add both right-angle squares and equal-length evidence for AP/d, and give the whole arrangement more padding. |
| `copy-angle` | Steps 3–12 | The source and target α angles had different arc counts. Automatic α placement could leave the angle’s sector; the source chord was invoked but not drawn, with crowded local points. | Use one-arc indicators consistently; recognize equivalent angles by their rays rather than endpoint distances. Constrain automatic angle-label positions to their sectors. Draw the chord with an interior compass opening and resolve helper names in captions. |
| `gallery` | Steps 1–5, 11–16, 39–62 | Primitive plates accumulated old geometry and lacked some defining-point labels; the promised one/two/three equal-angle classes were not all demonstrated; earlier bisector arcs interfered with the later copied angle. | Clear primitive plates, show defining points, enlarge the first circle, add three simultaneous angle-equality classes, keep the helper demonstration’s base, and remove the previous angle bisector/arcs before copying. Existing effects and accepted dimensions remain. |


## What is intentionally preserved

The right-angle square retains its accepted size. Equal-length and midpoint
ticks retain the earlier 20% reduction. Light/dark palette choices, one-second
default reading delay, the basic object-specific reveal semantics, and public
signatures of all eight standard helpers are unchanged. Captions describe
mathematical actions; they do not announce emphasis/deemphasis operations.

The 10-process video renderer, global frame naming, review all/single-example
selection, ZIP layout, and three-sample ordinary rows and five-sample compass rows are preserved.
The examples' authored steps, endings, and chosen representative layouts change
where listed above. No outer Animate repository file is replaced.

## Validation performed

| Actual command | Result |
|---|---|
| `racket geometry/run-tests.rkt --audit` | **49 groups, 3,053 checks passed** |
| `racket geometry/run-tests.rkt --library` | **68 groups, 2,484 checks passed** |
| `racket geometry/run-tests.rkt --review` | **60 groups, 215,848 checks passed** |

Runtime: **Racket CS 9.3.0.8**. The library's independent geometric oracles and
transformed-input tests are retained. The new tests target the observed naming,
marker, framing, chord, foot-marker and final-state errors, and exercise all
17 examples in both themes. The review tests validate the new step structure,
exact before/during/after states, and bundle safety. Recorded logs are included.

Reader, local-dependency and archive checks are in `static-audit.json`.
`example-audit.json` provides a machine-readable per-example record, including old
and new row counts. `estimated-layout-audit.json` contains the pure annotation
results with conservative caption reservation.

**Not run here:** the complete RackUnit suite, post-fix native text measurement,
bitmap/PNG/contact-sheet rendering, and macOS movies. The new
`tests/audit-render-test.rkt` is registered with the full local test runner and
checks native α positioning and representative rendered endings. Successful
headless tests do not replace that native check.

## Remaining risks to inspect after rendering

The conservative estimated pass has no `outside-safe-area` or
`annotation-overlap` warnings for these revised views. It still reports
`label-geometry-overlap` around some intermediate helper circles and supporting
lines. These are not suppressed: they remain in `--describe` and in the included
JSON. They are generally transient, but actual font metrics may expose further
collisions, and dense expanded-helper frames still deserve close attention.

Examples with no warnings in that estimated pass are equilateral-triangle,
square-on-segment, reflect-point, and orthocenter. Remaining warnings affect
intermediate labels in the other examples, including the bisector intersections,
the angle-copy compass points, and the repeated parallels. Do not interpret
“mathematical tests passed” as “all intermediate pictures are pixel-perfect”.

The highest-value native follow-up images are the final **copy-angle** frame
(matching α arcs and labels inside the sectors), the initial/final **tangent**
frames (whole main circle), the **SAS angle-copy** steps (correct source/primed
names and a visible chord), and the **incircle/orthocenter** endings (three feet
and right-angle markers). The gallery should show clean primitive plates and
three distinct equal-angle classes.

## Run the corrected review workflow

Replace `geometry/`, then run from the Animate repository root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" geometry/run-tests.rkt &&
"$RACKET" geometry/review-examples.rkt \
  --example copy-angle --dark \
  --output geometry-review-v081
```

After the native tests pass, rebuild all examples in both themes:

```sh
"$RACKET" geometry/review-examples.rkt \
  --all --both \
  --output geometry-review-v081
```

This retains the previous review directory for comparison. Each new manifest
records geometry v0.8.1. Use the narration and source paths when comparing old
and new results; `step-012` need not refer to the same action after the pacing
corrections. One ZIP per example/theme is still created.
