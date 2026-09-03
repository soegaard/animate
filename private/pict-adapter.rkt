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
                  frame
                  filled-rectangle
                  pict-height
                  pict-width
                  pin-over
                  scale)
         (only-in racket/draw
                  make-pen)
         "affine-map-visual.rkt"
         "affine-pict.rkt"
         "anchored-pict.rkt"
         "annotation-geometry.rkt"
         "camera.rkt"
         "derived-visual.rkt"
         "dynamic-endpoint-geometry.rkt"
         "formula-parts-visual.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "layout-attachment.rkt"
         "number-line-visual.rkt"
         "pict-renderer.rkt"
         "point-marker-visual.rkt"
         "path-geometry.rkt"
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
    [(affine-map-visual? visual)
     (affine-map-content->pict visual camera renderers)]
    [(layout-attached-visual? visual)
     (raise-arguments-error
      'visual->pict
      "a layout-attached Visual placed as a top-level scene decoration"
      "visual-id" (visual-id visual))]
    [(dynamic-endpoint-visual? visual)
     (raise-arguments-error
      'visual->pict
      "dynamic endpoint geometry placed as a top-level scene decoration"
      "visual-id" (visual-id visual))]
    [(surrounding-rectangle-visual? visual)
     (raise-arguments-error
      'visual->pict
      "a surrounding rectangle placed as a top-level scene decoration"
      "visual-id" (visual-id visual))]
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
  (define mapped-pict
    (affine2-pict-transform
     (visual->pict content camera #:renderers renderers)
     (affine-map-visual-map visual)))
  (define transformed-pict
    (scale-pict-if-needed mapped-pict (visual-scale visual)))
  (rotate-pict-if-needed transformed-pict (visual-rotation visual)))

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
    [(camera-view-visual? visual)
     (place-camera-view-on-pict frame state visual camera renderers)]
    [(dynamic-endpoint-visual? visual)
     (place-dynamic-endpoint-visual-on-pict
      frame state visual camera renderers)]
    [(surrounding-rectangle-visual? visual)
     (place-surrounding-rectangle-on-pict
      frame state visual camera renderers)]
    [(layout-attached-visual? visual)
     (place-layout-attached-visual-on-pict
      frame state visual camera renderers)]
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
  (define target
    (scene-state-resolved-world-ref
     state
     (camera-view-visual-target view)))
  (when (frame-space-visual? target)
    (raise-arguments-error
     'scene-state->pict
     "a camera-view target must resolve to a world-space Visual"
     "camera-view-id" (visual-id view)
     "target" (camera-view-visual-target view)))
  (define inset-camera
    (camera-view-visual-camera view))
  (define inset-background
    (filled-rectangle (camera-width inset-camera)
                      (camera-height inset-camera)
                      #:draw-border? #f
                      #:color (camera-background inset-camera)))
  (define inset-pict
    (place-world-visual-on-pict inset-background
                                target
                                inset-camera
                                renderers))
  (define desired-width
    (camera-length->pixels
     outer-camera
     (camera-view-visual-width view)))
  (define scaled-inset
    (scale inset-pict
           (/ desired-width
              (pict-width inset-pict))))
  ;; A one-pixel frame makes the second coordinate system legible without
  ;; inventing a separate decoration API for the first version of camera-view.
  (define framed-inset
    (frame scaled-inset))
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

; place-dynamic-endpoint-visual-on-pict : pict? scene-state?
;                                         dynamic-endpoint-visual? camera?
;                                         (listof pict-renderer?) -> pict?
;; Resolves edge/corner anchors only after the target's sampled renderer extent
;; is known, then paints the ordinary concrete line or arrow in world space.
(define (place-dynamic-endpoint-visual-on-pict frame state definition camera renderers)
  (define concrete
    (dynamic-endpoint-visual-resolve-renderer
     definition
     (lambda (parameter)
       (define value (scene-state-value-ref state parameter))
       (unless (vec2? value)
         (raise-arguments-error
          'scene-state->pict
          "a point-valued endpoint parameter"
          "parameter" parameter
          "sampled-value" value))
       value)
     (lambda (target anchor offset)
       (vec2+
        (target-layout-world-point
         state target anchor camera renderers 'scene-state->pict
         (visual-id definition))
        offset))))
  (place-world-visual-on-pict frame concrete camera renderers))

; place-surrounding-rectangle-on-pict : pict? scene-state?
;                                       surrounding-rectangle-visual? camera?
;                                       (listof pict-renderer?) -> pict?
;; Measures one sampled target's complete Pict box, adds world-space padding,
;; and paints the resulting ordinary rectangle in the enclosing scene layer.
(define (place-surrounding-rectangle-on-pict frame state enclosure camera renderers)
  (define target
    (surrounding-rectangle-visual-target enclosure))
  (define target-visual
    (checked-layout-target
     state target 'scene-state->pict (visual-id enclosure) '() camera renderers))
  (define target-pict
    (visual->pict target-visual camera #:renderers renderers))
  (define scale (camera-scale camera))
  (define padding (surrounding-rectangle-visual-padding enclosure))
  (define template
    ;; The model constructor owns the styles and opacity; only the live measured
    ;; center and dimensions vary across samples.
    (surrounding-rectangle-template enclosure))
  (define width (+ (/ (pict-width target-pict) scale) (* 2 padding)))
  (define height (+ (/ (pict-height target-pict) scale) (* 2 padding)))
  ;; A path Visual gives #f its established transparent-fill meaning, while an
  ;; author-supplied fill remains available for a highlighted enclosure. The
  ;; rectangle primitive intentionally has its legacy opaque-fill treatment.
  (define half-width (/ width 2))
  (define half-height (/ height 2))
  (define concrete
    (make-path-visual
     (polygon-path
      (list (vec2 (- half-width) (- half-height))
            (vec2 half-width (- half-height))
            (vec2 half-width half-height)
            (vec2 (- half-width) half-height)))
     #:id (visual-id enclosure)
     #:center (visual-position target-visual)
     #:opacity (visual-opacity template)
     #:fill (rectangle-visual-fill template)
     #:stroke (rectangle-visual-stroke template)
     #:stroke-width (rectangle-visual-stroke-width template)))
  (place-world-visual-on-pict frame concrete camera renderers))

; place-world-visual-on-pict : pict? visual? camera? (listof pict-renderer?)
;                              -> pict?
;;   Places a world-space Visual at its camera-space reference position.
(define (place-world-visual-on-pict frame visual camera renderers)
  (define visual-pict
    (visual->pict visual camera #:renderers renderers))
  (define-values (center-x center-y)
    (camera-world->pixel camera (visual-position visual)))
  (pin-centered-pict frame center-x center-y visual-pict))

; place-layout-attached-visual-on-pict : pict? scene-state?
;                                        layout-attached-visual? camera?
;                                        (listof pict-renderer?) -> pict?
;; Places concrete world-space content by matching one of its rendered-box
;; anchors to a live anchor of a different sampled target.  This is intentionally
;; resolved in the adapter, after all ordinary scene state has been sampled,
;; rather than being smuggled into the renderer-independent derived-Visual
;; resolver.
(define (place-layout-attached-visual-on-pict frame state attachment camera renderers)
  (define concrete
    (resolve-layout-attached-content
     state attachment camera renderers 'scene-state->pict (visual-id attachment) '()))
  (define content-pict
    (visual->pict concrete camera #:renderers renderers))
  (define-values (center-x center-y)
    (camera-world->pixel camera (visual-position concrete)))
  (pin-centered-pict frame center-x center-y content-pict))

; layout-anchor-content-center : vec2? symbol? vec2? pict? camera? -> vec2?
;; Converts the desired location of a content anchor into the world-space point
;; at which that content Pict must be centred.  Picts have symmetric semantic
;; layout boxes in this adapter, matching visual-layout-box and callout anchors.
(define (layout-anchor-content-center target-point self-anchor offset content-pict camera)
  (define half-width
    (/ (pict-width content-pict) (camera-scale camera) 2))
  (define half-height
    (/ (pict-height content-pict) (camera-scale camera) 2))
  (define desired-anchor
    (vec2+ target-point offset))
  (define center-offset
    (case self-anchor
      [(bottom-left) (vec2 half-width half-height)]
      [(bottom) (vec2 0 half-height)]
      [(bottom-right) (vec2 (- half-width) half-height)]
      [(left) (vec2 half-width 0)]
      [(center) origin]
      [(right) (vec2 (- half-width) 0)]
      [(top-left) (vec2 half-width (- half-height))]
      [(top) (vec2 0 (- half-height))]
      [(top-right) (vec2 (- half-width) (- half-height))]
      [else
       (raise-argument-error
        'layout-anchor-content-center
        "supported layout anchor"
        self-anchor)]))
  (vec2+ desired-anchor center-offset))

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
  (when (or (dynamic-endpoint-visual? target-visual)
            (surrounding-rectangle-visual? target-visual))
    (raise-arguments-error
     who
     "a concrete world-space target, not another renderer-aware layout definition"
     "owner-id" owner-id
     "target-path" target))
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
  (if (layout-attached-visual? target-visual)
      (resolve-layout-attached-content
       state target-visual camera renderers who owner-id active-layout-ids)
      target-visual))

;; Resolves one attachment to a concrete world-space Visual. Its own target can
;; be another attachment; `active-layout-ids` supplies explicit acyclic layout
;; dependency checking instead of relying on accidental renderer recursion.
(define (resolve-layout-attached-content state attachment camera renderers
                                         who owner-id active-layout-ids)
  (define attachment-id (visual-id attachment))
  (when (memq attachment-id active-layout-ids)
    (raise-arguments-error
     who
     "an acyclic renderer-layout dependency graph"
     "owner-id" owner-id
     "cycle" (reverse (cons attachment-id active-layout-ids))))
  (define content (layout-attached-visual-content attachment))
  (when (frame-space-visual? content)
    (raise-arguments-error
     who
     "layout-attached content in world space, not frame space"
     "attachment-id" attachment-id
     "content" content))
  (define target-point
    (target-layout-world-point
     state
     (layout-attached-visual-target attachment)
     (layout-attached-visual-target-anchor attachment)
     camera renderers who owner-id (cons attachment-id active-layout-ids)))
  (define content-pict (visual->pict content camera #:renderers renderers))
  (visual-with-position
   content
   (layout-anchor-content-center
    target-point
    (layout-attached-visual-self-anchor attachment)
    (layout-attached-visual-offset attachment)
    content-pict camera)))

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
