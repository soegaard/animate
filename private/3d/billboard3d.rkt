#lang racket/base

;;;
;;; Immutable Textured Billboards
;;;

;; A billboard is a small alpha image anchored in the spatial tree.  It is not
;; an ordinary projected label: it takes part in the viewport depth test and is
;; therefore useful for symbols, sprites, and image annotations that belong in
;; a three-dimensional construction.  The payload is straight ARGB bytes so it
;; can cross render workers without a GUI bitmap or a renderer-owned resource.

(require "../geometry.rkt"
         "bounds3.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide billboard-image3d
         billboard-image3d?
         billboard-image3d-width
         billboard-image3d-height
         billboard-image3d-argb
         billboard-style3d
         billboard-style3d?
         billboard-style3d-width
         billboard-style3d-height
         billboard-style3d-size-mode
         billboard-style3d-facing
         billboard-style3d-axis
         billboard-style3d-opacity
         billboard-style3d-depth-mode
         billboard-style3d-depth-bias
         billboard3d
         billboard3d?
         billboard3d-image
         billboard3d-position
         billboard3d-style)

;; The source is deliberately data, rather than bitmap% or a pathname.  It
;; makes the authoring value serializable and removes backend-/eventspace-owned
;; bitmap state from a Scene.
(struct billboard-image3d-value (width height argb)
  #:transparent
  #:guard
  (lambda (width height argb who)
    (unless (exact-positive-integer? width)
      (raise-argument-error who "exact-positive-integer?" width))
    (unless (exact-positive-integer? height)
      (raise-argument-error who "exact-positive-integer?" height))
    (unless (and (bytes? argb) (= (bytes-length argb) (* 4 width height)))
      (raise-arguments-error who "straight ARGB bytes matching width and height"
                             "width" width "height" height "argb" argb))
    (values width height (bytes->immutable-bytes argb))))

(define billboard-image3d? billboard-image3d-value?)
(define billboard-image3d-width billboard-image3d-value-width)
(define billboard-image3d-height billboard-image3d-value-height)
(define billboard-image3d-argb billboard-image3d-value-argb)

(define (billboard-image3d width height argb)
  (billboard-image3d-value width height argb))

;; `width` and optional `height` are pixels in screen mode and world units in
;; world mode.  A missing height preserves the source image's aspect ratio.
;; `camera` makes the plane parallel to the image plane; `axis` keeps the given
;; axis upright while rotating only around it to face the camera.
(struct billboard-style3d-value
  (width height size-mode facing axis opacity depth-mode depth-bias)
  #:transparent)

(define billboard-style3d? billboard-style3d-value?)
(define billboard-style3d-width billboard-style3d-value-width)
(define billboard-style3d-height billboard-style3d-value-height)
(define billboard-style3d-size-mode billboard-style3d-value-size-mode)
(define billboard-style3d-facing billboard-style3d-value-facing)
(define billboard-style3d-axis billboard-style3d-value-axis)
(define billboard-style3d-opacity billboard-style3d-value-opacity)
(define billboard-style3d-depth-mode billboard-style3d-value-depth-mode)
(define billboard-style3d-depth-bias billboard-style3d-value-depth-bias)

(define (billboard-style3d #:width [width 32]
                           #:height [height #f]
                           #:size-mode [size-mode 'screen]
                           #:facing [facing 'camera]
                           #:axis [axis y-axis3]
                           #:opacity [opacity 1]
                           #:depth-mode [depth-mode 'test]
                           #:depth-bias [depth-bias 1e-5])
  (unless (and (finite-real? width) (positive? width))
    (raise-argument-error 'billboard-style3d "positive finite #:width" width))
  (unless (or (not height) (and (finite-real? height) (positive? height)))
    (raise-argument-error 'billboard-style3d "#f or positive finite #:height" height))
  (unless (memq size-mode '(screen world))
    (raise-argument-error 'billboard-style3d "'screen or 'world as #:size-mode" size-mode))
  (unless (memq facing '(camera axis))
    (raise-argument-error 'billboard-style3d "'camera or 'axis as #:facing" facing))
  (when (and (eq? facing 'axis) (eq? size-mode 'screen))
    (raise-arguments-error
     'billboard-style3d
     "axis-facing billboards with a world-space size"
     "size-mode" size-mode "facing" facing))
  (unless (and (vec3? axis) (positive? (vec3-length axis)))
    (raise-argument-error 'billboard-style3d "nonzero vec3? as #:axis" axis))
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error 'billboard-style3d "finite opacity in [0, 1]" opacity))
  (unless (memq depth-mode '(test always hidden))
    (raise-argument-error 'billboard-style3d "'test, 'always, or 'hidden as #:depth-mode" depth-mode))
  (unless (and (finite-real? depth-bias) (>= depth-bias 0))
    (raise-argument-error 'billboard-style3d "nonnegative finite #:depth-bias" depth-bias))
  (billboard-style3d-value width height size-mode facing (vec3-normalize axis)
                           opacity depth-mode depth-bias))

(struct billboard3d-value (id transform opacity image position style local-bounds)
  #:transparent
  #:methods gen:spatial-visual
  [(define (spatial-id value) (billboard3d-value-id value))
   (define (spatial-transform value) (billboard3d-value-transform value))
   (define (spatial-with-transform value transform)
     (unless (transform3? transform)
       (raise-argument-error 'spatial-with-transform "transform3?" transform))
     (struct-copy billboard3d-value value [transform transform]))
   (define (spatial-opacity value) (billboard3d-value-opacity value))
   (define (spatial-with-opacity value opacity)
     (unless (and (finite-real? opacity) (<= 0 opacity 1))
       (raise-argument-error 'spatial-with-opacity "finite opacity in [0, 1]" opacity))
     (struct-copy billboard3d-value value [opacity opacity]))
   ;; A screen-oriented image has no camera-independent volume.  Its anchor is
   ;; an honest local bound and is also the point used by spatial selection.
   (define (spatial-local-bounds value) (billboard3d-value-local-bounds value))])

(define billboard3d? billboard3d-value?)
(define billboard3d-image billboard3d-value-image)
(define billboard3d-position billboard3d-value-position)
(define billboard3d-style billboard3d-value-style)

(define (billboard3d image position #:id id
                     #:style [style (billboard-style3d)]
                     #:transform [transform identity-transform3]
                     #:opacity [opacity 1])
  (unless (billboard-image3d? image)
    (raise-argument-error 'billboard3d "billboard-image3d?" image))
  (unless (vec3? position)
    (raise-argument-error 'billboard3d "vec3?" position))
  (unless (symbol? id)
    (raise-argument-error 'billboard3d "symbol?" id))
  (unless (billboard-style3d? style)
    (raise-argument-error 'billboard3d "billboard-style3d?" style))
  (unless (transform3? transform)
    (raise-argument-error 'billboard3d "transform3?" transform))
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error 'billboard3d "finite opacity in [0, 1]" opacity))
  (billboard3d-value id transform opacity image position style
                      (aabb3-from-points (list position))))
