#lang scribble/manual
@(require (for-label racket/base
                     (only-in racket/math pi)
                     animate animate/3d
                     animate/slides
                     animate/slides/pict
                     animate/slides/scene)
          "../private/guide-examples.rkt"
          "../private/three-d-illustrations.rkt")
@(define composition3d-eval (make-guide-eval))

@title[#:tag "guide-3d-composition"]{Combine 3D with text and slides}

@; requires: scene view3d spatial-path camera3d-motion
The previous chapter produced a Scene named @racket[lesson]. A 3D view can share
that Scene with ordinary text, formulas, and other 2D Visuals. This chapter first
adds text, then shows the optional slide route.

The documentation evaluator reconstructs the earlier Scene privately and keeps
all live 3D rendering on the software backend.

@examples[
 #:eval composition3d-eval
 #:hidden
 (require (only-in racket/math pi)
          animate animate/3d animate/3d/render
          animate/slides animate/slides/pict animate/slides/scene)
 (define brick
   (box3d 5/2 3/2 1
          #:id 'brick
          #:material
          (material3d #:color "cornflowerblue"
                      #:shading 'flat)))
 (define viewpoint
   (perspective-camera3d
    #:position (vec3 3 2 5)
    #:look-at origin3))
 (define model
   (view3d (list brick)
           #:id 'model
           #:width 10 #:height 45/8
           #:camera viewpoint
           #:render-mode 'opaque
           #:background "aliceblue"))
 (define still
   (scene-add (make-scene) model))
 (define (make-lesson initial)
   (define turn
     (scene-play initial
                 (rotate3d-by '(model brick)
                              (axis-angle y-axis3 (/ pi 2)))
                 #:duration 2))
   (define read-turn (scene-wait turn 1))
   (define orbit
     (scene-play read-turn
                 (camera3d-orbit-by 'model #:azimuth (/ pi 2))
                 #:duration 2))
   (scene-wait orbit 1))
 (define lesson
   (make-lesson still))
 (define (guide-3d-pict thunk)
   (parameterize ([current-view3d-renderer3d (software-renderer3d)])
     (guide-pict (thunk))))
]

@section[#:tag "guide-3d-labels"]{Choose what a label follows}
@; introduces: projected-label

A heading placed in the surrounding Scene stays still when the @emph{3D} camera
moves. A @bold{projected label} instead follows a point seen through the 3D view.
It is still ordinary 2D text, so its letters stay upright and readable.

Here the heading stays above the window, while @racket["Box"] follows the box's
origin. First the box moves to the side for two seconds. The six-second
turn-and-orbit sequence follows, making eight seconds in all.

The view is supplied separately to @racket[follow-projected-spatial], so this
helper's @racket[#:target] is the path @racket['(brick)] within that view. That
differs from the full @racket['(model brick)] path used by a motion request.

@examples[
 #:eval composition3d-eval
 #:no-result
 (define heading
   (plain-text "Turn the object, then move the camera"
               #:id 'heading
               #:center (vec2 0 10/3)
               #:font-size 9/25
               #:color "navy"))
 (define box-label
   (follow-projected-spatial
    (plain-text "Box"
                #:id 'box-label
                #:font-size 1/4
                #:color "navy")
    #:view 'model
    #:target '(brick)
    #:offset (vec2 14 16)))
 (define labelled-move
   (scene-play (scene-add still heading box-label)
               (move3d-to '(model brick) (vec3 1 0 0))
               #:duration 2))
 (define captioned-lesson
   (make-lesson labelled-move))
]

The complete captioned sequence lasts eight seconds:

@examples[
 #:eval composition3d-eval
 #:label #f
 (eval:check (scene-duration captioned-lesson) 8)
 (eval:alts
  (scene->pict captioned-lesson 1)
  (guide-3d-pict
   (lambda () (scene->pict captioned-lesson 1))))
]

@three-d-frames["captioned-lesson"]

The label's offset is measured in screen pixels. Its text size is still an
ordinary 2D text size. The default label policy keeps it visible; it does not
promise to hide text behind the box. The Reference describes explicit occlusion
and placement options.

The complete standalone source is
@filepath{scribblings/examples/spatial-slides.rkt}.

@section[#:tag "guide-3d-slide"]{Put the animation in a slide}
@; requires: slide-clip beat slot-action storyboard shot viewport content-clock

This section uses layouts, beats, and the local content clock from
@secref["guide-slides"] and @secref["guide-embedded-content"]. Readers who came
straight from the Quick Start can stop here and return after those chapters.

Wrap the existing Scene with @racket[scene-content]. Do not use
@racket[geometry-content]: that adapter is for the separate Euclidean
construction library, not for every kind of geometry or every 3D object.

@examples[
 #:eval composition3d-eval
 #:no-result
 (define card
   (slide #:id 'spatial-lesson #:layout 'title+figure
     [title "Two ways to change a 3D picture"]
     [figure (scene-content lesson)]
     [body "First turn the box. Then move the camera."]))
 (define clip
   (build-slide card
     (beat 'look #:duration 1)
     (beat 'play #:duration 6
       (play-content 'figure #:to 'end))
     (beat 'read #:duration 2)))
 (define film
   (storyboard
     (storyboard-shot 'demonstration clip)))
]

The slide holds the initial picture for one second. Its @racket[play] beat
advances the embedded Scene's six-second clock. The last beat holds the final
picture for two seconds. The total is nine seconds:

@examples[
 #:eval composition3d-eval
 #:label #f
 (eval:check
  (scene-duration (storyboard->scene film))
  9)
 (eval:alts
  (storyboard->pict film #:at 4)
  (guide-3d-pict
   (lambda () (storyboard->pict film #:at 4))))
]

@three-d-frames["slide-lesson"]

Adding a hold to the slide does not add a second moving clock to the 3D view.
For this embedding we use the uncaptioned @racket[lesson]. The slide supplies
its own title, so we do not place a second native title inside the figure region.

@section[#:tag "guide-3d-where-next"]{Choose the next topic when you need it}

The @seclink["3d-algebra"]{3D reference map} separates solids, materials,
cameras, curves, surfaces, relations, mesh operations, numerical flow, picking,
and rendering internals. None of the mesh-topology or renderer-protocol chapters
is a prerequisite for the examples above.

@secref["cookbook-3d"] collects the complete source programs and short answers
to common placement and camera questions.

@close-eval[composition3d-eval]
