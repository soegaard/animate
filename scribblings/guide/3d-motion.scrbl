#lang scribble/manual
@(require (for-label racket/base (only-in racket/math pi) animate animate/3d)
          "../private/examples.rkt" "../private/three-d-illustrations.rkt")
@title[#:tag "guide-3d-motion"]{Animate a 3D object and its camera}

@; requires: scene request hold view3d spatial-visual camera3d
Use the box and Scene from @secref["guide-3d-picture"]. Save the following
examples in a second file, @filepath{spatial-motion.rkt}, beside the first one:

@example-part["spatial-motion.rkt" "imports"]

Each of the short examples starts from @racket[still]. They are alternatives,
not successive changes to one variable. We combine operations later in this chapter.

@section[#:tag "guide-3d-turn-object"]{Turn the object inside the view}
@; introduces: spatial-path spatial-motion
A @bold{spatial path} names an object inside a view. The path
@racket['(model brick)] starts with the view's ID and ends with the object's ID.
Use it when the object should change but the surrounding window should stay put.

@racket[axis-angle] makes a rotation from an axis and an angle in radians.
@racket[y-axis3] is the positive y axis. An angle of @racket[(/ pi 2)] is a
quarter turn. This is an orientation change, not a count of repeated full turns.

@example-part["spatial-motion.rkt" "object-motion"]
@three-d-frames["object-motion"]

The box turns; its 3D camera and the rectangle containing the picture remain
unchanged. @racket[scene-play] supplies the duration just as it did in 2D.

To change the box's position instead, use a 3D point:

@example-part["spatial-motion.rkt" "translation"]
@three-d-frames["object-translation"]

This moves the box in the view's spatial coordinate system. Use @racket[group3d]
to move several objects together. Each child then has a position relative to that
group. A path through a group might be @racket['(model assembly brick)].

@section[#:tag "guide-3d-orbit-camera"]{Move the camera around the object}
@; introduces: camera3d-motion
A camera request names only the owning view, @racket['model].
@racket[camera3d-orbit-by] moves the 3D camera around a point while keeping it
looking at that point. Its default centre is the origin. @tt{#:azimuth} is the
horizontal orbit angle, in radians.

@example-part["spatial-motion.rkt" "camera-motion"]
@three-d-frames["camera-motion"]

The box itself has not moved. It looks different because we see it from another
side. The window stays at the same place on the page.

@section[#:tag "guide-3d-move-panel"]{Move the whole window}
The view is an ordinary 2D Visual, so ordinary @racket[move-to] moves the whole
window. This time the target is @racket['model] and the destination is a
@racket[vec2], not a @racket[vec3].

@example-part["spatial-motion.rkt" "panel-motion"]
@three-d-frames["panel-motion"]

The box and its camera keep their relationship. Only the placement of their
picture within the surrounding Scene changes.

@tabular[#:sep @hspace[1]
 (list
  (list @bold{Change} @bold{Target} @bold{Operation})
  (list "Box position" @tt{'(model brick)} @tt{move3d-to})
  (list "Box orientation" @tt{'(model brick)} @tt{rotate3d-by})
  (list "3D viewpoint" @tt{'model} @tt{camera3d-orbit-by})
  (list "Window on the page" @tt{'model} @tt{move-to}))]

@section[#:tag "guide-3d-small-lesson"]{Build a complete six-second sequence}
First turn the object for two seconds. Hold it for one second. Then orbit the
camera for two seconds and hold again. A small function lets us reuse this timing
with or without a surrounding heading:

@example-part["spatial-motion.rkt" "lesson"]
@three-d-frames["lesson"]

The @racket[lesson] value is an ordinary Scene. Use the frame and MP4 commands
from @secref["guide-rendering-a-video"] with this value. Add a final hold whenever
the finished picture needs time on screen: a video's frame grid does not normally
include the exact endpoint as an extra frame.

The software renderer works without an OpenGL window. OpenGL is a separate,
optional rendering choice with its own restrictions; it is not required for any
example in this route. Next, @secref["guide-3d-composition"] adds text and a slide.
