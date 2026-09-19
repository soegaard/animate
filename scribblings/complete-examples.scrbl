#lang scribble/manual

@title[#:tag "part-complete-examples" #:style '(toc grouper)]{Complete Example Programs}

Start with a result you would like to make. Each chapter shows selected frames,
the complete source files, a short explanation of their structure, and a command
that renders the example. The programs are read from the repository, not copied
into the manual.

The @secref["part-guide"] teaches each idea in order. The
@secref["part-cookbook"] answers short questions. This part shows how those ideas
fit together in a whole program.

@bold{Choose a program}

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Example} @bold{Study it for})
  (list @secref["complete-moving-circle"] "The smallest complete Scene and a final hold.")
  (list @secref["complete-function-graph"] "A sampled curve, a reveal, and a shared group.")
  (list @secref["complete-slide-lesson"] "Three slides, named beats, and a render project.")
  (list @secref["complete-algebra-checkpoints"] "One derivation carried across two layouts.")
  (list @secref["complete-geometry-construction"] "A construction, narration timing, and playback.")
  (list @secref["complete-semantic-parts"] "Named children that rearrange across a transition.")
  (list @secref["complete-spatial-lesson"] "A 3D lesson split into three related files.")
  (list @secref["complete-source-blocks"] "A longer Scene divided into editable blocks."))]

@bold{Running the examples}

Run the shell commands from the Animate checkout root, with Animate installed in
the Racket installation you use. The commands use @exec{racket} and @exec{raco}
from your PATH; a full path to either executable works too. MP4 commands need
FFmpeg. Each chapter names any additional requirements.

Most source files only export a description. Running such a file by itself does
not show a window or write a movie. Use the command printed in its chapter.
Choose a fresh output location rather than mixing a new render with old files.

The illustrations are stored samples of Scenes and storyboards. Captions retain
their original times. Gallery-supplied captures are identified as such; they
illustrate the same example without claiming to be newly encoded MP4 frames.
Changing a source file does not automatically regenerate its stored pictures.

@local-table-of-contents[]
@include-section["complete-examples/moving-circle.scrbl"]
@include-section["complete-examples/function-graph.scrbl"]
@include-section["complete-examples/slide-lesson.scrbl"]
@include-section["complete-examples/algebra-checkpoints.scrbl"]
@include-section["complete-examples/geometry-construction.scrbl"]
@include-section["complete-examples/semantic-parts.scrbl"]
@include-section["complete-examples/spatial-lesson.scrbl"]
@include-section["complete-examples/source-blocks.scrbl"]
@include-section["complete-examples/catalog.scrbl"]
