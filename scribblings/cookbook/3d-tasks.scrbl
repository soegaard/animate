#lang scribble/manual
@(require (for-label racket/base animate animate/3d)
          "../private/examples.rkt" "../private/three-d-illustrations.rkt")
@title[#:tag "cookbook-3d"]{3D objects, cameras, and slide figures}

For the step-by-step route, start at @secref["guide-3d-picture"]. These recipes
reuse three source files. Keep them together because the second and third require
the first by a relative filename.

@section[#:tag "recipe-3d-target"]{Move the object, not its window}
Use @tt{move3d-to} with the full path @tt{'(model brick)} and a @tt{vec3}.
Use ordinary @tt{move-to} with @tt{'model} and a @tt{vec2} only when the entire
window should move in the surrounding 2D composition.
@example-part["spatial-motion.rkt" "translation"]
@three-d-frames["object-translation"]

@section[#:tag "recipe-3d-camera"]{Keep the object still and change the view}
An orbit changes the owning view's 3D camera. It does not rotate its objects.
@example-part["spatial-motion.rkt" "camera-motion"]
@three-d-frames["camera-motion"]

@section[#:tag "recipe-3d-complete"]{Copy the complete examples}
Requiring these files creates descriptions, not videos or GUI windows. Render a
Scene or call a picture function explicitly after loading it.
@example-source["first-spatial-picture.rkt"]
@example-source["spatial-motion.rkt"]
@example-source["spatial-slides.rkt"]

@section[#:tag "recipe-3d-software"]{Use the ordinary software renderer}
The examples select filled faces with @tt{#:render-mode 'opaque}; they do not
select OpenGL. Start with the software path. An OpenGL render is an explicit
backend choice, requires a suitable GUI process, and currently has its own
one-worker restriction. It is not the same restriction as the older slide
geometry adapter, which now supports the shared subprocess worker path.
