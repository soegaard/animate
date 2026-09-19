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


@title[#:tag "cookbook-camera-views-and-overlays"]{Camera Views and Fixed Overlays}

Animate the camera, frame a subject, and keep titles or callouts fixed in the output frame.

API reference: @secref["cameras"], @secref["frame-space"].

@local-table-of-contents[]

@; recipe-redistribution begin: animated-camera
@section[#:tag "animated-camera"]{Animated Camera Views}

Every scene and timeline clip stores one immutable camera. The camera can be
sampled independently from the Visual state, and both tracks are rendered at
the same absolute time.

A scene may begin with an explicit camera:

@racketblock[
(define initial-camera
  (make-camera #:world-width 14
               #:center origin))

(define scene
  (make-scene #:camera initial-camera))
]

Camera and Visual requests can share one play clip:

@racketblock[
(scene-play scene
            (move-to 'marker (vec2 3 1))
            (camera-pan-to (vec2 2 1))
            (camera-zoom-by 2)
            #:duration 2)
]

Camera requests use the same composition vocabulary as Visual requests:

@racketblock[
(scene-play scene
            (succession
             (camera-pan-to (vec2 -4 0))
             (animation-group
              (camera-follow 'marker)
              (camera-zoom-by 2)))
            #:duration 4)
]

Here pan occupies the first half. Follow and zoom occupy the second half in
parallel because they write separate camera components. A top-level
@racket[timed] camera request uses literal local seconds; inside a composition,
it follows the same duration-scaling rules as a timed Visual request. Each
camera leaf compiles from the exact view at its local start. A local
@racket[camera-follow] tracks the sampled world-space target only during its
own interval and then retains that endpoint view.

The camera center and visible world width are independent components. Pan and
follow requests change the center. Zoom requests change visible width. A fit
request changes both components. Requests for disjoint components may run
together; overlapping requests that reserve the same component raise an
exception. Relative pan and zoom requests compile from the camera at the start
of their own local interval.

@racket[camera-zoom-by] uses magnification rather than a width multiplier. A
factor of two divides the visible world width by two and zooms in. A factor of
one half doubles the visible width and zooms out. Visible world width is
interpolated linearly between the clip-start and target widths.

@racket[scene-camera-at] samples arbitrary times using the same half-open clip
selection and closed total-duration interval as @racket[scene-sample]. A wait
clip holds both state and camera. @racket[scene-set-camera] replaces only the
current endpoint camera and appends no clip.

@racket[scene->pict], @racket[scene-frame->bitmap], and
@racket[render-frames!] use the sampled scene camera when their
@racket[#:camera] argument is @racket[#f]. Supplying a camera is a deliberate
static override and ignores every camera request for that render.

The camera's pixel dimensions, aspect ratio, and background stay fixed while
its center or visible width changes. Renderer-aware layout continues to accept
a static camera value. To measure for one sampled view, pass
@racket[(scene-camera-at scene time)] explicitly. Layout does not reflow
automatically on every frame.

This version does not animate camera rotation, pixel dimensions, or background
style.

Render the pan-and-zoom example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/camera-pan-and-zoom.rkt \
  frames/camera-pan-and-zoom \
  camera-pan-and-zoom.mp4

open camera-pan-and-zoom.mp4
}



@; recipe-redistribution end: animated-camera

@; recipe-redistribution begin: camera-framing-following
@section[#:tag "camera-framing-following"]{
  Automatic Camera Framing and Following}

Camera fitting uses renderer-aware measurements, while camera following tracks
a target for one clip. Both use ordinary requests accepted by
@racket[scene-play].

@subsection{Fitting a Rendered Box}

A fit request can be built from a world-coordinate layout box:

@racketblock[
(define fit-request
  (camera-fit-layout-box box
                         #:camera (scene-current-camera scene)
                         #:padding 1/2))

(scene-play scene fit-request #:duration 1)
]

The target center is the center of @racket[box]. Padding is added equally on all
four sides in world units. The target visible width is then enlarged when
needed so the padded height fits the camera's pixel aspect ratio. Pixel width,
pixel height, and background are preserved.

The @racket[#:camera] value supplies the aspect ratio used to compute the fit.
Use the same camera, or at least the same pixel aspect ratio, as the scene in
which the request will run. A fit request stores only the resulting center and
visible width. It does not retain the box or recompute it later.

@subsection{Fitting Visuals and Scene Targets}

Fit a nonempty list of Visuals with the renderer list used for final output:

@racketblock[
(camera-fit-visuals (list diagram title)
                    #:camera (scene-current-camera scene)
                    #:renderers default-pict-renderers
                    #:padding 1/2)
]

This operation measures complete renderer boxes, not tight visible-ink bounds.
Transparent padding, semantic anchors, group extents, cosmetic stroke padding,
and custom-renderer padding can therefore affect the result. Measuring a
nonempty formula with the built-in formula renderer can invoke LaTeX and
Poppler. The Visuals must use one containing coordinate system.

The current scene can be fitted directly:

@racketblock[
(camera-fit-scene scene #:padding 1/2)

(camera-fit-scene scene
                  #:targets (list 'marker 'label)
                  #:padding 1)
]

With no @racket[#:targets], every current top-level world-space Visual is
included and frame-space overlays are ignored. Otherwise, each Visual value or
symbol is resolved by stable identity against @racket[(scene-current-state
scene)]. An explicit nested @racket[visual-path?] is also accepted and measured
after every enclosing transform/opacity is composed. An empty world scene, empty
target list, missing target, or explicitly selected frame-space target raises an
exception. For a focused explanation, @racket[camera-focus] names one nested or
top-level subject and its chosen context directly.

Both operations are snapshots. Geometry, transforms, text metrics, renderer
results, or scene membership changed later in the same play clip are not
remeasured. To fit a planned endpoint, construct and measure Visual values that
already describe that endpoint.

A fit request changes center and visible world width together. It conflicts
with pan, zoom, follow, or another fit request in the same clip. It may run with
any disjoint Visual animation.

@subsection{Following a Moving Visual}

Follow one top-level Visual while it moves:

@racketblock[
(scene-play scene
            (move-to marker destination)
            (camera-follow marker)
            (camera-zoom-by 2)
            #:duration 2)
]

At clip compilation, the request records the target's prepared start position
and normalized horizontal and vertical frame offset. At each sample it reads the
target's actual sampled @racket[visual-position] at the same eased progress as
the Visual motion. The camera center is chosen so that sampled reference
position remains at the same pixel coordinates. When zoom runs simultaneously,
the world-space offset shrinks or grows with the sampled visible width and
height. This sampled-state rule lets following trace @racket[move-along-path]
through a polyline elbow or Bézier curve instead of interpolating only between
the target's clip endpoints.

Following tracks @racket[visual-position], not a rendered bounding box. It is
clip-local and does not install a persistent observer. Clips without a follow
request keep the ordinary camera-only sampling path; scene-state sampling is
needed only when following depends on it. Repeat @racket[camera-follow] in each
later clip that should continue tracking.

The target must be a top-level world-space Visual in the prepared clip state;
frame-space overlays cannot be camera-follow targets. It may be introduced by
@racket[fade-in] or @racket[create] in the same clip. It may also be followed
through @racket[fade-out] or @racket[uncreate], because the pre-removal sampled
motion state is retained for camera completion before the structural endpoint is
stored.

A follow request changes only the center component. It may run with one zoom
request, but it conflicts with pan, fit, or another follow request. Follow and
fit endpoints obey the easing result; neither has a structural endpoint
override.

Render the camera-fitting example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/camera-framing-and-following.rkt \
  frames/camera-framing-and-following \
  camera-framing-and-following.mp4

open camera-framing-and-following.mp4
}




@; recipe-redistribution end: camera-framing-following

@; recipe-redistribution begin: fixed-overlays-callouts
@section[#:tag "fixed-overlays-callouts"]{
  Fixed-in-Frame Overlays and Callouts}

Frame space is an origin-centered coordinate domain for presentation content
that must remain stable while the world camera moves. The semantic
wrapper snapshots only a visible frame width; Pict rendering remains in the
adapter.

Freeze a title at an explicit frame position:

@racketblock[
(define title
  (fixed-in-frame
   (plain-text "Fixed title"
               #:id 'title
               #:font-size 1/2)
   #:camera initial-camera
   #:at (vec2 0 3)))
]

Frame-space Visuals remain ordinary affine and opacity animation targets. Later
world pan and zoom do not alter their screen position or local render scale. A
compound overlay is made by grouping ordinary content first and wrapping the
complete group; frame-space wrappers themselves remain top-level.

Add a fixed annotation whose leader tracks a moving world Visual:

@racketblock[
(define note
  (callout
   (plain-text "moving point" #:id 'note #:font-size 2/5)
   marker
   #:camera initial-camera
   #:at (vec2 4 2)
   #:connector-stroke "navy"
   #:connector-width 2))

(scene-play
 (scene-add (make-scene #:camera initial-camera) marker title note)
 (move-to marker destination)
 (camera-pan-by (vec2 2 1))
 (camera-zoom-by 2)
 #:duration 2)
]

The callout stores a Visual target as its stable identity. Complete scene
rendering resolves that identity against each sampled top-level state, draws the
leader from the target's current world pixel position to the fixed annotation
box, and then places the annotation. A literal @racket[vec2] target instead
represents one fixed world point.

Renderer-aware relative layout measures frame-space Visuals with their captured
frame scale. World and frame domains cannot be mixed in one layout calculation,
and frame Visuals combined together must share the same captured frame width.
Camera fit and follow remain world-only.

The canonical movie moves its marker along the same piecewise-linear sample
edges that define the displayed quadratic graph. The traversal uses one
@racket[move-along-path] clip while the camera keeps the
original continuous linear pan and zoom trajectory over the three seconds.

Render the canonical fixed-overlay example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/fixed-overlays-and-callouts.rkt \
  frames/fixed-overlays-and-callouts \
  fixed-overlays-and-callouts.mp4

open fixed-overlays-and-callouts.mp4
}



@; recipe-redistribution end: fixed-overlays-callouts
