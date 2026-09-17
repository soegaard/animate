# Maintain the manual as a teaching tool

The manual has four parts with different jobs. Concepts explains ideas. Cookbook
solves individual tasks. Guide teaches a workflow in small steps. Reference owns
the API contracts. A topic may appear in more than one part, but do not copy a long
reference entry into the Guide.

## Add a lesson

Begin with a visible goal and name the preceding lesson the reader needs. Introduce
a concept immediately before the code that needs it. Use plain words, then give the
API name. Show a complete small example in stages, not a large finished program
followed by explanations of everything it already used.

State whether a snippet continues the preceding Scene or starts a separate
alternative. Define the Racket variables it needs, name its module imports, and
state whether loading the file opens anything or writes files. Say what the reader
should see. Include one small change the reader can try and its expected effect.

Use the real example files in `examples/`, shown through `example-part` or
`example-source`. Keep the snippet markers unique and paired. Do not maintain a
second copy of the code in the prose. Run its tests after editing it.

## Add an illustration

Use genuine frames from the example being taught. An animation normally needs
three or five frames, including an interior sample. Label actual sample times;
separately label alternatives or still pictures. Use the same camera and scale
through a motion comparison. Keep text large enough to read when the manual is
printed. An image strip is not a substitute for explaining what changes.

`render-learning-illustrations.rkt --install` generates the r4 figures. Its manifest
records the source, recipe, renderer-script hashes, platform, Racket version, times,
and PNG hashes. It samples each frame twice. These source stamps do not fingerprint
every Animate implementation module or installed font: review and regenerate the
figures after a relevant renderer/library change too. Move the old figure directory
to a backup first; the runner will not silently overwrite stale or edited files.

Commit reviewed PNGs and their manifest under `figures/learning-r4/`. Never commit
font binaries or machine-local caches. An ordinary Scribble build must read stored
assets, not run an animation renderer, TeX, or a video encoder.

## Keep the Reference navigable

Separate contracts by task, not by implementation history. Put common authoring
operations before extension protocols. Keep a predicate beside its constructor.
Use the 3D reference map for the r3 split; do not recreate the old giant chapter.
When a chapter becomes hard to navigate, first check whether it contains several
unrelated tasks. Do not split a contract or example in the middle merely to hit a
page quota. A source-line limit is an editorial signal, not a rendered page count.

Every new heading needs a short explicit tag. Retain published tags when moving
material. Never skip a heading level. Each Scribble part must have a single,
correct exporting declaration; `defmodule` also declares exporting unless marked
otherwise. Test the actual build, not just a regular-expression inventory.

## Check the whole chain

From the checkout root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python3 scribblings/build-manual.py --racket "$RACKET" --math --geometry \
  slides-output/manual-learning-r4
```

The driver saves stdout, stderr, and actual exit codes for every stage. Its JSON
report distinguishes tests not selected from stages that passed. It stops at the
first failure and keeps the failing log. `--skip-examples` is an explicit opt-out,
recorded in the report, not evidence that those examples passed.

The checks cover different things. Source checks check links and the declared
teaching order. RackUnit checks the programs. Image checks check stored assets.
The Scribble checker checks the assembled manual and its Animate-owned links.
Finally, open the HTML and review the typography and pictures. Do not claim a
verified PDF layout without building and inspecting that output separately.
