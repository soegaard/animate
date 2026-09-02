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
         (only-in pict
                  blank
                  cellophane
                  dc
                  filled-rectangle
                  pict-height
                  pict-width
                  pin-over)
         (only-in racket/draw
                  make-pen)
         "anchored-pict.rkt"
         "camera.rkt"
         "derived-visual.rkt"
         "formula-parts-visual.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "number-line-visual.rkt"
         "pict-renderer.rkt"
         "point-marker-visual.rkt"
         "scene-state.rkt"
         "shape-pict-renderers.rkt"
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
  (when (derived-visual? visual)
    (raise-arguments-error
     'visual->pict
     "a derived Visual must be resolved against a scene state before rendering"
     "visual-id" (visual-id visual)))
  (cond
    [(transient-visual? visual)
     (render-visual-or-composite
      (transient-visual-underlying visual)
      camera
      renderers)]
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
  (for/fold ([frame background])
            ([visual
              (in-list
               (scene-state-resolved-visuals-in-drawing-order state))])
    (place-scene-visual-on-pict frame
                                state
                                visual
                                camera
                                renderers)))

; place-scene-visual-on-pict : pict? scene-state? visual? camera?
;                              (listof pict-renderer?) -> pict?
;;   Places one world-space Visual, frame overlay, or hybrid callout on frame.
(define (place-scene-visual-on-pict frame state visual camera renderers)
  (cond
    [(callout-visual? visual)
     (place-callout-on-pict frame state visual camera renderers)]
    [(frame-space-visual? visual)
     (place-frame-space-visual-on-pict frame visual camera renderers)]
    [else
     (place-world-visual-on-pict frame visual camera renderers)]))

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
    (callout-target-world-point state callout))
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

; callout-target-world-point : scene-state? callout-visual? -> vec2?
;;   Resolves one callout target against the sampled top-level world state.
(define (callout-target-world-point state callout)
  (define target
    (callout-visual-target callout))
  (cond
    [(vec2? target)
     target]
    [else
     (unless (scene-state-has? state target)
       (raise-arguments-error
        'scene-state->pict
        "a callout target is not present as a top-level Visual"
        "callout-id" (visual-id callout)
        "target-id" target))
     (define target-visual
       (scene-state-resolved-ref state target))
     (when (frame-space-visual? target-visual)
       (raise-arguments-error
        'scene-state->pict
        "a callout target must belong to world space"
        "callout-id" (visual-id callout)
        "target-id" target))
     (define position
       (visual-position target-visual))
     (unless (vec2? position)
       (raise-arguments-error
        'scene-state->pict
        "a callout target must return a world-space vec2 position"
        "callout-id" (visual-id callout)
        "target-id" target
        "visual-position" position))
     position]))

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
