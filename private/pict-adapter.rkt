#lang racket/base

;;;
;;; Pict Adapter
;;;

;; Converts semantic Visual values, groups, formula assemblies, frame-space
;; overlays, callouts, and scene states to static picts.
;; Optional global opacity is applied after renderer dispatch or composite
;; composition.
;;
;; Renderer dispatch is delegated to an explicit ordered list of Pict renderer
;; implementations. This module does not write files or mutate scene data.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/class
         racket/list
         (only-in pict
                  blank
                  cellophane
                  cc-superimpose
                  clip
                  dc
                  draw-pict
                  frame
                  filled-rectangle
                  pict-height
                  pict-width
                  pin-over
                  scale)
         (only-in racket/draw
                  dc-path%
                  make-brush
                  make-pen
                  region%)
         "affine-map-visual.rkt"
         "affine-pict.rkt"
         "affine-transform.rkt"
         "anchored-pict.rkt"
         "annotation-geometry.rkt"
         "arrow-visual.rkt"
         "axes-visual.rkt"
         "camera.rkt"
         "derived-visual.rkt"
         "relation-visual.rkt"
         "resolvable-visual.rkt"
         "clipped-visual.rkt"
         "formula-parts-visual.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "layout-box.rkt"
         "number-line-visual.rkt"
         "pict-renderer.rkt"
         "point-marker-visual.rkt"
         "path-geometry.rkt"
         "scene-state.rkt"
         "3d/projected-label.rkt"
         "3d/view3d-visual.rkt"
         "shape-pict-renderers.rkt"
         "visual-selection.rkt"
         "visual-model.rkt")

;; Exports
(provide default-pict-renderers
         visual->pict
         scene-state->pict)


;;;
;;; Visual Conversion
;;;

; visual->pict : visual? camera?
;                [#:renderers (listof pict-renderer?)]
;                -> pict?
;;   Converts visual through renderer dispatch or recursive composite composition.
(define (visual->pict visual camera
                      #:renderers [renderers default-pict-renderers])
  (unless (visual? visual)
    (raise-argument-error 'visual->pict "visual?" visual))
  (unless (camera? camera)
    (raise-argument-error 'visual->pict "camera?" camera))
  (check-pict-renderer-list 'visual->pict renderers)
  (define render-camera
    (visual-render-camera visual camera))
  (define rendered-pict
    (render-visual-or-composite visual render-camera renderers))
  (apply-semantic-opacity visual rendered-pict))

; visual-render-camera : visual? camera? -> camera?
;;   Returns the world camera or the stable frame camera selected by visual.
(define (visual-render-camera visual camera)
  (if (frame-space-visual? visual)
      (frame-space-camera
       camera
       (frame-space-visual-frame-width visual))
      camera))

; render-visual-or-composite : visual? camera?
;                              (listof pict-renderer?)
;                              -> pict?
;;   Uses an explicit renderer or a built-in recursive composite compositor.
(define (render-visual-or-composite visual camera renderers)
  (when (resolvable-visual? visual)
    (raise-arguments-error
     'visual->pict
     "a resolvable Visual must be resolved against a scene state before rendering"
     "visual-id" (visual-id visual)))
  (cond
    [(transient-visual? visual)
     (render-visual-or-composite
      (transient-visual-underlying visual)
      camera
      renderers)]
    [(affine-map-visual? visual)
     (affine-map-content->pict visual camera renderers)]
    [else
     (define renderer
       (find-supporting-pict-renderer visual renderers))
     (cond
      [renderer
       (render-visual-with-pict-renderer renderer visual camera)]
    [(fixed-in-frame-visual? visual)
     (frame-space-content->pict
      visual
      (fixed-in-frame-visual-content visual)
      camera
      renderers)]
    [(callout-visual? visual)
     (frame-space-content->pict
      visual
      (callout-visual-content visual)
      camera
      renderers)]
    [(camera-view-visual? visual)
     (raise-arguments-error
      'visual->pict
      "a camera-view must be resolved against a scene state before rendering"
      "visual-id" (visual-id visual))]
    [(number-line-visual? visual)
     (render-visual-or-composite
      (number-line-visual->path-visual visual)
      camera
      renderers)]
    [(point-marker-visual? visual)
     (render-visual-or-composite
      (point-marker-visual->visual visual)
      camera
      renderers)]
    [(clipped-visual? visual)
     (clipped-visual->pict visual camera renderers)]
    [(group-visual? visual)
     (group-visual->pict visual camera renderers)]
    [(formula-assembly-visual? visual)
     (group-visual->pict
      (formula-assembly-visual-group visual)
      camera
      renderers)]
    [else
     (raise-arguments-error
      'visual->pict
      "no Pict renderer supports the Visual"
     "visual" visual)])]))

;; affine-map-content->pict : affine-map-visual? camera?
;;                            (listof pict-renderer?) -> pict?
;; Renders canonical content through the normal dispatcher, applies the full
;; semantic map's linear part around the Pict centre, and then applies any
;; ordinary enclosing-group scale/rotation retained by the affine protocol.
;; The scene compositor separately places the result at the map's translated
;; world reference point.
(define (affine-map-content->pict visual camera renderers)
  (define content
    (affine-map-visual-content visual))
  (when (frame-space-visual? content)
    (raise-arguments-error
     'visual->pict
     "a world-space Visual inside affine-map"
     "visual-id" (visual-id content)))
  (define map
    (affine-map-visual-map visual))
  (define mapped-pict
    (cond
      ;; An affine-mapped group normally retains its established Pict extent.
      ;; Near a reflection's singular midpoint, however, pass the map to the
      ;; affected child instead.  That prevents padded child Picts from
      ;; displacing a very thin mapped path.
      [(and (group-visual? content)
            (group-has-near-singular-affine-child? content map))
       (visual->pict
        (group-visual-with-children
         content
         (for/list ([child (in-list (group-visual-children content))])
           (affine-map child map)))
        camera
        #:renderers renderers)]
      ;; Map semantic vector geometry directly through that same
      ;; near-singular interval.  Rendering a circle, rectangle, arrow, or
      ;; axes to a padded Pict and then squashing that Pict loses the thin
      ;; shape entirely at rank one.  Normalising these primitives to paths
      ;; keeps their geometry and their vertical extent exact without changing
      ;; the appearance of ordinary affine transformations.
      ;; Arrows and axes are directed semantic objects.  Their shafts follow
      ;; the affine map, but their cosmetic arrowheads are redrawn from those
      ;; mapped directions for the entire animation.  Restricting this to the
      ;; singular interval creates a visible head-size jump at its boundary.
      [(arrow-visual? content)
       (affine-arrow->pict content map camera renderers)]
      [(axes-visual? content)
       (affine-axes->pict content map camera renderers)]
      [(and (geometry-backed-visual? content)
            (near-singular-affine? map))
       (affine-path->pict
        (geometry-backed-visual->path-visual content)
        map camera renderers)]
      [else
       (fade-pict-through-singularity
        (affine2-pict-transform
         (visual->pict content camera #:renderers renderers)
         map)
        map)]))
  (define transformed-pict
    (scale-pict-if-needed mapped-pict (visual-scale visual)))
  (rotate-pict-if-needed transformed-pict (visual-rotation visual)))

;; Near a reflection midpoint, a closed path's narrow acute corners make a
;; Pict-space miter visibly overshoot the geometric endpoints.  A third covers
;; only the visually thin portion of the identity-to-reflection interpolation.
(define near-singular-determinant 1/3)

;; near-singular-affine? : affine2? -> boolean?
(define (near-singular-affine? map)
  (<= (abs (linear2-determinant (affine2-linear map)))
      near-singular-determinant))

;; fade-pict-through-singularity : pict? affine2? -> pict?
;; Imported/raster Picts have no geometric representation to preserve at a
;; rank-one affine map.  Instead of leaving a malformed one-pixel remnant,
;; fade them continuously over the same narrow interval used for vector
;; geometry.  At rank one they are deliberately absent.
(define (fade-pict-through-singularity rendered-pict map)
  (cond
    [(not (near-singular-affine? map)) rendered-pict]
    [else
     (define determinant
       (abs (linear2-determinant (affine2-linear map))))
     (define opacity
       (/ determinant near-singular-determinant))
     (if (zero? opacity)
         (blank 1 1)
         (cellophane rendered-pict opacity))]))

;; group-has-near-singular-affine-child? : group-visual? affine2? -> boolean?
;; Returns whether passing `map` down to one direct child reaches the thin part
;; of a reflection.  Ordinary affine-mapped groups take the established Pict
;; path above without any representation change.
(define (group-has-near-singular-affine-child? content map)
  (for/or ([child (in-list (group-visual-children content))])
    (and (affine-map-visual? child)
         (near-singular-affine?
          (affine2-compose map (affine-map-visual-map child))))))

;; geometry-backed-visual? : visual? -> boolean?
;; These Visuals have canonical vector geometry which can be passed to the
;; path renderer when an enclosing affine map approaches rank one.
(define (geometry-backed-visual? visual)
  (or (path-visual? visual)
      (circle-visual? visual)
      (rectangle-visual? visual)
      (arrow-visual? visual)
      (axes-visual? visual)))

;; geometry-backed-visual->path-visual : visual? -> path-visual?
;; Converts only the rendering representation; the source Visual remains the
;; authoritative semantic value in the scene state.
(define (geometry-backed-visual->path-visual visual)
  (cond
    [(path-visual? visual) visual]
    [(circle-visual? visual) (circle->path-visual visual)]
    [(rectangle-visual? visual) (rectangle->path-visual visual)]
    [(arrow-visual? visual) (arrow->path-visual visual)]
    [(axes-visual? visual) (axes->path-visual visual)]
    [else
     (raise-argument-error
      'geometry-backed-visual->path-visual
      "geometry-backed-visual?"
      visual)]))

;; circle->path-visual : circle-visual? -> path-visual?
;; A cubic circle is sufficient here because it is only used in the thin
;; affine interval; the ordinary renderer remains the exact ellipse renderer.
(define (circle->path-visual visual)
  (define radius (circle-visual-radius visual))
  (define k 0.5522847498307936)
  (define (point x y) (vec2 (* radius x) (* radius y)))
  (make-path-visual
   (path-geometry
    (list
     (path-subpath
      (point 1 0)
      (list (cubic-bezier-path-segment (point 1 k) (point k 1) (point 0 1))
            (cubic-bezier-path-segment (point (- k) 1) (point -1 k) (point -1 0))
            (cubic-bezier-path-segment (point -1 (- k)) (point (- k) -1) (point 0 -1))
            (cubic-bezier-path-segment (point k -1) (point 1 (- k)) (point 1 0)))
      #t)))
   #:id (visual-id visual)
   #:center (visual-position visual)
   #:rotation (visual-rotation visual)
   #:scale (visual-scale visual)
   #:opacity (visual-opacity visual)
   #:fill (circle-visual-fill visual)
   #:stroke (circle-visual-stroke visual)
   #:stroke-width (circle-visual-stroke-width visual)))

;; rectangle->path-visual : rectangle-visual? -> path-visual?
(define (rectangle->path-visual visual)
  (define half-width (/ (rectangle-visual-width visual) 2))
  (define half-height (/ (rectangle-visual-height visual) 2))
  (make-path-visual
   (polygon-path
    (list (vec2 (- half-width) (- half-height))
          (vec2 half-width (- half-height))
          (vec2 half-width half-height)
          (vec2 (- half-width) half-height)))
   #:id (visual-id visual)
   #:center (visual-position visual)
   #:rotation (visual-rotation visual)
   #:scale (visual-scale visual)
   #:opacity (visual-opacity visual)
   #:fill (rectangle-visual-fill visual)
   #:stroke (rectangle-visual-stroke visual)
   #:stroke-width (rectangle-visual-stroke-width visual)))

;; arrow->path-visual : arrow-visual? -> path-visual?
(define (arrow->path-visual visual)
  (make-path-visual
   ;; Retain the full semantic shaft here.  affine-tipped-path->pict paints
   ;; the filled tip above it while it exists, then exposes the shaft all the
   ;; way to the semantic endpoint as that tip fades at rank one.
   (arrow-visual-path-geometry visual)
   #:id (visual-id visual)
   #:center (visual-position visual)
   #:rotation (visual-rotation visual)
   #:scale (visual-scale visual)
   #:opacity (visual-opacity visual)
   #:fill (arrow-visual-stroke visual)
   #:stroke (arrow-visual-stroke visual)
   #:stroke-width (arrow-visual-stroke-width visual)))

;; axes->path-visual : axes-visual? -> path-visual?
(define (axes->path-visual visual)
  (make-path-visual
   (axes-visual-path-geometry visual)
   #:id (visual-id visual)
   #:center (visual-position visual)
   #:rotation (visual-rotation visual)
   #:scale (visual-scale visual)
   #:opacity (visual-opacity visual)
   #:fill (axes-visual-stroke visual)
   #:stroke (axes-visual-stroke visual)
   #:stroke-width (axes-visual-stroke-width visual)))

;; affine-arrow->pict : arrow-visual? affine2? camera?
;;                       (listof pict-renderer?) -> pict?
;; An arrow is a semantic directed segment, not a generic filled triangle.
;; Map its endpoints and redraw its cosmetic head in the new direction.  This
;; retains an intelligible arrow at the rank-one instant instead of shearing
;; its head into an unrelated spur.
(define (affine-arrow->pict content map camera renderers)
  (define start
    (affine2-apply-vector map (arrow-visual-start content)))
  (define end
    (affine2-apply-vector map (arrow-visual-end content)))
  (if (zero? (vec2-distance start end))
      ;; A collapsed directed segment has no direction for an arrowhead.  The
      ;; ordinary path fallback preserves any remaining shaft geometry.
      (affine-path->pict (arrow->path-visual content) map camera renderers)
      (visual->pict
       (arrow start end
              #:id (visual-id content)
              #:opacity (visual-opacity content)
              #:stroke (arrow-visual-stroke content)
              #:stroke-width (arrow-visual-stroke-width content)
              #:tip-length (arrow-visual-tip-length content)
              #:tip-width (arrow-visual-tip-width content)
              #:start-tip? (arrow-visual-start-tip? content)
              #:end-tip? (arrow-visual-end-tip? content))
       camera #:renderers renderers)))

;; affine-axes->pict : axes-visual? affine2? camera?
;;                      (listof pict-renderer?) -> pict?
;; Maps the axes, tick, and shaft geometry directly, then redraws each visible
;; directional tip from its transformed axis segment.  A tip fades only when
;; its own axis collapses, while a perpendicular axis keeps its normal head.
(define (affine-axes->pict content map camera renderers)
  (define original-path
    (axes-visual-path-geometry content))
  (define mapped-path
    (map-path-geometry-through-affine original-path map))
  (define open-path
    (path-geometry
     (filter (lambda (subpath) (not (path-subpath-closed? subpath)))
             (path-geometry-subpaths mapped-path))))
  (define shaft-pict
    (visual->pict
     (path-visual-with-geometry (axes->path-visual content) open-path #:fill #f)
     camera #:renderers renderers))
  (define original-subpaths
    (path-geometry-subpaths original-path))
  (define x-shaft (car original-subpaths))
  (define y-shaft (cadr original-subpaths))
  (define tip-picts
    (filter values
            (list (axes-tip->pict content map x-shaft
                                   (axes-visual-x-tip? content)
                                   camera renderers)
                  (axes-tip->pict content map y-shaft
                                   (axes-visual-y-tip? content)
                                   camera renderers))))
  (apply cc-superimpose shaft-pict tip-picts))

;; axes-tip->pict : axes-visual? affine2? path-subpath? boolean? camera?
;;                   (listof pict-renderer?) -> (or/c pict? #f)
(define (axes-tip->pict content map shaft enabled? camera renderers)
  (cond
    [(not enabled?) #f]
    [else
     (define original-start (path-subpath-start shaft))
     (define original-end
       (line-path-segment-end (car (path-subpath-segments shaft))))
     (define mapped-start
       (affine2-apply-vector map original-start))
     (define mapped-end
       (affine2-apply-vector map original-end))
     (define original-length (vec2-distance original-start original-end))
     (define mapped-length (vec2-distance mapped-start mapped-end))
     (cond
       [(zero? mapped-length) #f]
       [else
        (define tip-opacity
          (min 1 (/ mapped-length original-length)))
        (visual->pict
         (path-visual-with-geometry
          (axes->path-visual content)
          (path-geometry
           (list
            (arrowhead-subpath mapped-end mapped-start
                               (axes-visual-tip-length content)
                               (axes-visual-tip-width content))))
          #:opacity (* (visual-opacity content) tip-opacity))
         camera #:renderers renderers)])]))

;; vec2-distance : vec2? vec2? -> nonnegative-real?
(define (vec2-distance start end)
  (define delta-x (- (vec2-x end) (vec2-x start)))
  (define delta-y (- (vec2-y end) (vec2-y start)))
  (sqrt (+ (* delta-x delta-x)
           (* delta-y delta-y))))

;; map-path-geometry-through-affine : path-geometry? affine2? -> path-geometry?
(define (map-path-geometry-through-affine path map)
  (path-geometry-map-points
   path
   (lambda (point)
     (affine2-apply-vector map point))))

;; path-visual-with-geometry : path-visual? path-geometry?
;;                              [#:fill any/c] [#:opacity opacity?]
;;                              -> path-visual?
(define (path-visual-with-geometry content geometry
                                   #:fill [fill (path-visual-fill content)]
                                   #:opacity [opacity (visual-opacity content)])
  (make-path-visual
   geometry
   #:id (visual-id content)
   #:center (visual-position content)
   #:rotation (visual-rotation content)
   #:scale (visual-scale content)
   #:opacity opacity
   #:fill fill
   #:stroke (path-visual-stroke content)
   #:stroke-width (path-visual-stroke-width content)))

;; affine-path->pict : path-visual? affine2? camera?
;;                     (listof pict-renderer?) -> pict?
;; Renders a path through its mapped world geometry.  At rank one a closed
;; filled contour has no area, so it becomes its open boundary stroke; for all
;; other maps, fill and closed-path semantics are preserved unchanged.
(define (affine-path->pict content map camera renderers)
  (define mapped-path
    (map-path-geometry-through-affine (path-visual-path content) map))
  (define singular?
    (zero? (linear2-determinant (affine2-linear map))))
  (define rendered-path
    (if singular?
        (path-geometry
         (for/list ([subpath (in-list (path-geometry-subpaths mapped-path))])
           (path-subpath (path-subpath-start subpath)
                         (path-subpath-segments subpath)
                         #f)))
        mapped-path))
  (define transformed-content
    (path-visual-with-geometry
     content rendered-path
     #:fill (and (not singular?) (path-visual-fill content))))
  (visual->pict transformed-content camera #:renderers renderers))

; frame-space-content->pict : frame-space-visual? visual? camera?
;                             (listof pict-renderer?) -> pict?
;;   Renders content at frame-local origin and applies the wrapper transform.
(define (frame-space-content->pict wrapper content camera renderers)
  (define local-content
    (visual-with-position content origin))
  (unless (and (visual? local-content)
               (eq? (visual-id local-content)
                    (visual-id content))
               (equal? (visual-position local-content)
                       origin))
    (raise-arguments-error
     'visual->pict
     "frame-space content must preserve identity and install local position"
     "content" content
     "result" local-content))
  (define content-pict
    (visual->pict local-content
                  camera
                  #:renderers renderers))
  (define scaled-pict
    (scale-pict-if-needed content-pict
                          (visual-scale wrapper)))
  (rotate-pict-if-needed scaled-pict
                         (visual-rotation wrapper)))

; apply-semantic-opacity : visual? pict? -> pict?
;;   Applies optional semantic opacity after rendering or group composition.
(define (apply-semantic-opacity visual rendered-pict)
  (cond
    [(not (opacity-visual? visual))
     rendered-pict]
    [else
     (define opacity
       (visual-opacity visual))
     (unless (opacity? opacity)
       (raise-arguments-error
        'visual->pict
        "an opacity Visual must return a finite real in [0, 1]"
        "visual" visual
        "opacity" opacity))
     (if (= opacity 1)
         rendered-pict
         (cellophane rendered-pict opacity))]))


;;;
;;; Group Conversion
;;;

(struct placed-child (pict center-x center-y)
  #:transparent)

;; placed-child records one rendered child relative to a group anchor.
;;  - pict      pict?   complete rendered child Pict.
;;  - center-x  real?   horizontal center offset in pixels.
;;  - center-y  real?   downward vertical center offset in pixels.

; group-visual->pict : group-visual? camera? (listof pict-renderer?) -> pict?
;;   Composes resolved children around the group's local anchor.
(define (group-visual->pict group camera renderers)
  (define placed-children
    (for/list ([child
                (in-list
                 (group-visual-resolved-children group))])
      (resolved-child->placed-child child camera renderers)))
  (if (null? placed-children)
      (blank 1 1)
      (compose-placed-children placed-children)))

; resolved-child->placed-child : affine-visual? camera?
;                                (listof pict-renderer?)
;                                -> placed-child?
;;   Renders one resolved child and converts its local position to pixels.
(define (resolved-child->placed-child child camera renderers)
  (define child-pict
    (visual->pict child camera #:renderers renderers))
  (define position
    (visual-position child))
  (define pixel-scale
    (camera-scale camera))
  (placed-child child-pict
                (* pixel-scale (vec2-x position))
                (* -1 pixel-scale (vec2-y position))))

; compose-placed-children : (non-empty-listof placed-child?) -> pict?
;;   Layers children in significant back-to-front order around the group anchor.
(define (compose-placed-children children)
  (define-values (half-width half-height)
    (placed-children-half-extents children))
  (for/fold ([composite (blank (* 2 half-width)
                              (* 2 half-height))])
            ([child (in-list children)])
    (define child-pict
      (placed-child-pict child))
    (pin-over composite
              (+ half-width
                 (placed-child-center-x child)
                 (- (/ (pict-width child-pict) 2)))
              (+ half-height
                 (placed-child-center-y child)
                 (- (/ (pict-height child-pict) 2)))
              child-pict)))

; placed-children-half-extents : (non-empty-listof placed-child?)
;                                 -> (values positive-real? positive-real?)
;;   Returns symmetric group extents around the local anchor.
(define (placed-children-half-extents children)
  (for/fold ([half-width 1/2]
             [half-height 1/2])
            ([child (in-list children)])
    (define child-pict
      (placed-child-pict child))
    (define child-half-width
      (/ (pict-width child-pict) 2))
    (define child-half-height
      (/ (pict-height child-pict) 2))
    (values
     (max half-width
          (abs (- (placed-child-center-x child)
                  child-half-width))
          (abs (+ (placed-child-center-x child)
                  child-half-width)))
     (max half-height
          (abs (- (placed-child-center-y child)
                  child-half-height))
          (abs (+ (placed-child-center-y child)
                  child-half-height))))))


;;;
;;; Semantic path clipping
;;;

;; `clip-visual` remains entirely vector based. Its content is rendered through
;; the normal dispatcher, but the Pict drawing context is restricted by a
;; region made from the semantic clip path. This keeps formula/SVG/shape
;; content crisp and allows the wrapper to participate in ordinary affine and
;; opacity animations without pre-rasterising it.

(define (clipped-visual->pict visual camera renderers)
  (define content (clipped-visual-content visual))
  (when (frame-space-visual? content)
    (raise-arguments-error
     'visual->pict
     "a world-space Visual inside clip-to/mask-with"
     "visual-id" (visual-id visual)))
  (define resolved-content
    (resolve-clipped-content content (visual-transform visual)))
  (define content-pict
    (visual->pict resolved-content camera #:renderers renderers))
  (define pixel-clip
    (clip-path->pixel-geometry (clipped-visual-path visual)
                               (visual-transform visual)
                               camera))
  (cond [(path-geometry-empty? pixel-clip) (blank 1 1)]
        [else
         (define-values (minimum-x minimum-y maximum-x maximum-y)
           (path-geometry-bounds pixel-clip))
         (define pixel-scale (camera-scale camera))
         (define content-position (visual-position resolved-content))
         (define content-x (* pixel-scale (vec2-x content-position)))
         (define content-y (* -1 pixel-scale (vec2-y content-position)))
         (define half-width
           (max 1/2
                (abs minimum-x) (abs maximum-x)
                (abs (- content-x (/ (pict-width content-pict) 2)))
                (abs (+ content-x (/ (pict-width content-pict) 2)))))
         (define half-height
           (max 1/2
                (abs minimum-y) (abs maximum-y)
                (abs (- content-y (/ (pict-height content-pict) 2)))
                (abs (+ content-y (/ (pict-height content-pict) 2)))))
         (dc
          (lambda (drawing-context x y)
            (define old-region (send drawing-context get-clipping-region))
            (define clip-region (new region% [dc drawing-context]))
            (send clip-region set-path (path-geometry->dc-path pixel-clip)
                  (+ x half-width) (+ y half-height) 'odd-even)
            (when old-region (send clip-region intersect old-region))
            (dynamic-wind
              (lambda () (send drawing-context set-clipping-region clip-region))
              (lambda ()
                (draw-pict content-pict drawing-context
                           (+ x half-width content-x
                              (- (/ (pict-width content-pict) 2)))
                           (+ y half-height content-y
                              (- (/ (pict-height content-pict) 2)))))
              (lambda () (send drawing-context set-clipping-region old-region))))
          (* 2 half-width)
          (* 2 half-height))]))

(define (resolve-clipped-content content parent-transform)
  (define content-transform (visual-transform content))
  (visual-with-transform
   content
   (make-affine-transform
    #:translation
    (affine-transform-apply-vector
     parent-transform (affine-transform-translation content-transform))
    #:rotation
    (+ (affine-transform-rotation parent-transform)
       (affine-transform-rotation content-transform))
    #:scale
    (vec2* (affine-transform-scale parent-transform)
           (affine-transform-scale content-transform)))))

(define (clip-path->pixel-geometry path transform camera)
  (define pixel-scale (camera-scale camera))
  (path-geometry-map-points
   path
   (lambda (point)
     (define transformed (affine-transform-apply-vector transform point))
     (vec2 (* pixel-scale (vec2-x transformed))
           (* -1 pixel-scale (vec2-y transformed))))))

(define (path-geometry->dc-path geometry)
  (define drawing-path (new dc-path%))
  (for ([subpath (in-list (path-geometry-subpaths geometry))])
    (define start (path-subpath-start subpath))
    (send drawing-path move-to (vec2-x start) (vec2-y start))
    (for ([segment (in-list (path-subpath-segments subpath))])
      (cond [(line-path-segment? segment)
             (define end (line-path-segment-end segment))
             (send drawing-path line-to (vec2-x end) (vec2-y end))]
            [(cubic-bezier-path-segment? segment)
             (define control1 (cubic-bezier-path-segment-control1 segment))
             (define control2 (cubic-bezier-path-segment-control2 segment))
             (define end (cubic-bezier-path-segment-end segment))
             (send drawing-path curve-to
                   (vec2-x control1) (vec2-y control1)
                   (vec2-x control2) (vec2-y control2)
                   (vec2-x end) (vec2-y end))]))
    (when (path-subpath-closed? subpath)
      (send drawing-path close)))
  drawing-path)


;;;
;;; Scene-State Conversion
;;;

; scene-state->pict : scene-state?
;                     [#:camera camera?]
;                     [#:renderers (listof pict-renderer?)]
;                     -> pict?
;;   Converts state to a fixed-size pict in drawing order.
(define (scene-state->pict state
                           #:camera [camera default-camera]
                           #:renderers [renderers default-pict-renderers])
  (unless (scene-state? state)
    (raise-argument-error 'scene-state->pict "scene-state?" state))
  (unless (camera? camera)
    (raise-argument-error 'scene-state->pict "camera?" camera))
  (check-pict-renderer-list 'scene-state->pict renderers)
  (define background
    (filled-rectangle (camera-width camera)
                      (camera-height camera)
                      #:draw-border? #f
                      #:color (camera-background camera)))
  (define layout-cache (make-hash))
  (define active-layout-paths (box '()))
  (for/fold ([frame background])
            ([visual
              (in-list
               (scene-state-resolved-visuals-in-drawing-order state))])
    (define resolved-for-layout
      (resolve-layout-relations-in-visual
       state visual (list (visual-id visual)) camera renderers layout-cache
       active-layout-paths))
    (place-scene-visual-on-pict frame state resolved-for-layout camera renderers)))

;; resolve-layout-relations-in-visual : scene-state? visual? visual-path? ...
;;                                      -> visual?
;; Scene-state resolves only semantic relations. This adapter-local traversal
;; resolves layout relations after camera and renderer selection, while keeping
;; the immutable sampled scene completely unchanged.
(define (resolve-layout-relations-in-visual state visual path camera renderers
                                            cache active-paths)
  (cond
    [(projected-label? visual)
     (resolve-projected-label-in-state state visual path camera cache)]
    [(layout-relation-visual? visual)
     (resolve-layout-relation
      state visual path camera renderers cache active-paths)]
    [(group-visual? visual)
     (group-visual-with-children
      visual
      (for/list ([child (in-list (group-visual-children visual))])
        (resolve-layout-relations-in-visual
         state child (append path (list (visual-id child))) camera renderers
         cache active-paths)))]
    [(affine-map-visual? visual)
     (affine-map-visual-with-content
      visual
      (resolve-layout-relations-in-visual
       state (affine-map-visual-content visual) path camera renderers cache
       active-paths))]
    [else visual]))

;; A projected label crosses the view3d-to-2D boundary after semantic spatial
;; relation resolution but before normal renderer-aware layout.  Its concrete
;; formula/text Visual is then painted through the ordinary Pict renderer and
;; stays crisp at every 3D camera distance.
(define (resolve-projected-label-in-state state label path camera cache)
  (define key (cons 'projected-label path))
  (cond [(hash-has-key? cache key) (hash-ref cache key)]
        [else
         (define view
           (scene-state-resolved-ref state (projected-label-view label)))
         (unless (view3d? view)
           (raise-arguments-error
            'scene-state->pict
            "a #:view identity resolving to view3d"
            "projected-label-id" (visual-id label)
            "view-id" (projected-label-view label)
            "resolved-visual" view))
         (define resolved (resolve-projected-label label view camera))
         (hash-set! cache key resolved)
         resolved]))

;; A deferred relation create/uncreate remains a relation definition for
;; dependency and renderer-layout purposes.  It differs only in the final
;; concrete path prefix that is displayed after resolution.
(define (layout-relation-visual? visual)
  (and (or (relation-visual? visual)
           (relation-path-reveal-visual? visual))
       (eq? (resolvable-visual-phase visual) 'layout)))

(define (layout-relation-base visual)
  (if (relation-path-reveal-visual? visual)
      (relation-path-reveal-visual-relation visual)
      visual))

(define (resolve-layout-relation state relation path camera renderers cache
                                 active-paths)
  (define base-relation (layout-relation-base relation))
  (unless (equal? path (list (visual-id relation)))
    (raise-arguments-error
     'scene-state->pict
     "a top-level layout relation in this initial renderer-aware phase"
     "relation path" path
     "relation space" (relation-visual-space base-relation)))
  (cond
    [(hash-has-key? cache path) (hash-ref cache path)]
    [(member path (unbox active-paths))
     (raise-arguments-error
      'scene-state->pict
      "an acyclic renderer-layout relation graph"
      "relation dependency cycle"
      (append (member path (unbox active-paths)) (list path)))]
    [else
     (set-box! active-paths (append (unbox active-paths) (list path)))
     (define base-context
       (make-derived-context
        (lambda (id) (scene-state-value-has? state id))
        (lambda (id) (scene-state-value-ref state id))
        (lambda (target) (scene-state-has? state target))
        (lambda (target)
          (layout-target-world-ref
           state target camera renderers cache active-paths))))
     (define (anchor-ref target anchor)
       (callout-target-layout-anchor
        (layout-target-world-ref
         state target camera renderers cache active-paths)
        anchor camera renderers))
     (define (selection-box-ref selection)
       (selection-layout-box
        state selection camera renderers cache active-paths))
     (define (layout-box-ref visual)
       (concrete-visual-layout-box visual camera renderers))
     (define concrete
       (if (relation-path-reveal-visual? relation)
           (resolve-relation-path-reveal-visual
           relation base-context
           #:anchor-ref anchor-ref
            #:layout-box-ref layout-box-ref
            #:selection-box-ref selection-box-ref)
           (resolve-relation-visual
            relation base-context
            #:anchor-ref anchor-ref
            #:layout-box-ref layout-box-ref
            #:selection-box-ref selection-box-ref)))
     (define nested-resolved
       (resolve-layout-relations-in-visual
        state concrete path camera renderers cache active-paths))
     (set-box! active-paths (drop-right (unbox active-paths) 1))
     (hash-set! cache path nested-resolved)
     nested-resolved]))

;; Resolves a semantic target in world coordinates, except for a top-level
;; layout relation which is recursively resolved against this camera/renderer
;; combination. This is intentionally on-demand and memoized in `cache`.
(define (layout-target-world-ref state target camera renderers cache active-paths)
  (define path (visual-target-path target 'scene-state->pict))
  (define stored
    (scene-state-ref state path))
  (cond
    [(layout-relation-visual? stored)
     (unless (equal? path (list (visual-id stored)))
       (raise-arguments-error
        'scene-state->pict
        "a top-level layout relation target in this initial renderer-aware phase"
        "target path" path))
     (resolve-layout-relation
      state stored path camera renderers cache active-paths)]
    [else
     (scene-state-resolved-world-ref state path)]))

;; selection-layout-box : scene-state? visual-selection? ... -> layout-box?
;; Measures each selected concrete leaf in the same current world camera and
;; returns their aggregate bounds. Selection paths remain semantic; no fake
;; group Visual is introduced solely for measurement.
(define (selection-layout-box state selection camera renderers cache active-paths)
  (define paths (visual-selection-absolute-paths selection))
  (unless (pair? paths)
    (raise-arguments-error
     'scene-state->pict
     "a nonempty visual selection for renderer layout"
     "selection" selection))
  (for/fold ([combined #f]) ([path (in-list paths)])
    (define visual
      (layout-target-world-ref state path camera renderers cache active-paths))
    (define box (concrete-visual-layout-box visual camera renderers))
    (if combined
        (layout-box
         (min (layout-box-left combined) (layout-box-left box))
         (min (layout-box-bottom combined) (layout-box-bottom box))
         (max (layout-box-right combined) (layout-box-right box))
         (max (layout-box-top combined) (layout-box-top box)))
        box)))

(define (concrete-visual-layout-box visual camera renderers)
  (define left
    (vec2-x (callout-target-layout-anchor visual 'left camera renderers)))
  (define bottom
    (vec2-y (callout-target-layout-anchor visual 'bottom camera renderers)))
  (define right
    (vec2-x (callout-target-layout-anchor visual 'right camera renderers)))
  (define top
    (vec2-y (callout-target-layout-anchor visual 'top camera renderers)))
  (layout-box left bottom right top))

; place-scene-visual-on-pict : pict? scene-state? visual? camera?
;                              (listof pict-renderer?) -> pict?
;;   Places one world-space Visual, frame overlay, or hybrid callout on frame.
(define (place-scene-visual-on-pict frame state visual camera renderers)
  (cond
    [(callout-visual? visual)
     (place-callout-on-pict frame state visual camera renderers)]
    [(camera-view-visual? visual)
     (place-camera-view-on-pict frame state visual camera renderers)]
    [(frame-space-visual? visual)
     (place-frame-space-visual-on-pict frame visual camera renderers)]
    [else
     (place-world-visual-on-pict frame visual camera renderers)]))

; place-camera-view-on-pict : pict? scene-state? camera-view-visual? camera?
;                             (listof pict-renderer?) -> pict?
;;   Resolves the inset target in the sampled world state, paints it into a
;;   complete second-camera canvas, and pins that canvas in the outer frame.
;;   The inset's own local transform and opacity then work exactly as for other
;;   frame-space Visuals; its target remains a normal world-space Visual.
(define (place-camera-view-on-pict canvas state view outer-camera renderers)
  (define targets
    (camera-view-resolved-targets state view))
  (define inset-camera
    (camera-view-visual-camera view))
  (define inset-background
    (filled-rectangle (camera-width inset-camera)
                      (camera-height inset-camera)
                      #:draw-border? #f
                      #:color (camera-background inset-camera)))
  ;; `pin-over` preserves the background extent but does not itself establish
  ;; a drawing clip.  A view is a viewport, so discard the portions of a large
  ;; target that lie outside the inset camera canvas before scaling it.
  (define inset-pict
   (clip
     (for/fold ([inset inset-background])
               ([target (in-list targets)])
       (place-world-visual-on-pict inset target inset-camera renderers))))
  (define desired-width
    (camera-length->pixels
     outer-camera
     (camera-view-visual-width view)))
  (define scaled-inset
    (scale inset-pict
           (/ desired-width
              (pict-width inset-pict))))
  (define framed-inset
    (case (camera-view-visual-clip view)
      [(rounded) (rounded-inset-pict scaled-inset)]
      [else
       ;; A one-pixel frame makes the second coordinate system legible without
       ;; inventing a separate decoration API for the basic rectangular view.
       (frame scaled-inset)]))
  (define transformed-inset
    (rotate-pict-if-needed
     (scale-pict-if-needed framed-inset (visual-scale view))
     (visual-rotation view)))
  (define rendered-inset
    (if (= (visual-opacity view) 1)
        transformed-inset
        (cellophane transformed-inset (visual-opacity view))))
  (define frame-camera
    (frame-space-camera
     outer-camera
     (frame-space-visual-frame-width view)))
  (define-values (center-x center-y)
    (camera-world->pixel frame-camera (visual-position view)))
  (pin-centered-pict canvas center-x center-y rendered-inset))

;; Resolves either the explicitly selected world-space layers, in declaration
;; order, or every ordinary top-level world-space layer. A camera view must
;; never recursively paint itself or another frame-space overlay into its inset.
(define (camera-view-resolved-targets state view)
  (define declared (camera-view-visual-targets view))
  (define candidates
    (if declared
        (for/list ([target (in-list declared)])
          (scene-state-resolved-world-ref state target))
        (filter (lambda (visual) (not (frame-space-visual? visual)))
                (scene-state-resolved-visuals-in-drawing-order state))))
  (for ([target (in-list candidates)])
    (when (frame-space-visual? target)
      (raise-arguments-error
       'scene-state->pict
       "a camera-view target must resolve to a world-space Visual"
       "camera-view-id" (visual-id view)
       "targets" declared)))
  candidates)

;; A rounded clip is deliberately part of the viewport decoration, not a
;; bitmap mask. It is applied directly to the dc that draws the scaled inset,
;; preserving the vector content inside it.
(define (rounded-inset-pict inset)
  (define width (pict-width inset))
  (define height (pict-height inset))
  (define radius (min (/ width 8) (/ height 8)))
  (dc
   (lambda (drawing-context x y)
     (define old-region (send drawing-context get-clipping-region))
     (define old-pen (send drawing-context get-pen))
     (define old-brush (send drawing-context get-brush))
     (define rounded-path (rounded-rectangle-dc-path width height radius))
     (define clip-region (new region% [dc drawing-context]))
     (send clip-region set-path rounded-path x y 'odd-even)
     (when old-region (send clip-region intersect old-region))
     (dynamic-wind
       (lambda () (send drawing-context set-clipping-region clip-region))
       (lambda () (draw-pict inset drawing-context x y))
       (lambda () (send drawing-context set-clipping-region old-region)))
     (send drawing-context set-pen (make-pen #:color "black" #:width 1))
     (send drawing-context set-brush (make-brush #:color "black" #:style 'transparent))
     (send drawing-context draw-path rounded-path x y)
     (send drawing-context set-pen old-pen)
     (send drawing-context set-brush old-brush))
   width height))

(define (rounded-rectangle-dc-path width height radius)
  (define handle (* radius 0.5522847498307936))
  (define path (new dc-path%))
  (send path move-to radius 0)
  (send path line-to (- width radius) 0)
  (send path curve-to (+ (- width radius) handle) 0
        width (- radius handle) width radius)
  (send path line-to width (- height radius))
  (send path curve-to width (+ (- height radius) handle)
        (+ (- width radius) handle) height (- width radius) height)
  (send path line-to radius height)
  (send path curve-to (- radius handle) height
        0 (+ (- height radius) handle) 0 (- height radius))
  (send path line-to 0 radius)
  (send path curve-to 0 (- radius handle) (- radius handle) 0 radius 0)
  (send path close)
  path)

; place-world-visual-on-pict : pict? visual? camera? (listof pict-renderer?)
;                              -> pict?
;;   Places a world-space Visual at its camera-space reference position.
(define (place-world-visual-on-pict frame visual camera renderers)
  (define visual-pict
    (visual->pict visual camera #:renderers renderers))
  (define-values (center-x center-y)
    (camera-world->pixel camera (visual-position visual)))
  (pin-centered-pict frame center-x center-y visual-pict))

; place-frame-space-visual-on-pict : pict? frame-space-visual? camera?
;                                    (listof pict-renderer?) -> pict?
;;   Places a fixed overlay using its camera-independent frame coordinates.
(define (place-frame-space-visual-on-pict frame visual camera renderers)
  (define frame-camera
    (frame-space-camera
     camera
     (frame-space-visual-frame-width visual)))
  (define visual-pict
    (visual->pict visual camera #:renderers renderers))
  (define-values (center-x center-y)
    (camera-world->pixel frame-camera
                         (visual-position visual)))
  (pin-centered-pict frame center-x center-y visual-pict))

; place-callout-on-pict : pict? scene-state? callout-visual? camera?
;                         (listof pict-renderer?) -> pict?
;;   Draws a world-to-frame connector and then the fixed annotation content.
(define (place-callout-on-pict frame state callout camera renderers)
  (define frame-camera
    (frame-space-camera
     camera
     (frame-space-visual-frame-width callout)))
  (define annotation-pict
    (visual->pict callout camera #:renderers renderers))
  (define-values (annotation-x annotation-y)
    (camera-world->pixel frame-camera
                         (visual-position callout)))
  (define target-point
    (callout-target-world-point state callout camera renderers))
  (define-values (target-x target-y)
    (camera-world->pixel camera target-point))
  (define frame-with-connector
    (place-callout-connector-on-pict
     frame
     callout
     annotation-pict
     annotation-x
     annotation-y
     target-x
     target-y))
  (pin-centered-pict frame-with-connector
                     annotation-x
                     annotation-y
                     annotation-pict))

; pin-centered-pict : pict? real? real? pict? -> pict?
;;   Places source so its Pict center lies at the supplied pixel coordinate.
(define (pin-centered-pict frame center-x center-y source)
  (pin-over frame
            (- center-x (/ (pict-width source) 2))
            (- center-y (/ (pict-height source) 2))
            source))


;;;
;;; Callout Connectors
;;;

; callout-target-world-point : scene-state? callout-visual? camera?
;                              (listof pict-renderer?) -> vec2?
;;   Resolves one callout target against the sampled world state.
(define (callout-target-world-point state callout camera renderers)
  (target-layout-world-point
   state
   (callout-visual-target callout)
   (callout-visual-target-anchor callout)
   camera
   renderers
   'scene-state->pict
   (visual-id callout)))

; target-layout-world-point : scene-state? (or/c vec2? visual-path?) symbol?
;                             camera? (listof pict-renderer?) symbol? symbol?
;                             -> vec2?
;; Resolves a literal world point or a live rendered-box anchor of a world-space
;; Visual.  Both callout leaders and SCENE-CM layout attachments use exactly this
;; operation so their anchor vocabulary and camera scaling cannot drift apart.
(define (target-layout-world-point state target anchor camera renderers who owner-id
                                   [active-layout-ids '()])
  (cond
    [(vec2? target)
     (unless (eq? anchor 'center)
       (raise-arguments-error
        who
        "the center anchor for a literal target point"
        "owner-id" owner-id
        "target" target
        "anchor" anchor))
     target]
    [else
     (define target-visual
       (checked-layout-target state target who owner-id active-layout-ids
                              camera renderers))
     (callout-target-layout-anchor target-visual anchor camera renderers)]))

; checked-layout-target : scene-state? visual-path? symbol? symbol?
;                         (listof symbol?) camera? (listof pict-renderer?)
;                         -> visual?
;; Resolves one independently drawable world-space target used by live layout
;; relationships. Layout attachments may be targets when their dependency graph
;; is acyclic; other renderer-aware definitions remain invalid targets.
(define (checked-layout-target state target who owner-id active-layout-ids
                               camera renderers)
  (define target-visual
    ;; Resolve directly instead of checking raw scene-state membership first:
    ;; a top-level derived group may expose its child paths only after sampled
    ;; resolution has constructed the current concrete group.
    (with-handlers
        ([exn:fail?
          (lambda (_exception)
            (raise-arguments-error
             who
             "a target present at its Visual path"
             "owner-id" owner-id
             "target-path" target))])
      (scene-state-resolved-world-ref state target)))
  (when (frame-space-visual? target-visual)
    (raise-arguments-error
     who
     "a target in world space, not frame space"
     "owner-id" owner-id
     "target-path" target))
  (define position
    (visual-position target-visual))
  (unless (vec2? position)
    (raise-arguments-error
     who
     "a world-space target that returns a vec2 position"
     "owner-id" owner-id
     "target-path" target
     "visual-position" position))
  target-visual)

; callout-target-layout-anchor : visual? symbol? camera?
;                                (listof pict-renderer?) -> vec2?
;; Uses the target's current rendered extent, rather than a constructor-time
;; snapshot, so leaders can remain attached to an animated edge or corner.
(define (callout-target-layout-anchor visual anchor camera renderers)
  (define center
    (visual-position visual))
  (if (eq? anchor 'center)
      center
      (let* ([rendered (visual->pict visual camera #:renderers renderers)]
             [scale (camera-scale camera)]
             [half-width (/ (pict-width rendered) scale 2)]
             [half-height (/ (pict-height rendered) scale 2)]
             [left (- (vec2-x center) half-width)]
             [right (+ (vec2-x center) half-width)]
             [bottom (- (vec2-y center) half-height)]
             [top (+ (vec2-y center) half-height)])
        (case anchor
          [(bottom-left) (vec2 left bottom)]
          [(bottom) (vec2 (vec2-x center) bottom)]
          [(bottom-right) (vec2 right bottom)]
          [(left) (vec2 left (vec2-y center))]
          [(right) (vec2 right (vec2-y center))]
          [(top-left) (vec2 left top)]
          [(top) (vec2 (vec2-x center) top)]
          [(top-right) (vec2 right top)]
          [else
           (raise-argument-error
            'callout-target-layout-anchor
            "supported layout anchor"
            anchor)]))))

; place-callout-connector-on-pict : pict? callout-visual? pict?
;                                   real? real? real? real? -> pict?
;;   Places the callout's leader line beneath its annotation content.
(define (place-callout-connector-on-pict frame
                                         callout
                                         annotation-pict
                                         annotation-x
                                         annotation-y
                                         target-x
                                         target-y)
  (define stroke
    (callout-visual-connector-stroke callout))
  (define width
    (callout-visual-connector-width callout))
  (cond
    [(or (not stroke)
         (zero? width))
     frame]
    [else
     (define-values (connector-x connector-y)
       (annotation-edge-toward-target
        annotation-x
        annotation-y
        (pict-width annotation-pict)
        (pict-height annotation-pict)
        target-x
        target-y))
     (define connector
       (callout-connector-pict
        (pict-width frame)
        (pict-height frame)
        connector-x
        connector-y
        target-x
        target-y
        stroke
        width))
     (define opacity
       (visual-opacity callout))
     (pin-over frame
               0
               0
               (if (= opacity 1)
                   connector
                   (cellophane connector opacity)))]))

; annotation-edge-toward-target : real? real? nonnegative-real? nonnegative-real?
;                                  real? real? -> (values real? real?)
;;   Returns the annotation-box edge point lying toward the connector target.
(define (annotation-edge-toward-target center-x
                                       center-y
                                       width
                                       height
                                       target-x
                                       target-y)
  (define dx
    (- target-x center-x))
  (define dy
    (- target-y center-y))
  (define half-width
    (/ width 2))
  (define half-height
    (/ height 2))
  (define inside?
    (and (<= (abs dx) half-width)
         (<= (abs dy) half-height)))
  (cond
    ;; A custom renderer may deliberately return a zero-width or zero-height
    ;; annotation Pict. In that degenerate case the semantic reference point is
    ;; the only stable connector attachment that avoids division by zero.
    [(or (zero? width)
         (zero? height))
     (values center-x center-y)]
    [(or inside?
         (and (zero? dx)
              (zero? dy)))
     (values target-x target-y)]
    [else
     (define ratio
       (max (/ (abs dx) half-width)
            (/ (abs dy) half-height)))
     (values (+ center-x (/ dx ratio))
             (+ center-y (/ dy ratio)))]))

; callout-connector-pict : positive-real? positive-real?
;                          real? real? real? real? any/c nonnegative-real?
;                          -> pict?
;;   Creates one transparent full-frame Pict containing a leader line.
(define (callout-connector-pict frame-width
                                frame-height
                                from-x
                                from-y
                                to-x
                                to-y
                                stroke
                                width)
  (dc (lambda (drawing-context x y)
        (define old-pen
          (send drawing-context get-pen))
        (dynamic-wind
          void
          (lambda ()
            (send drawing-context
                  set-pen
                  (make-pen #:color stroke
                            #:width width
                            #:style 'solid
                            #:cap 'round
                            #:join 'round))
            (send drawing-context
                  draw-line
                  (+ x from-x)
                  (+ y from-y)
                  (+ x to-x)
                  (+ y to-y)))
          (lambda ()
            (send drawing-context set-pen old-pen))))
      frame-width
      frame-height))
