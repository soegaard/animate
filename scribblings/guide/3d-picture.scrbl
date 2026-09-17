#lang scribble/manual
@(require (for-label racket/base animate animate/3d)
          "../private/examples.rkt" "../private/three-d-illustrations.rkt")
@title[#:tag "guide-3d-picture"]{Make a first 3D picture}

@; requires: visual coordinates scene sampling pict
This is an optional route through the Guide. You need only the Visual, Scene,
position, and Pict from @secref["guide-getting-started"]. You do not need the
slide chapters to make a 3D animation. Continue to @secref["guide-3d-motion"]
after this chapter, or skip this route when your video is entirely 2D.

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

@racket[box3d] takes width, height, and depth. Its centre is initially the origin.
A @bold{material} chooses the surface's appearance. We use a blue material and
@tt{'flat} shading so the box's flat faces are easy to distinguish. We do not
need to set up individual lights yet: the view has a default light setup.

Save the following pieces in @filepath{first-spatial-picture.rkt}.
@example-part["first-spatial-picture.rkt" "imports"]
@example-part["first-spatial-picture.rkt" "solid"]

The ID @racket['brick] names this object. It does not name a picture or a file.
Other solid constructors include @racket[cube3d] and @racket[sphere3d]. See the
@seclink["3d-algebra"]{3D reference map} for their options and more kinds of objects.

@section[#:tag "guide-3d-viewpoint"]{Choose where to look from}
@; introduces: camera3d
A @bold{3D camera} chooses a viewpoint and where it looks. A perspective camera
makes more distant objects look smaller. @racket[origin3] is the point
@racket[(vec3 0 0 0)]. The following camera is above and to one side of the box,
looking toward that origin:

@example-part["first-spatial-picture.rkt" "camera"]

Do not confuse this with the ordinary 2D camera. The 3D camera looks at the box.
The ordinary camera chooses which part of the surrounding 2D Scene becomes the
output image. For now we leave that ordinary camera unchanged.

@section[#:tag "guide-3d-view"]{Put the object inside a view}
@; introduces: view3d
A @racket[view3d] is a rectangular window onto a list of spatial Visuals. The
window itself is an ordinary 2D Visual. Its width and height are measured in the
same 2D world units as the circle in the Quick Start, not in 3D object units or
output pixels.

@tt{'opaque} draws filled faces. The default, @tt{'wireframe}, draws edges.
The name @tt{'opaque} does not mean the whole 3D system lacks transparency; it
selects the filled-surface rendering path.

@example-part["first-spatial-picture.rkt" "view"]

The box is @racket['brick]; the window is @racket['model]. We give them separate
names because later we will move them separately.

@section[#:tag "guide-3d-scene"]{Use an ordinary Scene}
There is no second 3D timeline to learn. Add the view to a Scene just as you added
the circle in the Quick Start:

@example-part["first-spatial-picture.rkt" "scene"]

@verbatim{
Scene
  model                 ordinary 2D view
    camera              viewpoint used inside the view
    brick               spatial Visual
}

The camera is a setting on the view, not another child beside the box. A view can
contain several spatial objects; this example needs only one.

@section[#:tag "guide-3d-picture-output"]{Ask for a picture}
The Scene still has duration zero. It is enough for a single picture.
@racket[scene-camera-at] gets the surrounding Scene's 2D camera at a given time.
Use it with the state sampled at the same time; the view keeps its own 3D camera:

@example-part["first-spatial-picture.rkt" "picture"]
@three-d-frames["first-picture"]

Call @racket[(picture-at 0)] in DrRacket. Merely requiring this example does not
open a window, render a frame, or run a video encoder. The function call renders
the requested picture.

Next, @secref["guide-3d-motion"] gives this same Scene a duration. Keep this file:
the following examples reuse it rather than redefining the box and camera.
