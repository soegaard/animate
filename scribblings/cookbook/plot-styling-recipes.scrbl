#lang scribble/manual
@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     animate
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental)
          "../../version.rkt")


@title[#:tag "cookbook-plot-styling-recipes"]{Combining Plot Areas and Observations}

Layer a filled function area, its graph, and observation markers in one plot.

API reference: @secref["point-markers-scatter-areas"], @secref["visuals"].

@; recipe-redistribution begin: marker-recipe


The following example places a filled function area behind its graph and adds
ordered observations as diamond markers:

@racketblock[
(define area
  (function-area coordinate-axes
                 function
                 #:id 'area
                 #:interpolation 'smooth))

(define graph
  (function-graph coordinate-axes
                  function
                  #:id 'graph
                  #:interpolation 'smooth))

(define observations
  (scatter-plot coordinate-axes
                (list (vec2 -2 1)
                      (vec2 0 0)
                      (vec2 2 1))
                #:id 'observations
                #:shape 'diamond))
]

Render the canonical marker-and-area example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/markers-scatter-areas.rkt \
  frames/markers-scatter-areas \
  markers-scatter-areas.mp4

open markers-scatter-areas.mp4
}



@; recipe-redistribution end: marker-recipe
