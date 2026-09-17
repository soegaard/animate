#lang scribble/manual
@(require (for-label racket/base
                     (only-in animate
                              scene-duration scene->pict
                              make-scene make-camera scene-add scene-play
                              line circle vec2 move-to smooth)
                     (only-in animate/colors theme-muted theme-accent)
                     animate/slides
                     animate/slides/pict
                     animate/slides/scene
                     animate/slides/render
                     animate/slides/math
                     animate/slides/geometry)
          "../private/guide-examples.rkt"
          "../private/illustrations.rkt")
@(define embedded-eval (make-guide-eval))

@title[#:tag "guide-embedded-content"]{Put an animation inside a slide}
@; requires: scene coordinates slide slot slide-clip beat easing theme narration

A figure slot can hold a picture or an animation. The slide places the figure;
the figure still owns the motion inside it. Start with an ordinary moving Scene.

@section[#:tag "guide-native-viewport"]{Choose the figure's visible area}
@; introduces: camera viewport

A @bold{camera} chooses the visible world area and the pixel size. Here it shows
an eight-unit-wide world in an 800-by-450 image. This area becomes the figure's
@bold{viewport}: a stable window that the slide can place and resize.

The track is a line between two points. The disc moves along it. The color names
@racket[theme-muted] and @racket[theme-accent] adapt to the selected theme.
Native @racket[scene-play] takes a rate-function value, @racket[(smooth)],
whereas a slide transition takes the symbol @racket['smooth].

@examples[
 #:eval embedded-eval
 #:hidden
 (require animate
          animate/colors
          animate/slides
          animate/slides/pict
          animate/slides/scene
          animate/slides/render)
]

@examples[
 #:eval embedded-eval
 #:no-result
 (define inner
   (scene-play
    (scene-add
     (make-scene
      #:camera
      (make-camera #:width 800 #:height 450 #:world-width 8))
     (line (vec2 -3 0) (vec2 3 0) #:id 'track
           #:stroke theme-muted #:stroke-width 2)
     (circle #:id 'disc #:center (vec2 -2 0) #:radius 0.45
             #:fill theme-accent #:stroke-width 0))
    (move-to 'disc (vec2 2 0))
    #:duration 3
    #:easing (smooth)))
]

Before embedding it, inspect the native Scene itself halfway through its motion:

@examples[
 #:eval embedded-eval
 #:label #f
 (eval:alts
  (scene->pict inner 3/2)
  (guide-pict (scene->pict inner 3/2)))
]

@section[#:tag "guide-embed-scene"]{Embed the Scene}

@racket[scene-content] wraps the Scene as slot content. No movie file is made.

@examples[
 #:eval embedded-eval
 #:no-result
 (define card
   (slide #:layout 'title+figure
     [title "A scene inside a slide"]
     [figure (scene-content inner)]
     [footer "The inner clock starts at play-content."]))
]

@section[#:tag "guide-content-clock"]{Start its own clock}
@; introduces: content-clock

The figure has a @bold{local clock}. Revealing a slot changes visibility; it
does not start that clock. @racket[play-content] advances it. Here the first beat
holds the disc at its starting position for one second; the next plays the
three-second movement.

@examples[
 #:eval embedded-eval
 #:no-result
 (define clip
   (build-slide card
     (beat 'introduce #:duration 1)
     (beat 'move #:duration 3
       (play-content 'figure))
     (beat 'hold #:duration 3/2)))
 (define film
   (storyboard #:id 'manual-native #:theme lecture-dark
     (storyboard-shot 'native-scene clip)))
]

The complete presentation lasts 5.5 seconds:

@examples[
 #:eval embedded-eval
 #:label #f
 (eval:check
  (scene-duration (storyboard->scene film))
  11/2)
 (eval:alts
  (storyboard->pict film #:at 5/2)
  (guide-pict (storyboard->pict film #:at 5/2)))
]

@frame-strip["native-viewport"]

The captions show whole-slide times. The middle image, at 2.5 seconds, is only
1.5 seconds into the figure's motion. An empty final beat holds the reached
state. A complete standalone version is
@filepath{scribblings/examples/native-viewport.rkt}.

@section[#:tag "guide-content-preparation"]{Prepare resource-dependent content}
@; introduces: preparation

Some figures need work before they can be sampled. @bold{Preparation} measures
text, typesets formulas, and fixes construction points and label positions.
Afterwards, frames use those prepared results instead of repeating the work.

The native Scene above needs no external tool, so it is a safe example on which
to execute the preparation step:

@examples[
 #:eval embedded-eval
 #:no-result
 (define prepared
   (prepare-storyboard! film))
]

@examples[
 #:eval embedded-eval
 #:label #f
 (eval:check
  (prepared-storyboard? prepared)
  #t)
]

Keep an explicit preparation call in a runner rather than at the top level of a
reusable lesson module. A later resource-dependent figure can then perform its
measurement or typesetting once before frames are sampled.

@section[#:tag "guide-math-content"]{A mathematical explanation has its own plan}
@; introduces: math-plan

The math subsystem starts with an expression, makes named derivation steps, and
turns those steps into a @bold{presentation plan}. @racket[math-content] wraps
that plan for a figure slot. The slide does not perform the algebra.

The semantic math plan itself is pure, so the Guide can execute it without
typesetting any formula:

@examples[
 #:eval embedded-eval
 #:hidden
 (require (only-in animate/math
                   math math-context derive
                   both-sides cancel-addends lhs
                   evaluate rhs present classroom)
          animate/slides/math)
 (define problem
   (math '(= (+ (* 3 x) 5) 17) #:id 'problem
         #:context (math-context #:real '(x))))
 (define working
   (derive problem
     [subtract-five (both-sides 'subtract 5)]
     [cancel-five (cancel-addends #:at (lhs))]
     [evaluate-rhs (evaluate #:at (rhs))]))
 (define plan
   (present working #:style classroom
            #:groups '((subtract-five cancel-five evaluate-rhs))))
 (define equation
   (math-content plan))
]

@racketblock[
(require animate/math animate/slides/math)

(define problem
  (math '(= (+ (* 3 x) 5) 17) #:id 'problem
        #:context (math-context #:real '(x))))

(define working
  (derive problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five (cancel-addends #:at (lhs))]
    [evaluate-rhs (evaluate #:at (rhs))]))

(define plan
  (present working #:style classroom
           #:groups '((subtract-five cancel-five evaluate-rhs))))

(define equation
  (math-content plan))
]

The displayed block is ordinary source code. The same definitions are evaluated
in a hidden documentation example immediately before it, so API drift still
fails the build even though the Math identifiers are not linked into the
separate Math manual from this Guide page.

@examples[
 #:eval embedded-eval
 #:label #f
 (eval:check
  (content? equation)
  #t)
]

Rendering or preparing a slide that contains @racket[equation] may invoke the
formula toolchain. This chapter deliberately stops at the semantic content value,
so building the manual does not make TeX a requirement.

For ordinary playback, put @racket[equation] in the figure slot and use
@racket[(play-content 'figure #:to '(cancel-five end))] in a beat. The next
chapter uses this same plan to move between two frozen checkpoints. The complete
multi-step program remains
@filepath{scribblings/examples/math-checkpoints.rkt}.

@section[#:tag "guide-geometry-content"]{Reuse a geometry construction}
@; introduces: construction

A @bold{construction program} describes named points, lines, circles, and the
steps used to reveal them. This example reuses the library's
equilateral-triangle program. Its points and labels stay under the geometry
subsystem's control.

Construct the slide description and timing, but leave construction preparation
to the reviewed frame-strip pipeline:

@examples[
 #:eval embedded-eval
 #:no-result
 (require animate/slides/geometry
          (only-in animate/geometry/examples/equilateral-triangle
                   equilateral-triangle))
 (define geometry-card
   (slide #:layout 'title+figure
     [title "Construct equal sides"]
     [figure (geometry-content equilateral-triangle)]))
 (define geometry-clip
   (build-slide geometry-card
     (beat 'construct
       #:narration
       (narration
        "Construct an equilateral triangle with two circles."
        #:draft-duration 4)
       (play-content 'figure))
     (beat 'hold #:duration 2)))
]

@examples[
 #:eval embedded-eval
 #:label #f
 (eval:check (slide-clip? geometry-clip) #t)
]

@frame-strip["geometry-play"]

The draft narration supplies four seconds of text and pacing, but
@racket[play-content] may need longer. Because the beat has no explicit
duration, preparation uses the longer interval. The last beat holds the finished
construction. The complete program is
@filepath{scribblings/examples/geometry-slide.rkt}.

Continue with @secref["guide-semantic-continuity"] to change a figure's layout
while its own animation advances. Worker rendering comes later in
@secref["guide-project-planning"]; it does not require a different construction.

@close-eval[embedded-eval]
