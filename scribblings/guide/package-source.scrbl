#lang scribble/manual

@title[#:tag "guide-package-source"]{Source Package Hygiene}

Animate is distributed as source. Create a clean archive from a checkout with
@tt{raco pkg create --source .}. The package configuration omits local
experiments, generated renders, compiled artifacts, and Finder metadata while
retaining the optional Rhombus examples as source. Normal compilation omits
those Rhombus examples because they require their own language tooling.

The package registers this manual in @filepath{info.rkt}; a normal installation
therefore builds and links the documentation. Run @tt{raco animate check-repo}
before a release to exercise metadata coherence, compilation, examples, this
manual, and a fresh source-package installation.
