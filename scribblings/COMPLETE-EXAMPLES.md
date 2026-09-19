# Maintaining Complete Example Programs

The fifth manual part is `scribblings/complete-examples.scrbl`. It sits between
Guide and Reference. Its eight chapters show complete source programs, selected
frames, run commands, and a short explanation of how each program fits together.
The Cookbook remains a collection of short tasks.

## One source of truth

The `.rkt` programs stay in `scribblings/examples/`. A chapter uses
`@complete-source["scribblings/examples/name.rkt"]` to read the complete real file.
This includes `#lang`, imports, exports, comments, and every definition. The helper
uses Scribble's `codeblock0` for syntax coloring without expanding or running the
program. It supplies the chapter's label context, so names with available manual
targets can link to their definitions. Do not paste a second copy of the program
into a chapter.

Keep unrelated contracts out of these chapters. Link to Guide for teaching and
Reference for exact API details. A multi-file example should list all of its
example-level files and explain their relative imports; it need not reproduce
library implementation modules.

`complete-examples/entries.json` declares the chapter order, source files,
exported-value checks, selected capture strips, requirements, and run commands.
The chapter uses `complete-command` and `complete-requirements` to display that
same metadata. New entries must have matching chapter, source, frame, and command
references. Do not change the library's runtime example catalog just to add a
manual case study.

## Frames

The new part reads the existing main, learning-r4, and 3d-r3 manifests. It does
not regenerate images or encode movies during a Scribble build.

Use `@complete-frames["entry-id" "strip-id"]` to display the registered selection.
Selections contain one still or three or five increasing, distinct frame indices.
The helper preserves the original frame captions and sample times. It delegates
the presentation to `manual-frame-strip`, so each frame keeps the shared one-pixel
border and the preferred single-row layout. Narrow pages may wrap the row. Use an
explicit `#:columns` override only for readability.

Choose samples that explain the change. An interior sample matters for movement
and transitions. A final endpoint sample is a valid illustration even when an
encoded video's half-open frame grid does not include that exact time. Do not
call stored samples frames extracted from an MP4 unless they really were.

A few existing slide strips were captured through equivalent gallery entries.
Their notes identify that origin. Keep those notes; do not imply that a screenshot
is a fresh render of a newly edited source. Native manifests with source stamps
are checked for staleness. Library, renderer, or font changes can also affect the
result without changing those source stamps, so visual review remains necessary.

## Run commands

Commands assume the checkout root is the working directory and `racket`/`raco`
select the intended installation. Use an explicit executable path locally when
several Racket versions are installed. The native examples use the existing
`render-frames!` and `encode-mp4!` operations. Slide examples use the existing
`slides/render-example.rkt` runner and request ten workers. The two forms are
intentional; no separate example rendering engine is introduced.

A module that only exports `film` or `animation` does not create a movie merely
because it is run. Show the renderer command and its expected output. Formula
rendering needs the formula toolchain; MP4 encoding needs FFmpeg; the explicit
preview command needs a graphical session. Do not run these commands while
building the documentation.

## Checks

From the repository root:

```sh
python3 scribblings/check-structure.py .
python3 scribblings/tests/test-complete-examples.py
raco test scribblings/tests/complete-examples-test.rkt
racket scribblings/check-complete-examples.rkt --math --geometry --3d
racket tools/check-documentation.rkt slides-output/manual-complete-examples
```

The structure checker includes `check-complete-examples.py`. It checks the fifth
part, page wiring, source and command input paths, selected images, and recorded
checksums. It does not expand Racket code or prove that a shell command renders
successfully. `--overlay` and `--sources-only` are explicitly partial checks.

The Racket checker loads the actual registered modules, checks exported types,
and checks known native Scene durations. `--math`, `--geometry`, and `--3d`
enable those families. By default it does not prepare storyboards or render
media. To exercise storyboard preparation and known storyboard durations too,
run this separately in a configured environment:

```sh
racket scribblings/check-complete-examples.rkt --math --geometry --3d --prepare
```

That optional command may require the mathematical typesetting tools. It still
does not encode MP4s. The complete Scribble build checks label resolution; a
browser review checks source readability, captions, frame size, and wrapping.
These checks have different jobs, and none should be described as replacing the
others.

## Catalog migration

`complete-examples/catalog.scrbl` generates More example programs from the
existing `private/example-catalog.rkt`. It groups every catalog entry once.
It retains the old `cookbook-canonical-examples` tag as an alias alongside
`complete-example-catalog`, so manual links using the old tag still resolve.
The old Cookbook catalog page is no longer included or maintained separately.
