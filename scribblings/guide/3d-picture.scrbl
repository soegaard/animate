#lang scribble/manual
@(require (for-label racket/base animate animate/3d)
          "../private/guide-examples.rkt"
          "../private/three-d-illustrations.rkt")
@(define picture3d-eval (make-guide-eval))

@title[#:tag "guide-3d-picture"]{Make a first 3D picture}

@; requires: visual coordinates scene sampling pict
This is an optional route through the Guide. You need only the Visual, Scene,
position, and Pict from @secref["guide-getting-started"]. You do not need the
slide chapters to make a 3D animation. Continue to
@secref["guide-3d-motion"] after this chapter, or skip this route when your video
is entirely 2D.

The examples below are evaluated while the manual is built. The hidden
documentation setup explicitly selects Animate's software 3D renderer, so the
Guide does not require an OpenGL context.

@examples[
 #:eval picture3d-eval
 #:hidden
 (require animate animate/3d animate/3d/render)
 (define (guide-3d-pict thunk)
   (parameterize ([current-view3d-renderer3d (software-renderer3d)])
     (guide-pict (thunk))))
]

@section[#:tag "guide-3d-object"]{Make an object}
@; introduces: spatial-visual spatial-coordinates solid3d material3d

A @bold{spatial Visual} describes a 3D object. A box, sphere, curve, or surface
can be a spatial Visual. Unlike an ordinary 2D Visual, it does not go directly
into @racket[scene-add]. We will put it inside a view first.

A 3D point has three coordinates: @racket[(vec3 x y z)]. They describe the
object's position in space, not a position in the output image. The axes are
right-handed. Before moving the camera, think of positive x as right, positive y
as up, and positive z as toward you. A different camera changes how those axes
look on screen; it does not change the coordinates.

@racket[box3d] takes width, height, and depth. Its centre is initially the
origin. A @bold{material} chooses the surface's appearance. We use a blue
material and @racket['flat] shading so the box's flat faces are easy to
distinguish. We do not need individual lights yet: the view has a default light
setup.

@examples[
 #:eval picture3d-eval
 #:no-result
 (define brick
   (box3d 5/2 3/2 1
          #:id 'brick
          #:material
          (material3d #:color "cornflowerblue"
                      #:shading 'flat)))
]

The ID @racket['brick] names this object. It does not name a picture or a file.
Other solid constructors include @racket[cube3d] and @racket[sphere3d]. See the
@seclink["3d-algebra"]{3D reference map} for their options and more kinds of
objects.

@section[#:tag "guide-3d-viewpoint"]{Choose where to look from}
@; introduces: camera3d

A @bold{3D camera} chooses a viewpoint and where it looks. A perspective camera
makes more distant objects look smaller. @racket[origin3] is the point
@racket[(vec3 0 0 0)]. The following camera is above and to one side of the box,
looking toward that origin:

@examples[
 #:eval picture3d-eval
 #:no-result
 (define viewpoint
   (perspective-camera3d
    #:position (vec3 3 2 5)
    #:look-at origin3))
]

Do not confuse this with the ordinary 2D camera. The 3D camera looks at the box.
The ordinary camera chooses which part of the surrounding 2D Scene becomes the
output image. For now we leave that ordinary camera unchanged.

@section[#:tag "guide-3d-view"]{Put the object inside a view}
@; introduces: view3d

A @racket[view3d] is a rectangular window onto a list of spatial Visuals. The
window itself is an ordinary 2D Visual. Its width and height are measured in the
same 2D world units as the circle in the Quick Start, not in 3D object units or
output pixels.

@racket['opaque] draws filled faces. The default, @racket['wireframe], draws
edges. The name @racket['opaque] does not mean the whole 3D system lacks
transparency; it selects the filled-surface rendering path.

@examples[
 #:eval picture3d-eval
 #:no-result
 (define model
   (view3d (list brick)
           #:id 'model
           #:width 10
           #:height 45/8
           #:camera viewpoint
           #:render-mode 'opaque
           #:background "aliceblue"))
]

The box is @racket['brick]; the window is @racket['model]. We give them separate
names because later we will move them separately.

@section[#:tag "guide-3d-scene"]{Use an ordinary Scene}

There is no second 3D timeline to learn. Add the view to a Scene just as you
added the circle in the Quick Start:

@examples[
 #:eval picture3d-eval
 #:no-result
 (define still
   (scene-add (make-scene) model))
]

The Scene still has duration zero:

@examples[
 #:eval picture3d-eval
 #:label #f
 (eval:check (scene-duration still) 0)
]

@verbatim{
Scene
  model                 ordinary 2D view
    camera              viewpoint used inside the view
    brick               spatial Visual
}

The camera is a setting on the view, not another child beside the box. A view
can contain several spatial objects; this example needs only one.

@section[#:tag "guide-3d-picture-output"]{Ask for a picture}

Because @racket[view3d] is an ordinary Visual, the same
@racket[scene->pict] operation used earlier can draw the Scene. The expression
shown below is what you write; the documentation build evaluates it with the
software 3D renderer and adds only page scaling and a one-pixel frame:

@examples[
 #:eval picture3d-eval
 #:label #f
 (eval:alts
  (scene->pict still 0)
  (guide-3d-pict (lambda () (scene->pict still 0))))
]

@three-d-frames["first-picture"]

The complete standalone program is
@filepath{scribblings/examples/first-spatial-picture.rkt}. Merely requiring that
example does not open a window, render a movie, or run an encoder. Rendering
happens only when a picture or output frame is requested.

Next, @secref["guide-3d-motion"] gives this same Scene a duration.

@close-eval[picture3d-eval]
