#lang racket/base

;;;
;;; Frame-Space Visuals
;;;

;; Defines semantic Visual wrappers whose reference positions use a camera-
;; independent frame coordinate system, plus hybrid callouts from frame-space
;; content to world-space targets.
;;
;; This module remains pure. It stores no Pict, bitmap, drawing-context, or
;; renderer values. A frame-space Visual snapshots only the visible width and
;; center relationship of the camera supplied when it is constructed.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "camera.rkt"
         "geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide frame-space-visual?
         frame-space-visual-frame-width
         frame-space-camera
         fixed-in-frame
         fixed-in-frame-visual?
         fixed-in-frame-visual-content
         camera-view
         camera-view-visual?
         camera-view-visual-target
         camera-view-visual-targets
         camera-view-visual-camera
         camera-view-visual-with-camera
         camera-view-visual-width
         camera-view-visual-clip
         callout
         callout-visual?
         callout-visual-content
         callout-visual-target
         callout-visual-target-anchor
         callout-visual-connector-stroke
         callout-visual-connector-width)


;;;
;;; Data Representation
;;;

(struct fixed-in-frame-visual (id transform opacity content frame-width)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual)
     (fixed-in-frame-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation
      (fixed-in-frame-visual-transform visual)))
   (define (visual-with-position visual position)
     (check-frame-position 'visual-with-position position)
     (struct-copy fixed-in-frame-visual visual
                  [transform
                   (affine-transform-with-translation
                    (fixed-in-frame-visual-transform visual)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (fixed-in-frame-visual-transform visual))
   (define (visual-with-transform visual transform)
     (check-frame-transform 'visual-with-transform transform)
     (struct-copy fixed-in-frame-visual visual
                  [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (fixed-in-frame-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (check-frame-opacity 'visual-with-opacity opacity)
     (struct-copy fixed-in-frame-visual visual
                  [opacity opacity]))])

;; fixed-in-frame-visual represents one camera-independent overlay Visual.
;;  - id           symbol?             stable top-level Visual identity.
;;  - transform    affine-transform?   extra transform in frame coordinates.
;;  - opacity      opacity?            opacity applied to the complete overlay.
;;  - content      visual?             semantic Visual rendered at local origin.
;;  - frame-width  positive real?      captured visible frame width in frame units.
;;
;; The content's own geometry, rotation, scale, and opacity remain significant.
;; Its containing-coordinate position is ignored during overlay rendering.

;; A camera-view is a frame-space viewport onto explicitly selected world-space
;; targets or every world-space top-level layer. Targets are looked up only
;; during scene rendering, which keeps the inset synchronized without a mutable
;; secondary Scene.
(struct camera-view-visual
  (id transform opacity target-values camera frame-width width clip)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual)
     (camera-view-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation
      (camera-view-visual-transform visual)))
   (define (visual-with-position visual position)
     (check-frame-position 'visual-with-position position)
     (struct-copy camera-view-visual visual
                  [transform
                   (affine-transform-with-translation
                    (camera-view-visual-transform visual)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (camera-view-visual-transform visual))
   (define (visual-with-transform visual transform)
     (check-frame-transform 'visual-with-transform transform)
     (struct-copy camera-view-visual visual [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (camera-view-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (check-frame-opacity 'visual-with-opacity opacity)
     (struct-copy camera-view-visual visual [opacity opacity]))])

;; camera-view-visual represents an orthographic view inset.
;;  - target-values (or/c false/c (listof (or/c symbol? visual-path?)))
;;                  #f means all world-space top-level layers at render time.
;;  - camera      camera?                 the inset's world-space view.
;;  - frame-width positive real?          captured outer frame width.
;;  - width       positive real?          inset width in captured frame units.
;;  - clip        (or/c 'rectangle 'rounded) frame shape for the inset canvas.

(struct callout-visual
  (id transform opacity content frame-width target target-anchor connector-stroke connector-width)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual)
     (callout-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation
      (callout-visual-transform visual)))
   (define (visual-with-position visual position)
     (check-frame-position 'visual-with-position position)
     (struct-copy callout-visual visual
                  [transform
                   (affine-transform-with-translation
                    (callout-visual-transform visual)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (callout-visual-transform visual))
   (define (visual-with-transform visual transform)
     (check-frame-transform 'visual-with-transform transform)
     (struct-copy callout-visual visual
                  [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (callout-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (check-frame-opacity 'visual-with-opacity opacity)
     (struct-copy callout-visual visual
                  [opacity opacity]))])

;; callout-visual represents one fixed annotation with a world-space leader.
;;  - id                symbol?             stable top-level Visual identity.
;;  - transform         affine-transform?   annotation transform in frame space.
;;  - opacity           opacity?            opacity of annotation and connector.
;;  - content           visual?             semantic annotation content.
;;  - frame-width       positive real?      captured frame-space visible width.
;;  - target            (or/c visual-path? vec2?) Visual path or world point.
;;  - target-anchor     layout-anchor?      live rendered target point.
;;  - connector-stroke  any/c               opaque connector style for adapter.
;;  - connector-width   nonnegative real?   cosmetic connector width in pixels.
;;
;; Visual paths are resolved against the sampled scene state. A vec2 target is
;; a fixed point in world coordinates.


;;;
;;; Construction
;;;

; fixed-in-frame : visual?
;                  [#:camera camera?]
;                  [#:at (or/c vec2? false/c)]
;                  [#:rotation finite-real?]
;                  [#:scale scale-factor?]
;                  [#:opacity opacity?]
;                  -> fixed-in-frame-visual?
;;   Wraps content in a frame-space Visual that ignores later camera pan/zoom.
(define (fixed-in-frame content
                        #:camera [camera default-camera]
                        #:at [position #f]
                        #:rotation [rotation 0]
                        #:scale [scale 1]
                        #:opacity [opacity 1])
  (check-frame-content 'fixed-in-frame content)
  (check-frame-camera 'fixed-in-frame camera)
  (check-optional-frame-position 'fixed-in-frame position)
  (check-frame-rotation 'fixed-in-frame rotation)
  (check-frame-scale 'fixed-in-frame scale)
  (check-frame-opacity 'fixed-in-frame opacity)
  (define id
    (visual-target-id content 'fixed-in-frame))
  (define frame-position
    (or position
        (vec2- (checked-content-position 'fixed-in-frame content)
               (camera-center camera))))
  (fixed-in-frame-visual
   id
   (make-affine-transform #:translation frame-position
                          #:rotation rotation
                          #:scale scale)
   opacity
   content
   (camera-world-width camera)))

;; camera-view : [(or/c false/c visual? symbol? visual-path?)] #:id symbol?
;;               [#:targets (or/c false/c (listof (or/c visual? symbol? visual-path?)))]
;;               [#:camera camera?] [#:frame-camera camera?]
;;               [#:at vec2?] [#:width positive-finite-real?]
;;               [#:clip (or/c 'rectangle 'rounded 'rounded-frame)]
;;               [#:opacity opacity?] -> camera-view-visual?
;; Creates a fixed-position inset that renders selected live world-space targets
;; with its own orthographic camera. Omit both target arguments for every
;; world-space top-level layer. `frame-camera` supplies the stable frame
;; coordinate system used by `at` and `width`; it defaults to default-camera.
(define (camera-view [target #f]
                     #:id id
                     #:camera camera
                     #:targets [targets #f]
                     #:frame-camera [frame-camera default-camera]
                     #:at [position origin]
                     #:width [width 3]
                     #:clip [clip 'rectangle]
                     #:opacity [opacity 1])
  (check-camera-view-target-selection 'camera-view target targets)
  (unless (symbol? id)
    (raise-argument-error 'camera-view "symbol?" id))
  (check-frame-camera 'camera-view camera)
  (check-frame-camera 'camera-view frame-camera)
  (check-frame-position 'camera-view position)
  (check-positive-frame-length 'camera-view "width" width)
  (check-camera-view-clip 'camera-view clip)
  (check-frame-opacity 'camera-view opacity)
  (camera-view-visual
   id
   (make-affine-transform #:translation position)
   opacity
   (normalize-camera-view-target-selection target targets)
   camera
   (camera-world-width frame-camera)
   width
   (normalize-camera-view-clip clip)))

; callout : visual? (or/c visual? symbol? visual-path? vec2?)
;           [#:camera camera?]
;           [#:at (or/c vec2? false/c)]
;           [#:rotation finite-real?]
;           [#:scale scale-factor?]
;           [#:opacity opacity?]
;           [#:target-anchor layout-anchor?]
;           [#:connector-stroke any/c]
;           [#:connector-width nonnegative-real?]
;           -> callout-visual?
;;   Creates a fixed annotation whose connector points to a world-space target.
(define (callout content
                 target
                 #:camera [camera default-camera]
                 #:at [position #f]
                 #:rotation [rotation 0]
                 #:scale [scale 1]
                 #:opacity [opacity 1]
                 #:target-anchor [target-anchor 'center]
                 #:connector-stroke [connector-stroke "black"]
                 #:connector-width [connector-width 2])
  (check-frame-content 'callout content)
  (check-callout-target 'callout target)
  (check-frame-camera 'callout camera)
  (check-optional-frame-position 'callout position)
  (check-frame-rotation 'callout rotation)
  (check-frame-scale 'callout scale)
  (check-frame-opacity 'callout opacity)
  (check-callout-target-anchor 'callout target-anchor)
  (check-connector-width 'callout connector-width)
  (when (and (vec2? target)
             (not (eq? target-anchor 'center)))
    (raise-arguments-error
     'callout
     "a point target with the center anchor"
     "target" target
     "target-anchor" target-anchor))
  (define id
    (visual-target-id content 'callout))
  (define frame-position
    (or position
        (vec2- (checked-content-position 'callout content)
               (camera-center camera))))
  (callout-visual
   id
   (make-affine-transform #:translation frame-position
                          #:rotation rotation
                          #:scale scale)
   opacity
   content
   (camera-world-width camera)
   (normalize-callout-target target)
   target-anchor
   connector-stroke
   connector-width))


;;;
;;; Frame-Space Queries
;;;

; frame-space-visual? : any/c -> boolean?
;;   Reports whether value is a built-in fixed overlay or callout Visual.
(define (frame-space-visual? value)
  (or (fixed-in-frame-visual? value)
      (camera-view-visual? value)
      (callout-visual? value)))

; camera-view-visual-target : camera-view-visual? -> (or/c false/c symbol? visual-path?)
;;   Compatibility accessor for a one-target view. A multi-target or all-layer
;;   view has no singular target and returns #f; use camera-view-visual-targets.
(define (camera-view-visual-target visual)
  (unless (camera-view-visual? visual)
    (raise-argument-error 'camera-view-visual-target "camera-view-visual?" visual))
  (define targets (camera-view-visual-target-values visual))
  (and (pair? targets) (null? (cdr targets)) (car targets)))

; camera-view-visual-targets : camera-view-visual?
;;                              -> (or/c false/c (listof (or/c symbol? visual-path?)))
;;   Returns #f for an all-world-layers view, otherwise its declared target list.
(define (camera-view-visual-targets visual)
  (unless (camera-view-visual? visual)
    (raise-argument-error 'camera-view-visual-targets "camera-view-visual?" visual))
  (camera-view-visual-target-values visual))

; camera-view-visual-with-camera : camera-view-visual? camera?
;;                                  -> camera-view-visual?
;;   Replaces only the semantic inset camera, preserving identity and frame pose.
(define (camera-view-visual-with-camera visual camera)
  (unless (camera-view-visual? visual)
    (raise-argument-error 'camera-view-visual-with-camera
                          "camera-view-visual?" visual))
  (check-frame-camera 'camera-view-visual-with-camera camera)
  (struct-copy camera-view-visual visual [camera camera]))

; frame-space-visual-frame-width : frame-space-visual? -> positive-real?
;;   Returns the captured visible width of visual's frame coordinate system.
(define (frame-space-visual-frame-width visual)
  (cond
    [(fixed-in-frame-visual? visual)
     (fixed-in-frame-visual-frame-width visual)]
    [(camera-view-visual? visual)
     (camera-view-visual-frame-width visual)]
    [(callout-visual? visual)
     (callout-visual-frame-width visual)]
    [else
     (raise-argument-error
      'frame-space-visual-frame-width
      "frame-space-visual?"
      visual)]))

; frame-space-camera : camera? positive-real? -> camera?
;;   Creates the origin-centered camera used to render one frame-space Visual.
(define (frame-space-camera camera frame-width)
  (check-frame-camera 'frame-space-camera camera)
  (check-frame-width 'frame-space-camera frame-width)
  (make-camera #:width (camera-width camera)
               #:height (camera-height camera)
               #:world-width frame-width
               #:center origin
               #:background (camera-background camera)))


;;;
;;; Target Normalization
;;;

; normalize-callout-target : (or/c visual? symbol? visual-path? vec2?)
;                            -> (or/c symbol? visual-path? vec2?)
;;   Converts a Visual target to its stable path address.
(define (normalize-callout-target target)
  (if (vec2? target)
      target
      (visual-target-id target 'callout)))

(define (normalize-camera-view-target-selection target targets)
  (cond [targets
         (for/list ([candidate (in-list targets)])
           (visual-target-id candidate 'camera-view))]
        [target
         (list (visual-target-id target 'camera-view))]
        [else #f]))

(define (normalize-camera-view-clip clip)
  (if (eq? clip 'rounded-frame) 'rounded clip))


;;;
;;; Validation
;;;

; check-frame-content : symbol? any/c -> void?
;;   Raises an argument error unless content is an ordinary semantic Visual.
(define (check-frame-content who content)
  (unless (visual? content)
    (raise-argument-error who "visual?" content))
  (when (frame-space-visual? content)
    (raise-arguments-error
     who
     "frame-space Visuals cannot be nested inside another frame-space wrapper"
     "content" content))
  (visual-target-id content who)
  (checked-content-position who content)
  (void))

; checked-content-position : symbol? visual? -> vec2?
;;   Returns content's validated containing-coordinate reference position.
(define (checked-content-position who content)
  (define position
    (visual-position content))
  (unless (vec2? position)
    (raise-arguments-error
     who
     "visual-position must return a vec2"
     "content" content
     "visual-position" position))
  position)

; check-callout-target : symbol? any/c -> void?
;;   Raises an argument error unless target is a world point or Visual/path target.
(define (check-callout-target who target)
  (unless (or (vec2? target)
              (symbol? target)
              (visual-path? target)
              (visual? target))
    (raise-argument-error
     who
     "(or/c vec2? visual? symbol? visual-path?)"
     target))
  (when (and (visual? target)
             (frame-space-visual? target))
    (raise-arguments-error
     who
     "a callout target must belong to world space"
     "target" target))
  (unless (vec2? target)
    (visual-target-id target who))
  (void))

(define (check-camera-view-target-selection who target targets)
  (when (and target targets)
    (raise-arguments-error
     who
     "provide either the positional target or #:targets, not both"
     "target" target
     "targets" targets))
  (when targets
    (unless (and (list? targets) (pair? targets))
      (raise-arguments-error who "a nonempty list of world-space targets"
                             "targets" targets)))
  (for ([candidate (in-list (cond [targets targets]
                                  [target (list target)]
                                  [else '()]))])
    (unless (or (symbol? candidate)
                (visual-path? candidate)
                (visual? candidate))
      (raise-argument-error who "(or/c visual? symbol? visual-path?)" candidate))
    (when (and (visual? candidate)
               (frame-space-visual? candidate))
      (raise-arguments-error
       who
       "a camera-view target must belong to world space"
       "target" candidate))
    (visual-target-id candidate who))
  (void))

(define (check-camera-view-clip who clip)
  (unless (memq clip '(rectangle rounded rounded-frame))
    (raise-argument-error who
                          "(or/c 'rectangle 'rounded 'rounded-frame)"
                          clip)))

; check-callout-target-anchor : symbol? any/c -> void?
;;   Validates the one of nine live renderer-box locations that a callout
;;   connector may follow on a Visual target.
(define (check-callout-target-anchor who anchor)
  (unless (and (symbol? anchor)
               (memq anchor
                     '(bottom-left bottom bottom-right
                       left center right
                       top-left top top-right)))
    (raise-argument-error
     who
     "(or/c 'bottom-left 'bottom 'bottom-right 'left 'center 'right 'top-left 'top 'top-right)"
     anchor)))

; check-frame-camera : symbol? any/c -> void?
;;   Raises an argument error unless value is a camera.
(define (check-frame-camera who camera)
  (unless (camera? camera)
    (raise-argument-error who "camera?" camera)))

; check-frame-width : symbol? any/c -> void?
;;   Raises an argument error unless value is a positive finite real.
(define (check-frame-width who frame-width)
  (unless (and (finite-real? frame-width)
               (positive? frame-width))
    (raise-argument-error who "positive finite real?" frame-width)))

(define (check-positive-frame-length who field value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "positive finite real?" field value)))

; check-frame-position : symbol? any/c -> void?
;;   Raises an argument error unless value is a frame-space point.
(define (check-frame-position who position)
  (unless (vec2? position)
    (raise-argument-error who "vec2?" position)))

; check-optional-frame-position : symbol? any/c -> void?
;;   Raises an argument error unless value is false or a frame-space point.
(define (check-optional-frame-position who position)
  (unless (or (not position)
              (vec2? position))
    (raise-argument-error who "(or/c vec2? false/c)" position)))

; check-frame-transform : symbol? any/c -> void?
;;   Raises an argument error unless value is a complete affine transform.
(define (check-frame-transform who transform)
  (unless (affine-transform? transform)
    (raise-argument-error who "affine-transform?" transform)))

; check-frame-rotation : symbol? any/c -> void?
;;   Raises an argument error unless value is a finite rotation in radians.
(define (check-frame-rotation who rotation)
  (unless (finite-real? rotation)
    (raise-argument-error who "finite real?" rotation)))

; check-frame-scale : symbol? any/c -> void?
;;   Raises an argument error unless value is a valid positive scale factor.
(define (check-frame-scale who scale)
  (unless (scale-factor? scale)
    (raise-argument-error who "scale-factor?" scale)))

; check-frame-opacity : symbol? any/c -> void?
;;   Raises an argument error unless value is a semantic opacity.
(define (check-frame-opacity who opacity)
  (unless (opacity? opacity)
    (raise-argument-error who "opacity?" opacity)))

; check-connector-width : symbol? any/c -> void?
;;   Raises an argument error unless value is nonnegative and finite.
(define (check-connector-width who width)
  (unless (and (finite-real? width)
               (not (negative? width)))
    (raise-argument-error who "nonnegative finite real?" width)))
