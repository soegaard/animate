#lang racket/base

;;;
;;; Animation Model
;;;

;; Defines transform, path-following, style, opacity, named-value, path-morph,
;; path-reveal, and matched-formula requests with deterministic transitions.
;;
;; Animation requests capture destinations or relative changes. Scene
;; compilation supplies start values, so requests remain independent of earlier
;; timeline sampling.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "color-style.rkt"
         "derived-visual.rkt"
         "formula-part-transition.rkt"
         "formula-parts-visual.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "interpolation.rkt"
         "path-geometry.rkt"
         "scene-state.rkt"
         "visual-model.rkt")

;; Exports
(provide value-to
         value-to-request?
         move-to
         move-to-request?
         move-along-path
         move-along-path-request?
         orient-along-path
         orient-along-path-request?
         rotate-to
         rotate-to-request?
         rotate-by
         rotate-by-request?
         scale-to
         scale-to-request?
         scale-by
         scale-by-request?
         stroke-width-to
         stroke-width-to-request?
         fill-color-to
         fill-color-to-request?
         stroke-color-to
         stroke-color-to-request?
         fade-to
         fade-to-request?
         fade-in
         fade-in-request?
         fade-out
         fade-out-request?
         morph-to
         morph-to-request?
         morph-to-normalized
         morph-to-normalized-request?
         morph-to-aligned
         morph-to-aligned-request?
         morph-to-open-aligned
         morph-to-open-aligned-request?
         morph-to-open-compound-aligned
         morph-to-open-compound-aligned-request?
         morph-to-mixed-compound-aligned
         morph-to-mixed-compound-aligned-request?
         morph-to-topology-changing
         morph-to-topology-changing-request?
         morph-to-compound-aligned
         morph-to-compound-aligned-request?
         transform-formula-parts
         transform-formula-parts-request?
         create
         create-request?
         uncreate
         uncreate-request?
         linear
         animation-request?
         animation-request-target-id
         animation-request-components
         compile-animation-requests
         apply-compiled-animations
         finalize-compiled-animation
         complete-compiled-animations)


;;;
;;; Request Data
;;;

(struct value-to-request (target-id destination)
  #:transparent)

;; value-to-request represents an uncompiled named semantic-value transition.
;;  - target-id    symbol?       stable scene value identity.
;;  - destination  interpolable? requested final semantic value.

(struct move-to-request (target-id destination)
  #:transparent)

;; move-to-request represents an uncompiled translation request.
;;  - target-id    symbol?  stable id of the Visual to move.
;;  - destination  vec2?    requested final reference position.

(struct move-along-path-request (target-id path-source start end normal-offset)
  #:transparent)

;; move-along-path-request represents an uncompiled arc-length path motion.
;;  - target-id    symbol?                     stable id of the Visual to move.
;;  - path-source  (or/c path-geometry? symbol?) direct route or scene path id.
;;  - start        finite-real?                starting arc-length fraction.
;;  - end          finite-real?                ending arc-length fraction.
;;  - normal-offset finite-real?               signed left-of-motion offset.

(struct orient-along-path-request
  (target-id path-source start end rotation-offset)
  #:transparent)

;; orient-along-path-request represents tangent-aligned path rotation.
;;  - target-id       symbol?                     stable id of the Visual.
;;  - path-source     (or/c path-geometry? symbol?) direct route or scene path id.
;;  - start           finite-real?                starting arc-length fraction.
;;  - end             finite-real?                ending arc-length fraction.
;;  - rotation-offset finite-real?                radians added to path tangent.

(struct rotate-to-request (target-id angle)
  #:transparent)

;; rotate-to-request represents an uncompiled absolute rotation request.
;;  - target-id  symbol?       stable id of the affine Visual to rotate.
;;  - angle      finite-real?  requested final counter-clockwise radians.

(struct rotate-by-request (target-id delta)
  #:transparent)

;; rotate-by-request represents an uncompiled relative rotation request.
;;  - target-id  symbol?       stable id of the affine Visual to rotate.
;;  - delta      finite-real?  counter-clockwise radians added at clip start.

(struct scale-to-request (target-id scale)
  #:transparent)

;; scale-to-request represents an uncompiled absolute scale request.
;;  - target-id  symbol?  stable id of the affine Visual to scale.
;;  - scale      vec2?    requested final positive x and y scale factors.

(struct scale-by-request (target-id factor)
  #:transparent)

;; scale-by-request represents an uncompiled relative scale request.
;;  - target-id  symbol?  stable id of the affine Visual to scale.
;;  - factor     vec2?    positive factors multiplied at clip start.

(struct stroke-width-to-request (target-id stroke-width)
  #:transparent)

;; stroke-width-to-request represents an uncompiled absolute stroke-width request.
;;  - target-id     symbol?         stable id of the stroke-width Visual.
;;  - stroke-width  stroke-width?  requested final cosmetic stroke width.

(struct fill-color-to-request (target-id color)
  #:transparent)

;; fill-color-to-request represents an uncompiled absolute fill-color request.
;;  - target-id  symbol?      stable id of the fill-color Visual.
;;  - color      color-spec?  requested final semantic fill color.

(struct stroke-color-to-request (target-id color)
  #:transparent)

;; stroke-color-to-request represents an uncompiled absolute stroke-color request.
;;  - target-id  symbol?      stable id of the stroke-color Visual.
;;  - color      color-spec?  requested final semantic stroke color.

(struct fade-to-request (target-id opacity)
  #:transparent)

;; fade-to-request represents an uncompiled absolute opacity request.
;;  - target-id  symbol?   stable id of the opacity Visual to change.
;;  - opacity    opacity?  requested final global opacity.

(struct fade-in-request (visual)
  #:transparent)

;; fade-in-request represents an uncompiled opacity introduction request.
;;  - visual  (and/c visual? opacity-visual?)
;;            complete Visual introduced during the play clip.

(struct fade-out-request (target-id)
  #:transparent)

;; fade-out-request represents an uncompiled opacity removal request.
;;  - target-id  symbol?  stable id of the opacity Visual removed at clip end.

(struct morph-to-request (target-id destination)
  #:transparent)

;; morph-to-request represents an uncompiled strict local path morph request.
;;  - target-id    symbol?          stable id of the path Visual to change.
;;  - destination  path-geometry?  requested final local path geometry.

(struct morph-to-normalized-request (target-id destination)
  #:transparent)

;; morph-to-normalized-request represents an uncompiled normalized path morph.
;;  - target-id    symbol?          stable id of the path Visual to change.
;;  - destination  path-geometry?  requested final local path geometry.

(struct morph-to-aligned-request
  (target-id destination allow-reverse? sample-count)
  #:transparent)

;; morph-to-aligned-request represents an automatically corresponded loop morph.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

(struct morph-to-open-aligned-request
  (target-id destination allow-reverse? sample-count)
  #:transparent)

;; morph-to-open-aligned-request represents an automatically directed open-path
;; morph. Endpoint correspondence may keep or reverse destination traversal.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

(struct morph-to-open-compound-aligned-request
  (target-id destination allow-reverse? sample-count)
  #:transparent)

;; morph-to-open-compound-aligned-request represents an automatically paired
;; compound morph whose subpaths are all open. Distinct destination subpaths are
;; globally assigned to source subpaths, then each pair may reverse direction.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

(struct morph-to-mixed-compound-aligned-request
  (target-id destination allow-reverse? sample-count)
  #:transparent)

;; morph-to-mixed-compound-aligned-request represents automatic topology-aware
;; compound correspondence. Open subpaths pair only with open subpaths; closed
;; loops pair only with closed loops, and the selected subpaths are reordered to
;; source topology/order before normalized interpolation.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

(struct morph-to-topology-changing-request
  (target-id destination allow-reverse? sample-count
             birth-anchor death-anchor birth-anchor-map death-anchor-map
             birth-penalty death-penalty birth-penalty-map death-penalty-map
             match-penalty-map)
  #:transparent)

;; morph-to-topology-changing-request represents automatic topology-aware
;; compound correspondence with deterministic subpath birth/death seeds.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

;;  - birth-anchor    (or/c 'bounds-center vec2?)  fallback local point for births.
;;  - death-anchor    (or/c 'bounds-center vec2?)  fallback local point for deaths.
;;  - birth-anchor-map hash? sparse destination-index birth-anchor overrides.
;;  - death-anchor-map hash? sparse source-index death-anchor overrides.
;;  - birth-penalty   (or/c 'forced nonnegative-finite-real?) birth cost fallback.
;;  - death-penalty   (or/c 'forced nonnegative-finite-real?) death cost fallback.
;;  - birth-penalty-map hash? sparse destination-index birth-cost overrides.
;;  - death-penalty-map hash? sparse source-index death-cost overrides.
;;  - match-penalty-map hash? sparse (source-index . destination-index) real-edge additions.

(struct morph-to-compound-aligned-request
  (target-id destination allow-reverse? sample-count)
  #:transparent)

;; morph-to-compound-aligned-request represents an automatically paired compound
;; path morph. Each closed destination subpath is globally assigned to one source
;; subpath, then SCENE-AC phase/direction alignment is applied within each pair.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

(struct transform-formula-parts-request (correspondence)
  #:transparent)

;; transform-formula-parts-request represents an uncompiled matched-part change.
;;  - correspondence  formula-correspondence?  explicit source-to-destination map.

(struct create-request (visual)
  #:transparent)

;; create-request represents an uncompiled path introduction request.
;;  - visual  path-visual?  complete Visual introduced during the play clip.

(struct uncreate-request (target-id)
  #:transparent)

;; uncreate-request represents an uncompiled path removal request.
;;  - target-id  symbol?  stable id of the path Visual removed at clip end.


;;;
;;; Compiled Animation Data
;;;

(struct scalar-value-animation (target-id from to)
  #:transparent)

;; scalar-value-animation represents one compiled named semantic-value transition.
;;  - target-id  symbol?       stable scene value identity.
;;  - from       interpolable? semantic value at interval start.
;;  - to         interpolable? exact requested semantic endpoint.

(struct translation-animation (target-id from to)
  #:transparent)

;; translation-animation represents one compiled position transition.
;;  - target-id  symbol?  stable id of the Visual to move.
;;  - from       vec2?    reference position at clip start.
;;  - to         vec2?    reference position at clip end.

(struct path-motion-animation (target-id path start end normal-offset)
  #:transparent)

;; path-motion-animation represents one compiled arc-length path traversal.
;;  - target-id  symbol?          stable id of the Visual to move.
;;  - path       path-geometry?  continuous route in target coordinates.
;;  - start      finite-real?    starting route fraction.
;;  - end        finite-real?    ending route fraction.
;;  - normal-offset finite-real? signed left-of-motion offset.

(struct path-orientation-animation
  (target-id path start end rotation-offset)
  #:transparent)

;; path-orientation-animation represents tangent-derived absolute rotation.
;;  - target-id       symbol?          stable id of the affine Visual.
;;  - path            path-geometry?  continuous route in target coordinates.
;;  - start           finite-real?    starting route fraction.
;;  - end             finite-real?    ending route fraction.
;;  - rotation-offset finite-real?    radians added to traversal tangent.

(struct rotation-animation (target-id from to)
  #:transparent)

;; rotation-animation represents one compiled rotation transition.
;;  - target-id  symbol?       stable id of the affine Visual to rotate.
;;  - from       finite-real?  rotation at clip start.
;;  - to         finite-real?  rotation at clip end.

(struct scaling-animation (target-id from to)
  #:transparent)

;; scaling-animation represents one compiled scale transition.
;;  - target-id  symbol?  stable id of the affine Visual to scale.
;;  - from       vec2?    positive scale at clip start.
;;  - to         vec2?    positive scale at clip end.

(struct stroke-width-animation (target-id from to)
  #:transparent)

;; stroke-width-animation represents one compiled cosmetic-width transition.
;;  - target-id  symbol?         stable id of the stroke-width Visual.
;;  - from       stroke-width?  width at clip start.
;;  - to         stroke-width?  requested width at clip end.

(struct fill-color-animation
  (target-id from-spec from-color to-spec to-color)
  #:transparent)

;; fill-color-animation keeps exact style endpoints plus resolved RGBA interiors.
;;  - target-id  symbol?       stable id of the fill-color Visual.
;;  - from-spec  color-spec?   exact semantic style at interval start.
;;  - from-color rgba-color?   normalized interpolation source.
;;  - to-spec    color-spec?   exact requested semantic endpoint.
;;  - to-color   rgba-color?   normalized interpolation destination.

(struct stroke-color-animation
  (target-id from-spec from-color to-spec to-color)
  #:transparent)

;; stroke-color-animation is the corresponding semantic stroke-color transition.

(struct opacity-animation
  (target-id from to force-to-at-end? remove-at-end?)
  #:transparent)

;; opacity-animation represents one compiled global-opacity transition.
;;  - target-id        symbol?   stable id of the opacity Visual to change.
;;  - from             opacity?  global opacity at clip start.
;;  - to               opacity?  requested global opacity at clip end.
;;  - force-to-at-end? boolean?  whether structural completion installs to.
;;  - remove-at-end?   boolean?  whether structural completion removes Visual.

(struct path-morph-animation (target-id from to)
  #:transparent)

;; path-morph-animation represents one compiled compatible path transition.
;;  - target-id  symbol?          stable id of the path Visual to change.
;;  - from       path-geometry?  complete local path at clip start.
;;  - to         path-geometry?  complete local path at clip end.

(struct normalized-path-morph-animation
  (target-id source normalized-source normalized-destination destination)
  #:transparent)

;; normalized-path-morph-animation represents one normalized path transition.
;;  - target-id               symbol?          stable id of the path Visual.
;;  - source                  path-geometry?  exact source representation.
;;  - normalized-source       path-geometry?  cubic source used in interiors.
;;  - normalized-destination  path-geometry?  compatible cubic destination.
;;  - destination             path-geometry?  exact requested destination.

(struct formula-parts-transform-animation (target-id plan)
  #:transparent)

;; formula-parts-transform-animation represents one compiled part transition.
;;  - target-id  symbol?                    stable assembly identity.
;;  - plan       formula-transition-plan?  exact endpoints and interior layers.

(struct path-reveal-animation (target-id path from to remove-at-end?)
  #:transparent)

;; path-reveal-animation represents one compiled arc-length reveal transition.
;;  - target-id       symbol?          stable id of the path Visual.
;;  - path            path-geometry?  complete local path geometry.
;;  - from            finite-real?    visible prefix fraction at clip start.
;;  - to              finite-real?    visible prefix fraction at clip end.
;;  - remove-at-end?  boolean?        whether completion removes the Visual.


;;;
;;; Public Animation Requests
;;;

; value-to : symbol? interpolable? -> value-to-request?
;;   Creates an absolute animation request for one named scene semantic value.
(define (value-to target-id destination)
  (unless (symbol? target-id)
    (raise-argument-error 'value-to "symbol?" target-id))
  (unless (interpolable? destination)
    (raise-argument-error 'value-to "interpolable?" destination))
  (value-to-request target-id destination))

; move-to : (or/c visual? symbol?) vec2? -> move-to-request?
;;   Creates a request to move target to destination.
(define (move-to target destination)
  (unless (vec2? destination)
    (raise-argument-error 'move-to "vec2?" destination))
  (move-to-request (visual-target-id target 'move-to)
                   destination))

; move-along-path : (or/c visual? symbol?)
;                   (or/c path-geometry? path-visual? derived-visual? symbol?)
;                   [#:start unit-real?]
;                   [#:end unit-real?]
;                   [#:normal-offset finite-real?]
;                   -> move-along-path-request?
;;   Creates a request that places target along a semantic path by arc length.
(define (move-along-path target path
                         #:start [start 0]
                         #:end [end 1]
                         #:normal-offset [normal-offset 0])
  (define target-id
    (visual-target-id target 'move-along-path))
  (define path-source
    (normalize-path-animation-source 'move-along-path path))
  (check-path-motion-fraction 'move-along-path "start" start)
  (check-path-motion-fraction 'move-along-path "end" end)
  (unless (finite-real? normal-offset)
    (raise-argument-error 'move-along-path "finite real?" normal-offset))
  (move-along-path-request target-id
                           path-source
                           start
                           end
                           normal-offset))

; orient-along-path : (or/c visual? symbol?)
;                     (or/c path-geometry? path-visual? derived-visual? symbol?)
;                     [#:start unit-real?]
;                     [#:end unit-real?]
;                     [#:rotation-offset finite-real?]
;                     -> orient-along-path-request?
;;   Creates a request that rotates target to the route's traversal tangent.
(define (orient-along-path target path
                           #:start [start 0]
                           #:end [end 1]
                           #:rotation-offset [rotation-offset 0])
  (define target-id
    (visual-target-id target 'orient-along-path))
  (define path-source
    (normalize-path-animation-source 'orient-along-path path))
  (check-path-motion-fraction 'orient-along-path "start" start)
  (check-path-motion-fraction 'orient-along-path "end" end)
  (unless (finite-real? rotation-offset)
    (raise-argument-error 'orient-along-path
                          "finite real?"
                          rotation-offset))
  (orient-along-path-request target-id
                             path-source
                             start
                             end
                             rotation-offset))

; rotate-to : (or/c visual? symbol?) finite-real? -> rotate-to-request?
;;   Creates a request to rotate target to an absolute angle.
(define (rotate-to target angle)
  (unless (finite-real? angle)
    (raise-argument-error 'rotate-to "finite real?" angle))
  (rotate-to-request (visual-target-id target 'rotate-to)
                     angle))

; rotate-by : (or/c visual? symbol?) finite-real? -> rotate-by-request?
;;   Creates a request to add a counter-clockwise rotation to target.
(define (rotate-by target delta)
  (unless (finite-real? delta)
    (raise-argument-error 'rotate-by "finite real?" delta))
  (rotate-by-request (visual-target-id target 'rotate-by)
                     delta))

; scale-to : (or/c visual? symbol?) (or/c positive-real? vec2?)
;            -> scale-to-request?
;;   Creates a request to replace target's absolute local scale.
(define (scale-to target scale)
  (check-animation-scale 'scale-to scale)
  (scale-to-request (visual-target-id target 'scale-to)
                    (scale-factor->vec2 scale)))

; scale-by : (or/c visual? symbol?) (or/c positive-real? vec2?)
;            -> scale-by-request?
;;   Creates a request to multiply target's local scale.
(define (scale-by target factor)
  (check-animation-scale 'scale-by factor)
  (scale-by-request (visual-target-id target 'scale-by)
                    (scale-factor->vec2 factor)))

; stroke-width-to : (or/c symbol? (and/c visual? stroke-width-visual?))
;                   stroke-width?
;                   -> stroke-width-to-request?
;;   Creates a request to replace target's cosmetic stroke width.
(define (stroke-width-to target stroke-width)
  (check-stroke-width-request-target 'stroke-width-to target)
  (check-animation-stroke-width 'stroke-width-to stroke-width)
  (stroke-width-to-request
   (visual-target-id target 'stroke-width-to)
   stroke-width))

; fill-color-to : (or/c symbol? (and/c visual? fill-color-visual?)) color-spec?
;                 -> fill-color-to-request?
;;   Creates a request to replace target's semantic fill color.
(define (fill-color-to target color)
  (check-fill-color-request-target 'fill-color-to target)
  (check-animation-color-spec 'fill-color-to color)
  (fill-color-to-request
   (visual-target-id target 'fill-color-to)
   color))

; stroke-color-to : (or/c symbol? (and/c visual? stroke-color-visual?))
;                   color-spec? -> stroke-color-to-request?
;;   Creates a request to replace target's semantic stroke color.
(define (stroke-color-to target color)
  (check-stroke-color-request-target 'stroke-color-to target)
  (check-animation-color-spec 'stroke-color-to color)
  (stroke-color-to-request
   (visual-target-id target 'stroke-color-to)
   color))

; fade-to : (or/c symbol? (and/c visual? opacity-visual?)) opacity?
;           -> fade-to-request?
;;   Creates a request to replace target's global opacity.
(define (fade-to target opacity)
  (check-opacity-request-target 'fade-to target)
  (check-animation-opacity 'fade-to opacity)
  (fade-to-request (visual-target-id target 'fade-to)
                   opacity))

; fade-in : (and/c visual? opacity-visual?) -> fade-in-request?
;;   Creates a request that introduces visual by increasing its opacity.
(define (fade-in visual)
  (check-opacity-visual-value 'fade-in visual)
  (fade-in-request visual))

; fade-out : (or/c symbol? (and/c visual? opacity-visual?))
;            -> fade-out-request?
;;   Creates a request that lowers and then removes an opacity Visual.
(define (fade-out target)
  (check-opacity-request-target 'fade-out target)
  (fade-out-request (visual-target-id target 'fade-out)))

; morph-to : (or/c path-visual? symbol?) path-geometry?
;            -> morph-to-request?
;;   Creates a request to interpolate target to destination path geometry.
(define (morph-to target destination)
  (check-path-morph-request-arguments 'morph-to target destination)
  (morph-to-request (visual-target-id target 'morph-to)
                    destination))

; morph-to-normalized : (or/c path-visual? symbol?) path-geometry?
;                       -> morph-to-normalized-request?
;;   Creates a request that normalizes limited path differences before morphing.
(define (morph-to-normalized target destination)
  (check-path-morph-request-arguments
   'morph-to-normalized
   target
   destination)
  (morph-to-normalized-request
   (visual-target-id target 'morph-to-normalized)
   destination))

; morph-to-aligned : (or/c path-visual? symbol?) path-geometry?
;                    [#:allow-reverse? boolean?]
;                    [#:sample-count exact-integer?]
;                    -> morph-to-aligned-request?
;;   Creates a normalized morph with automatic closed-loop correspondence.
(define (morph-to-aligned target destination
                          #:allow-reverse? [allow-reverse? #t]
                          #:sample-count [sample-count 64])
  (check-path-morph-request-arguments
   'morph-to-aligned
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error 'morph-to-aligned "boolean?" allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-aligned
     "exact integer greater than or equal to 8"
     sample-count))
  (morph-to-aligned-request
   (visual-target-id target 'morph-to-aligned)
   destination
   allow-reverse?
   sample-count))

; morph-to-open-aligned : (or/c path-visual? symbol?) path-geometry?
;                         [#:allow-reverse? boolean?]
;                         [#:sample-count exact-integer?]
;                         -> morph-to-open-aligned-request?
;;   Creates a normalized morph with automatic open-path endpoint correspondence.
(define (morph-to-open-aligned target destination
                               #:allow-reverse? [allow-reverse? #t]
                               #:sample-count [sample-count 64])
  (check-path-morph-request-arguments
   'morph-to-open-aligned
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error 'morph-to-open-aligned "boolean?" allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-open-aligned
     "exact integer greater than or equal to 8"
     sample-count))
  (morph-to-open-aligned-request
   (visual-target-id target 'morph-to-open-aligned)
   destination
   allow-reverse?
   sample-count))

; morph-to-open-compound-aligned : (or/c path-visual? symbol?) path-geometry?
;                                  [#:allow-reverse? boolean?]
;                                  [#:sample-count exact-integer?]
;                                  -> morph-to-open-compound-aligned-request?
;;   Creates a normalized morph with automatic open-subpath pairing.
(define (morph-to-open-compound-aligned target destination
                                        #:allow-reverse? [allow-reverse? #t]
                                        #:sample-count [sample-count 64])
  (check-path-morph-request-arguments
   'morph-to-open-compound-aligned
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error
     'morph-to-open-compound-aligned
     "boolean?"
     allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-open-compound-aligned
     "exact integer greater than or equal to 8"
     sample-count))
  (morph-to-open-compound-aligned-request
   (visual-target-id target 'morph-to-open-compound-aligned)
   destination
   allow-reverse?
   sample-count))

; morph-to-mixed-compound-aligned : (or/c path-visual? symbol?) path-geometry?
;                                   [#:allow-reverse? boolean?]
;                                   [#:sample-count exact-integer?]
;                                   -> morph-to-mixed-compound-aligned-request?
;;   Creates a normalized morph with topology-aware compound pairing.
(define (morph-to-mixed-compound-aligned target destination
                                         #:allow-reverse? [allow-reverse? #t]
                                         #:sample-count [sample-count 64])
  (check-path-morph-request-arguments
   'morph-to-mixed-compound-aligned
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error
     'morph-to-mixed-compound-aligned
     "boolean?"
     allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-mixed-compound-aligned
     "exact integer greater than or equal to 8"
     sample-count))
  (morph-to-mixed-compound-aligned-request
   (visual-target-id target 'morph-to-mixed-compound-aligned)
   destination
   allow-reverse?
   sample-count))

; morph-to-topology-changing : (or/c path-visual? symbol?) path-geometry?
;                               [#:allow-reverse? boolean?]
;                               [#:sample-count exact-integer?]
;                               [#:birth-anchor (or/c 'bounds-center vec2?)]
;                               [#:death-anchor (or/c 'bounds-center vec2?)]
;                               [#:birth-anchor-map hash?]
;                               [#:death-anchor-map hash?]
;                               [#:birth-penalty (or/c 'forced nonnegative-finite-real?)]
;                               [#:death-penalty (or/c 'forced nonnegative-finite-real?)]
;                               [#:birth-penalty-map hash?]
;                               [#:death-penalty-map hash?]
;                               [#:match-penalty-map hash?]
;                               -> morph-to-topology-changing-request?
;;   Creates a normalized topology-aware morph with subpath births/deaths.
(define (morph-to-topology-changing target destination
                                    #:allow-reverse? [allow-reverse? #t]
                                    #:sample-count [sample-count 64]
                                    #:birth-anchor [birth-anchor 'bounds-center]
                                    #:death-anchor [death-anchor 'bounds-center]
                                    #:birth-anchor-map [birth-anchor-map #hash()]
                                    #:death-anchor-map [death-anchor-map #hash()]
                                    #:birth-penalty [birth-penalty 'forced]
                                    #:death-penalty [death-penalty 'forced]
                                    #:birth-penalty-map [birth-penalty-map #hash()]
                                    #:death-penalty-map [death-penalty-map #hash()]
                                    #:match-penalty-map [match-penalty-map #hash()])
  (check-path-morph-request-arguments
   'morph-to-topology-changing
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error
     'morph-to-topology-changing
     "boolean?"
     allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-topology-changing
     "exact integer greater than or equal to 8"
     sample-count))
  (check-topology-morph-anchor-argument
   'morph-to-topology-changing "#:birth-anchor" birth-anchor)
  (check-topology-morph-anchor-argument
   'morph-to-topology-changing "#:death-anchor" death-anchor)
  (define immutable-birth-anchor-map
    (snapshot-topology-morph-anchor-map
     'morph-to-topology-changing "#:birth-anchor-map" birth-anchor-map))
  (define immutable-death-anchor-map
    (snapshot-topology-morph-anchor-map
     'morph-to-topology-changing "#:death-anchor-map" death-anchor-map))
  (define immutable-birth-penalty-map
    (snapshot-topology-morph-penalty-map
     'morph-to-topology-changing "#:birth-penalty-map" birth-penalty-map))
  (define immutable-death-penalty-map
    (snapshot-topology-morph-penalty-map
     'morph-to-topology-changing "#:death-penalty-map" death-penalty-map))
  (define immutable-match-penalty-map
    (snapshot-topology-morph-match-penalty-map
     'morph-to-topology-changing "#:match-penalty-map" match-penalty-map))
  (check-topology-morph-penalty-arguments
   'morph-to-topology-changing
   birth-penalty
   death-penalty
   immutable-birth-penalty-map
   immutable-death-penalty-map)
  (morph-to-topology-changing-request
   (visual-target-id target 'morph-to-topology-changing)
   destination
   allow-reverse?
   sample-count
   birth-anchor
   death-anchor
   immutable-birth-anchor-map
   immutable-death-anchor-map
   birth-penalty
   death-penalty
   immutable-birth-penalty-map
   immutable-death-penalty-map
   immutable-match-penalty-map))

; snapshot-topology-morph-anchor-map : symbol? string? any/c -> hash?
;;   Validates and snapshots sparse per-subpath anchor overrides in a request.
(define (snapshot-topology-morph-anchor-map who field value)
  (unless (hash? value)
    (raise-arguments-error
     who
     "expected a topology morph anchor map"
     field value
     "expected" "hash?"))
  (for/fold ([result #hash()])
            ([(subpath-index anchor) (in-hash value)])
    (unless (exact-nonnegative-integer? subpath-index)
      (raise-arguments-error
       who
       "expected nonnegative exact-integer anchor-map keys"
       field value
       "key" subpath-index))
    (check-topology-morph-anchor-argument who field anchor)
    (when (hash-has-key? result subpath-index)
      (raise-arguments-error
       who
       "anchor-map contains duplicate numeric keys under equal? lookup"
       field value
       "key" subpath-index))
    (hash-set result subpath-index anchor)))

; check-topology-morph-anchor-argument : symbol? string? any/c -> void?
;;   Validates one declarative local anchor captured by a morph request.
(define (check-topology-morph-anchor-argument who field value)
  (unless (or (eq? value 'bounds-center)
              (vec2? value))
    (raise-arguments-error
     who
     "expected a topology morph anchor"
     field value
     "expected" "'bounds-center or vec2?")))

; snapshot-topology-morph-penalty-map : symbol? string? any/c -> hash?
;;   Validates and snapshots sparse per-subpath numeric penalty overrides.
(define (snapshot-topology-morph-penalty-map who field value)
  (unless (hash? value)
    (raise-arguments-error
     who
     "expected a topology morph penalty map"
     field value
     "expected" "hash?"))
  (for/fold ([result #hash()])
            ([(subpath-index penalty) (in-hash value)])
    (unless (exact-nonnegative-integer? subpath-index)
      (raise-arguments-error
       who
       "expected nonnegative exact-integer penalty-map keys"
       field value
       "key" subpath-index))
    (unless (and (finite-real? penalty)
                 (>= penalty 0))
      (raise-arguments-error
       who
       "expected finite nonnegative penalty-map values"
       field value
       "key" subpath-index
       "value" penalty))
    (when (hash-has-key? result subpath-index)
      (raise-arguments-error
       who
       "penalty-map contains duplicate numeric keys under equal? lookup"
       field value
       "key" subpath-index))
    (hash-set result subpath-index penalty)))

; snapshot-topology-morph-match-penalty-map : symbol? string? any/c -> hash?
;;   Validates and snapshots sparse pairwise additive real-match costs.
(define (snapshot-topology-morph-match-penalty-map who field value)
  (unless (hash? value)
    (raise-arguments-error
     who
     "expected a topology morph match-penalty map"
     field value
     "expected" "hash?"))
  (for/fold ([result #hash()])
            ([(pair-key penalty) (in-hash value)])
    (unless (and (pair? pair-key)
                 (exact-nonnegative-integer? (car pair-key))
                 (exact-nonnegative-integer? (cdr pair-key)))
      (raise-arguments-error
       who
       "expected match-penalty-map keys of the form (cons source-index destination-index)"
       field value
       "key" pair-key))
    (unless (and (finite-real? penalty)
                 (>= penalty 0))
      (raise-arguments-error
       who
       "expected finite nonnegative match-penalty-map values"
       field value
       "key" pair-key
       "value" penalty))
    (define normalized-key (cons (car pair-key) (cdr pair-key)))
    (when (hash-has-key? result normalized-key)
      (raise-arguments-error
       who
       "match-penalty-map contains duplicate pair keys under equal? lookup"
       field value
       "key" pair-key))
    (hash-set result normalized-key penalty)))

; check-topology-morph-penalty-arguments : symbol? any/c any/c hash? hash? -> void?
;;   Requires forced-only defaults with empty maps or numeric costs with overrides.
(define (check-topology-morph-penalty-arguments
         who birth-penalty death-penalty birth-penalty-map death-penalty-map)
  (define (numeric-penalty? value)
    (and (finite-real? value)
         (>= value 0)))
  (unless (or (and (eq? birth-penalty 'forced)
                   (eq? death-penalty 'forced))
              (and (numeric-penalty? birth-penalty)
                   (numeric-penalty? death-penalty)))
    (raise-arguments-error
     who
     "expected both birth/death penalties to use the same policy mode"
     "#:birth-penalty" birth-penalty
     "#:death-penalty" death-penalty
     "expected" "both 'forced, or both nonnegative finite real numbers"))
  (when (and (eq? birth-penalty 'forced)
             (or (positive? (hash-count birth-penalty-map))
                 (positive? (hash-count death-penalty-map))))
    (raise-arguments-error
     who
     "per-subpath penalty maps require numeric birth/death penalty mode"
     "#:birth-penalty" birth-penalty
     "#:death-penalty" death-penalty
     "#:birth-penalty-map" birth-penalty-map
     "#:death-penalty-map" death-penalty-map)))

; morph-to-compound-aligned : (or/c path-visual? symbol?) path-geometry?
;                             [#:allow-reverse? boolean?]
;                             [#:sample-count exact-integer?]
;                             -> morph-to-compound-aligned-request?
;;   Creates a normalized morph with automatic closed-subpath pairing.
(define (morph-to-compound-aligned target destination
                                   #:allow-reverse? [allow-reverse? #t]
                                   #:sample-count [sample-count 64])
  (check-path-morph-request-arguments
   'morph-to-compound-aligned
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error
     'morph-to-compound-aligned
     "boolean?"
     allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-compound-aligned
     "exact integer greater than or equal to 8"
     sample-count))
  (morph-to-compound-aligned-request
   (visual-target-id target 'morph-to-compound-aligned)
   destination
   allow-reverse?
   sample-count))

; transform-formula-parts : formula-correspondence?
;                           -> transform-formula-parts-request?
;;   Creates a request that moves and cross-fades explicitly matched parts.
(define (transform-formula-parts correspondence)
  (unless (formula-correspondence? correspondence)
    (raise-argument-error
     'transform-formula-parts
     "formula-correspondence?"
     correspondence))
  (transform-formula-parts-request correspondence))

; create : path-visual? -> create-request?
;;   Creates a request that introduces visual by revealing its path prefix.
(define (create visual)
  (unless (path-visual? visual)
    (raise-argument-error 'create "path-visual?" visual))
  (create-request visual))

; uncreate : (or/c path-visual? symbol?) -> uncreate-request?
;;   Creates a request that hides and then removes a path Visual.
(define (uncreate target)
  (unless (or (symbol? target)
              (path-visual? target))
    (raise-argument-error
     'uncreate
     "(or/c path-visual? symbol?)"
     target))
  (uncreate-request (visual-target-id target 'uncreate)))

; linear : finite-real? -> finite-real?
;;   Returns progress unchanged.
(define (linear progress)
  progress)


;;;
;;; Compilation
;;;

; compile-animation-requests : scene-state? (listof animation-request?)
;                              -> (values scene-state?
;                                         (listof compiled-animation?))
;;   Prepares the clip start state and compiles all requests against it.
(define (compile-animation-requests state requests)
  (unless (scene-state? state)
    (raise-argument-error
     'compile-animation-requests
     "scene-state?"
     state))
  (unless (and (list? requests)
               (andmap animation-request? requests))
    (raise-argument-error
     'compile-animation-requests
     "list of animation requests"
     requests))
  (check-request-component-conflicts requests)
  (define start-state
    (prepare-animation-start-state state requests))
  (values start-state
          (for/list ([request (in-list requests)])
            (compile-animation-request start-state request))))

; prepare-animation-start-state : scene-state? (listof animation-request?)
;                                  -> scene-state?
;;   Adds invisible placeholders for Visuals introduced by structural requests.
(define (prepare-animation-start-state state requests)
  (for/fold ([prepared-state state])
            ([request (in-list requests)])
    (cond
      [(create-request? request)
       (define visual
         (create-request-visual request))
       (define id
         (visual-id visual))
       (check-absent-introduction-target prepared-state id 'create)
       (scene-state-add
        prepared-state
        (path-visual-with-path visual empty-path-geometry))]
      [(fade-in-request? request)
       (define visual
         (fade-in-request-visual request))
       (define id
         (visual-id visual))
       (check-absent-introduction-target prepared-state id 'fade-in)
       (scene-state-add
        prepared-state
        (replace-visual-opacity 'scene-play visual 0))]
      [else
       prepared-state])))

; compile-animation-request : scene-state? animation-request?
;                             -> compiled-animation?
;;   Compiles one request against state.
(define (compile-animation-request state request)
  (define target-id
    (animation-request-target-id request))
  (cond
    [(value-to-request? request)
     (define from
       (scene-state-value-ref state target-id))
     (define to
       (value-to-request-destination request))
     ;; Validate compatibility during compilation, before a scene acquires the
     ;; clip. The result is deliberately discarded; sampling preserves exact
     ;; endpoint representations through interpolate-value.
     (interpolate-value from to 1/2)
     (scalar-value-animation
      target-id
      from
      to)]
    [else
     (define visual
       (scene-state-ref state target-id))
     (when (derived-visual? visual)
       (raise-arguments-error
        'scene-play
        "derived Visuals are controlled by named scalar values and cannot be animated directly"
        "visual-id" target-id
        "request" request))
     (cond
    [(move-to-request? request)
     (translation-animation target-id
                            (visual-position visual)
                            (move-to-request-destination request))]
    [(move-along-path-request? request)
     (define path
       (resolve-path-animation-route
        state
        visual
        (move-along-path-request-path-source request)
        'move-along-path
        (move-along-path-request-start request)
        (move-along-path-request-end request)))
     (unless (zero? (move-along-path-request-normal-offset request))
       (path-traversal-tangent-at
        path
        (move-along-path-request-start request)
        (move-along-path-request-start request)
        (move-along-path-request-end request))
       (path-traversal-tangent-at
        path
        (move-along-path-request-end request)
        (move-along-path-request-start request)
        (move-along-path-request-end request)))
     (path-motion-animation
      target-id
      path
      (move-along-path-request-start request)
      (move-along-path-request-end request)
      (move-along-path-request-normal-offset request))]
    [(orient-along-path-request? request)
     (check-affine-animation-target visual 'rotation)
     (define path
       (resolve-path-animation-route
        state
        visual
        (orient-along-path-request-path-source request)
        'orient-along-path
        (orient-along-path-request-start request)
        (orient-along-path-request-end request)))
     (path-traversal-tangent-at
      path
      (orient-along-path-request-start request)
      (orient-along-path-request-start request)
      (orient-along-path-request-end request))
     (path-traversal-tangent-at
      path
      (orient-along-path-request-end request)
      (orient-along-path-request-start request)
      (orient-along-path-request-end request))
     (path-orientation-animation
      target-id
      path
      (orient-along-path-request-start request)
      (orient-along-path-request-end request)
      (orient-along-path-request-rotation-offset request))]
    [(rotate-to-request? request)
     (check-affine-animation-target visual 'rotation)
     (rotation-animation target-id
                         (visual-rotation visual)
                         (rotate-to-request-angle request))]
    [(rotate-by-request? request)
     (check-affine-animation-target visual 'rotation)
     (let ([from (visual-rotation visual)])
       (rotation-animation target-id
                           from
                           (+ from (rotate-by-request-delta request))))]
    [(scale-to-request? request)
     (check-affine-animation-target visual 'scale)
     (define to
       (scale-to-request-scale request))
     (check-scale-animation-endpoint visual to)
     (scaling-animation target-id
                        (visual-scale visual)
                        to)]
    [(scale-by-request? request)
     (check-affine-animation-target visual 'scale)
     (define from
       (visual-scale visual))
     (define to
       (vec2* from
              (scale-by-request-factor request)))
     (check-scale-animation-endpoint visual to)
     (scaling-animation target-id from to)]
    [(stroke-width-to-request? request)
     (check-stroke-width-animation-target visual 'stroke-width-to)
     (define to
       (stroke-width-to-request-stroke-width request))
     (replace-visual-stroke-width 'scene-play visual to)
     (stroke-width-animation
      target-id
      (checked-visual-stroke-width 'scene-play visual)
      to)]

    [(fill-color-to-request? request)
     (check-fill-color-animation-target visual 'fill-color-to)
     (define from-spec
       (checked-visual-fill-color 'scene-play visual))
     (define to-spec
       (fill-color-to-request-color request))
     (replace-visual-fill-color 'scene-play visual to-spec)
     (fill-color-animation
      target-id
      from-spec
      (color-spec->rgba-color from-spec 'scene-play)
      to-spec
      (color-spec->rgba-color to-spec 'scene-play))]
    [(stroke-color-to-request? request)
     (check-stroke-color-animation-target visual 'stroke-color-to)
     (define from-spec
       (checked-visual-stroke-color 'scene-play visual))
     (define to-spec
       (stroke-color-to-request-color request))
     (replace-visual-stroke-color 'scene-play visual to-spec)
     (stroke-color-animation
      target-id
      from-spec
      (color-spec->rgba-color from-spec 'scene-play)
      to-spec
      (color-spec->rgba-color to-spec 'scene-play))]
    [(fade-to-request? request)
     (check-opacity-animation-target visual 'fade-to)
     (opacity-animation target-id
                        (checked-visual-opacity 'scene-play visual)
                        (fade-to-request-opacity request)
                        #f
                        #f)]
    [(fade-in-request? request)
     (define complete-visual
       (fade-in-request-visual request))
     (check-opacity-animation-target complete-visual 'fade-in)
     (opacity-animation target-id
                        (checked-visual-opacity 'scene-play visual)
                        (checked-visual-opacity 'scene-play complete-visual)
                        #t
                        #f)]
    [(fade-out-request? request)
     (check-opacity-animation-target visual 'fade-out)
     (opacity-animation target-id
                        (checked-visual-opacity 'scene-play visual)
                        0
                        #f
                        #t)]
    [(morph-to-request? request)
     (check-path-morph-target visual 'morph-to)
     (define from-path
       (path-visual-path visual))
     (define to-path
       (morph-to-request-destination request))
     (path-geometry-lerp from-path to-path 0)
     (path-morph-animation target-id
                           from-path
                           to-path)]
    [(morph-to-normalized-request? request)
     (check-path-morph-target visual 'morph-to-normalized)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-normalized-request-destination request))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source destination))
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-aligned-request? request)
     (check-path-morph-target visual 'morph-to-aligned)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-aligned-request-destination request))
     (define aligned-destination
       (path-geometry-align-for-morph
        source
        destination
        #:allow-reverse?
        (morph-to-aligned-request-allow-reverse? request)
        #:sample-count
        (morph-to-aligned-request-sample-count request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source aligned-destination))
     ;; Interior frames use the aligned traversal, while progress one still
     ;; installs the exact destination representation requested by the caller.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-open-aligned-request? request)
     (check-path-morph-target visual 'morph-to-open-aligned)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-open-aligned-request-destination request))
     (define aligned-destination
       (path-geometry-align-open-for-morph
        source
        destination
        #:allow-reverse?
        (morph-to-open-aligned-request-allow-reverse? request)
        #:sample-count
        (morph-to-open-aligned-request-sample-count request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source aligned-destination))
     ;; Direction alignment is interior correspondence only. Progress one still
     ;; installs the exact destination representation requested by the caller.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-open-compound-aligned-request? request)
     (check-path-morph-target visual 'morph-to-open-compound-aligned)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-open-compound-aligned-request-destination request))
     (define aligned-destination
       (path-geometry-align-open-compound-for-morph
        source
        destination
        #:allow-reverse?
        (morph-to-open-compound-aligned-request-allow-reverse? request)
        #:sample-count
        (morph-to-open-compound-aligned-request-sample-count request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source aligned-destination))
     ;; Global open-subpath pairing and direction selection are interior
     ;; correspondence only. Progress one installs the exact requested storage.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-mixed-compound-aligned-request? request)
     (check-path-morph-target visual 'morph-to-mixed-compound-aligned)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-mixed-compound-aligned-request-destination request))
     (define aligned-destination
       (path-geometry-align-mixed-compound-for-morph
        source
        destination
        #:allow-reverse?
        (morph-to-mixed-compound-aligned-request-allow-reverse? request)
        #:sample-count
        (morph-to-mixed-compound-aligned-request-sample-count request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source aligned-destination))
     ;; Topology-class pairing and per-pair direction/phase alignment are
     ;; interior correspondence only. Progress one installs exact requested
     ;; destination storage and subpath ordering.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-topology-changing-request? request)
     (check-path-morph-target visual 'morph-to-topology-changing)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-topology-changing-request-destination request))
     (define-values (prepared-source prepared-destination)
       (path-geometry-prepare-topology-changing-morph
        source
        destination
        #:allow-reverse?
        (morph-to-topology-changing-request-allow-reverse? request)
        #:sample-count
        (morph-to-topology-changing-request-sample-count request)
        #:birth-anchor
        (morph-to-topology-changing-request-birth-anchor request)
        #:death-anchor
        (morph-to-topology-changing-request-death-anchor request)
        #:birth-anchor-map
        (morph-to-topology-changing-request-birth-anchor-map request)
        #:death-anchor-map
        (morph-to-topology-changing-request-death-anchor-map request)
        #:birth-penalty
        (morph-to-topology-changing-request-birth-penalty request)
        #:death-penalty
        (morph-to-topology-changing-request-death-penalty request)
        #:birth-penalty-map
        (morph-to-topology-changing-request-birth-penalty-map request)
        #:death-penalty-map
        (morph-to-topology-changing-request-death-penalty-map request)
        #:match-penalty-map
        (morph-to-topology-changing-request-match-penalty-map request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph
        prepared-source
        prepared-destination))
     ;; Birth/death seeds and correspondence are interior normalization only.
     ;; Exact caller representations remain structural clip endpoints.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-compound-aligned-request? request)
     (check-path-morph-target visual 'morph-to-compound-aligned)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-compound-aligned-request-destination request))
     (define aligned-destination
       (path-geometry-align-compound-for-morph
        source
        destination
        #:allow-reverse?
        (morph-to-compound-aligned-request-allow-reverse? request)
        #:sample-count
        (morph-to-compound-aligned-request-sample-count request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source aligned-destination))
     ;; Pairing and per-loop alignment are interior correspondence only. The
     ;; exact caller-requested destination storage is installed at progress one.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(transform-formula-parts-request? request)
     (check-formula-transform-target visual)
     (formula-parts-transform-animation
      target-id
      (make-formula-transition-plan
       visual
       (transform-formula-parts-request-correspondence request)))]
    [(create-request? request)
     (define complete-visual
       (create-request-visual request))
     (check-path-animation-target complete-visual 'create)
     (path-reveal-animation target-id
                            (path-visual-path complete-visual)
                            0
                            1
                            #f)]
    [(uncreate-request? request)
     (check-path-animation-target visual 'uncreate)
     (path-reveal-animation target-id
                            (path-visual-path visual)
                            1
                            0
                            #t)]
    [else
     (raise-argument-error
      'compile-animation-request
      "animation request"
      request)])]))

; check-request-component-conflicts : (listof animation-request?) -> void?
;;   Rejects duplicate updates to one animation component in a play clip.
(define (check-request-component-conflicts requests)
  (define keys
    (for*/list ([request (in-list requests)]
                [component
                 (in-list (animation-request-components request))])
      (cons (animation-request-target-id request)
            component)))
  (define duplicate-key
    (find-duplicate-key keys))
  (when duplicate-key
    (raise-arguments-error
     'scene-play
     "two simultaneous animations target the same animation component"
     "target-id" (car duplicate-key)
     "component" (cdr duplicate-key))))

; find-duplicate-key : list? -> any/c
;;   Returns the first duplicate key or #f when all keys are distinct.
(define (find-duplicate-key keys)
  (let loop ([remaining keys]
             [seen (hash)])
    (cond
      [(null? remaining)
       #f]
      [(hash-has-key? seen (car remaining))
       (car remaining)]
      [else
       (loop (cdr remaining)
             (hash-set seen (car remaining) #t))])))

; animation-request? : any/c -> boolean?
;;   Reports whether value is a supported uncompiled animation request.
(define (animation-request? value)
  (or (value-to-request? value)
      (move-to-request? value)
      (move-along-path-request? value)
      (orient-along-path-request? value)
      (rotate-to-request? value)
      (rotate-by-request? value)
      (scale-to-request? value)
      (scale-by-request? value)
      (stroke-width-to-request? value)
      (fill-color-to-request? value)
      (stroke-color-to-request? value)
      (fade-to-request? value)
      (fade-in-request? value)
      (fade-out-request? value)
      (morph-to-request? value)
      (morph-to-normalized-request? value)
      (morph-to-aligned-request? value)
      (morph-to-open-aligned-request? value)
      (morph-to-open-compound-aligned-request? value)
      (morph-to-mixed-compound-aligned-request? value)
      (morph-to-topology-changing-request? value)
      (morph-to-compound-aligned-request? value)
      (transform-formula-parts-request? value)
      (create-request? value)
      (uncreate-request? value)))

; animation-request-target-id : animation-request? -> symbol?
;;   Returns the stable target id of request.
(define (animation-request-target-id request)
  (cond
    [(value-to-request? request)
     (value-to-request-target-id request)]
    [(move-to-request? request)
     (move-to-request-target-id request)]
    [(move-along-path-request? request)
     (move-along-path-request-target-id request)]
    [(orient-along-path-request? request)
     (orient-along-path-request-target-id request)]
    [(rotate-to-request? request)
     (rotate-to-request-target-id request)]
    [(rotate-by-request? request)
     (rotate-by-request-target-id request)]
    [(scale-to-request? request)
     (scale-to-request-target-id request)]
    [(scale-by-request? request)
     (scale-by-request-target-id request)]
    [(stroke-width-to-request? request)
     (stroke-width-to-request-target-id request)]
    [(fill-color-to-request? request)
     (fill-color-to-request-target-id request)]
    [(stroke-color-to-request? request)
     (stroke-color-to-request-target-id request)]
    [(fade-to-request? request)
     (fade-to-request-target-id request)]
    [(fade-in-request? request)
     (visual-id (fade-in-request-visual request))]
    [(fade-out-request? request)
     (fade-out-request-target-id request)]
    [(morph-to-request? request)
     (morph-to-request-target-id request)]
    [(morph-to-normalized-request? request)
     (morph-to-normalized-request-target-id request)]
    [(morph-to-aligned-request? request)
     (morph-to-aligned-request-target-id request)]
    [(morph-to-open-aligned-request? request)
     (morph-to-open-aligned-request-target-id request)]
    [(morph-to-open-compound-aligned-request? request)
     (morph-to-open-compound-aligned-request-target-id request)]
    [(morph-to-mixed-compound-aligned-request? request)
     (morph-to-mixed-compound-aligned-request-target-id request)]
    [(morph-to-topology-changing-request? request)
     (morph-to-topology-changing-request-target-id request)]
    [(morph-to-compound-aligned-request? request)
     (morph-to-compound-aligned-request-target-id request)]
    [(transform-formula-parts-request? request)
     (visual-id
      (formula-correspondence-source
       (transform-formula-parts-request-correspondence request)))]
    [(create-request? request)
     (visual-id (create-request-visual request))]
    [(uncreate-request? request)
     (uncreate-request-target-id request)]
    [else
     (raise-argument-error
      'animation-request-target-id
      "animation request"
      request)]))

; animation-request-components : animation-request? -> (listof symbol?)
;;   Returns every animation component changed by request.
(define (animation-request-components request)
  (cond
    [(value-to-request? request)
     '(scalar-value)]
    [(or (move-to-request? request)
         (move-along-path-request? request))
     '(translation)]
    [(or (orient-along-path-request? request)
         (rotate-to-request? request)
         (rotate-by-request? request))
     '(rotation)]
    [(or (scale-to-request? request)
         (scale-by-request? request))
     '(scale)]
    [(stroke-width-to-request? request)
     '(stroke-width)]
    [(fill-color-to-request? request)
     '(fill-color)]
    [(stroke-color-to-request? request)
     '(stroke-color)]
    [(fade-to-request? request)
     '(opacity)]
    [(or (fade-in-request? request)
         (fade-out-request? request))
     '(opacity presence)]
    [(or (morph-to-request? request)
         (morph-to-normalized-request? request)
         (morph-to-aligned-request? request)
         (morph-to-open-aligned-request? request)
         (morph-to-open-compound-aligned-request? request)
         (morph-to-mixed-compound-aligned-request? request)
         (morph-to-topology-changing-request? request)
         (morph-to-compound-aligned-request? request))
     '(path-geometry)]
    [(transform-formula-parts-request? request)
     '(formula-parts presence)]
    [(or (create-request? request)
         (uncreate-request? request))
     '(path-geometry presence)]
    [else
     (raise-argument-error
      'animation-request-components
      "animation request"
      request)]))

;;;
;;; Sampling
;;;

; apply-compiled-animations : scene-state?
;                             (listof compiled-animation?)
;                             finite-real?
;                             (-> finite-real? finite-real?)
;                             -> scene-state?
;;   Samples all compiled animations at progress using easing.
(define (apply-compiled-animations state animations progress easing)
  (unless (scene-state? state)
    (raise-argument-error
     'apply-compiled-animations
     "scene-state?"
     state))
  (unless (and (list? animations)
               (andmap compiled-animation? animations))
    (raise-argument-error
     'apply-compiled-animations
     "list of compiled animations"
     animations))
  (unless (finite-real? progress)
    (raise-argument-error
     'apply-compiled-animations
     "finite real?"
     progress))
  (unless (and (procedure? easing)
               (procedure-arity-includes? easing 1))
    (raise-argument-error
     'apply-compiled-animations
     "(procedure-arity-includes/c 1)"
     easing))
  (define eased-progress
    (clamp-unit (easing (clamp-unit progress))))
  (for/fold ([sampled-state state])
            ([animation (in-list animations)])
    (apply-compiled-animation sampled-state
                              animation
                              eased-progress)))

; compiled-animation? : any/c -> boolean?
;;   Reports whether value is a supported compiled animation.
(define (compiled-animation? value)
  (or (scalar-value-animation? value)
      (translation-animation? value)
      (path-motion-animation? value)
      (path-orientation-animation? value)
      (rotation-animation? value)
      (scaling-animation? value)
      (stroke-width-animation? value)
      (fill-color-animation? value)
      (stroke-color-animation? value)
      (opacity-animation? value)
      (path-morph-animation? value)
      (normalized-path-morph-animation? value)
      (formula-parts-transform-animation? value)
      (path-reveal-animation? value)))

; apply-compiled-animation : scene-state? compiled-animation? finite-real?
;                            -> scene-state?
;;   Applies one compiled animation component at progress.
(define (apply-compiled-animation state animation progress)
  (cond
    [(scalar-value-animation? animation)
     (apply-scalar-value-animation state animation progress)]
    [(translation-animation? animation)
     (apply-translation-animation state animation progress)]
    [(path-motion-animation? animation)
     (apply-path-motion-animation state animation progress)]
    [(path-orientation-animation? animation)
     (apply-path-orientation-animation state animation progress)]
    [(rotation-animation? animation)
     (apply-rotation-animation state animation progress)]
    [(scaling-animation? animation)
     (apply-scaling-animation state animation progress)]
    [(stroke-width-animation? animation)
     (apply-stroke-width-animation state animation progress)]
    [(fill-color-animation? animation)
     (apply-fill-color-animation state animation progress)]
    [(stroke-color-animation? animation)
     (apply-stroke-color-animation state animation progress)]
    [(opacity-animation? animation)
     (apply-opacity-animation state animation progress)]
    [(path-morph-animation? animation)
     (apply-path-morph-animation state animation progress)]
    [(normalized-path-morph-animation? animation)
     (apply-normalized-path-morph-animation state animation progress)]
    [(formula-parts-transform-animation? animation)
     (apply-formula-parts-transform-animation state animation progress)]
    [(path-reveal-animation? animation)
     (apply-path-reveal-animation state animation progress)]
    [else
     (raise-argument-error
      'apply-compiled-animation
      "compiled animation"
      animation)]))

; apply-scalar-value-animation : scene-state? scalar-value-animation? finite-real?
;                                -> scene-state?
;;   Samples one named semantic value while preserving exact endpoints.
(define (apply-scalar-value-animation state animation progress)
  (define value
    (interpolate-value
     (scalar-value-animation-from animation)
     (scalar-value-animation-to animation)
     progress))
  (scene-state-value-set
   state
   (scalar-value-animation-target-id animation)
   value))

; apply-translation-animation : scene-state? translation-animation?
;                               finite-real? -> scene-state?
;;   Applies one compiled translation at progress.
(define (apply-translation-animation state animation progress)
  (define id
    (translation-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (scene-state-update
   state
   id
   (visual-with-position
    visual
    (vec2-lerp (translation-animation-from animation)
               (translation-animation-to animation)
               progress))))

; apply-path-motion-animation : scene-state? path-motion-animation?
;                               finite-real? -> scene-state?
;;   Places one Visual at the requested total arc-length fraction.
(define (apply-path-motion-animation state animation progress)
  (define id
    (path-motion-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define fraction
    (real-lerp (path-motion-animation-start animation)
               (path-motion-animation-end animation)
               progress))
  (scene-state-update
   state
   id
   (visual-with-position
    visual
    (path-motion-position-at
     (path-motion-animation-path animation)
     fraction
     (path-motion-animation-start animation)
     (path-motion-animation-end animation)
     (path-motion-animation-normal-offset animation)))))

; apply-path-orientation-animation : scene-state? path-orientation-animation?
;                                    finite-real? -> scene-state?
;;   Rotates one affine Visual to the route's traversal tangent at progress.
(define (apply-path-orientation-animation state animation progress)
  (define id
    (path-orientation-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define fraction
    (real-lerp (path-orientation-animation-start animation)
               (path-orientation-animation-end animation)
               progress))
  (define tangent
    (path-traversal-tangent-at
     (path-orientation-animation-path animation)
     fraction
     (path-orientation-animation-start animation)
     (path-orientation-animation-end animation)))
  (scene-state-update
   state
   id
   (visual-with-rotation
    visual
    (+ (atan (vec2-y tangent)
             (vec2-x tangent))
       (path-orientation-animation-rotation-offset animation)))))

; path-motion-position-at : path-geometry? finite-real? finite-real?
;                           finite-real? finite-real? -> vec2?
;;   Returns a route point plus one signed normal offset from traversal.
(define (path-motion-position-at path fraction start end normal-offset)
  (define point
    (path-geometry-point-at path fraction))
  (cond
    [(zero? normal-offset)
     point]
    [else
     (define tangent
       (path-traversal-tangent-at path fraction start end))
     (define left-normal
       (vec2 (- (vec2-y tangent))
             (vec2-x tangent)))
     (vec2+ point
            (vec2-scale normal-offset left-normal))]))

; path-traversal-tangent-at : path-geometry? finite-real? finite-real?
;                             finite-real? -> vec2?
;;   Returns a unit tangent pointing in the requested traversal direction.
(define (path-traversal-tangent-at path fraction start end)
  (define tangent
    (path-geometry-tangent-at path fraction))
  (if (< end start)
      (vec2-scale -1 tangent)
      tangent))

; apply-rotation-animation : scene-state? rotation-animation? finite-real?
;                            -> scene-state?
;;   Applies one compiled rotation at progress.
(define (apply-rotation-animation state animation progress)
  (define id
    (rotation-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (scene-state-update
   state
   id
   (visual-with-rotation
    visual
    (real-lerp (rotation-animation-from animation)
               (rotation-animation-to animation)
               progress))))

; apply-scaling-animation : scene-state? scaling-animation? finite-real?
;                           -> scene-state?
;;   Applies one compiled scale at progress.
(define (apply-scaling-animation state animation progress)
  (define id
    (scaling-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (scene-state-update
   state
   id
   (visual-with-scale
    visual
    (vec2-lerp (scaling-animation-from animation)
               (scaling-animation-to animation)
               progress))))

; apply-stroke-width-animation : scene-state? stroke-width-animation?
;                                finite-real? -> scene-state?
;;   Applies one compiled cosmetic stroke-width transition at progress.
(define (apply-stroke-width-animation state animation progress)
  (define id
    (stroke-width-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define stroke-width
    (cond
      [(zero? progress)
       (stroke-width-animation-from animation)]
      [(= progress 1)
       (stroke-width-animation-to animation)]
      [else
       (real-lerp (stroke-width-animation-from animation)
                  (stroke-width-animation-to animation)
                  progress)]))
  (scene-state-update
   state
   id
   (replace-visual-stroke-width
    'scene-sample
    visual
    stroke-width)))

; apply-fill-color-animation : scene-state? fill-color-animation? finite-real?
;                              -> scene-state?
;;   Applies one semantic fill-color transition while preserving exact endpoints.
(define (apply-fill-color-animation state animation progress)
  (define id
    (fill-color-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define color
    (cond
      [(zero? progress)
       (fill-color-animation-from-spec animation)]
      [(= progress 1)
       (fill-color-animation-to-spec animation)]
      [else
       (rgba-color-lerp (fill-color-animation-from-color animation)
                        (fill-color-animation-to-color animation)
                        progress)]))
  (scene-state-update
   state
   id
   (replace-visual-fill-color 'scene-sample visual color)))

; apply-stroke-color-animation : scene-state? stroke-color-animation? finite-real?
;                                -> scene-state?
;;   Applies one semantic stroke-color transition while preserving exact endpoints.
(define (apply-stroke-color-animation state animation progress)
  (define id
    (stroke-color-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define color
    (cond
      [(zero? progress)
       (stroke-color-animation-from-spec animation)]
      [(= progress 1)
       (stroke-color-animation-to-spec animation)]
      [else
       (rgba-color-lerp (stroke-color-animation-from-color animation)
                        (stroke-color-animation-to-color animation)
                        progress)]))
  (scene-state-update
   state
   id
   (replace-visual-stroke-color 'scene-sample visual color)))

; apply-opacity-animation : scene-state? opacity-animation? finite-real?
;                           -> scene-state?
;;   Applies one compiled global-opacity transition at progress.
(define (apply-opacity-animation state animation progress)
  (define id
    (opacity-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (scene-state-update
   state
   id
   (replace-visual-opacity
    'scene-sample
    visual
    (real-lerp (opacity-animation-from animation)
               (opacity-animation-to animation)
               progress))))

; apply-path-morph-animation : scene-state? path-morph-animation?
;                              finite-real? -> scene-state?
;;   Applies one compatible local path interpolation at progress.
(define (apply-path-morph-animation state animation progress)
  (define id
    (path-morph-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (scene-state-update
   state
   id
   (path-visual-with-path
    visual
    (path-geometry-lerp
     (path-morph-animation-from animation)
     (path-morph-animation-to animation)
     progress))))

; apply-normalized-path-morph-animation : scene-state?
;                                          normalized-path-morph-animation?
;                                          finite-real?
;                                          -> scene-state?
;;   Applies a normalized path interpolation while preserving exact endpoints.
(define (apply-normalized-path-morph-animation state animation progress)
  (define id
    (normalized-path-morph-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define path
    (cond
      [(zero? progress)
       (normalized-path-morph-animation-source animation)]
      [(= progress 1)
       (normalized-path-morph-animation-destination animation)]
      [else
       (path-geometry-lerp
        (normalized-path-morph-animation-normalized-source animation)
        (normalized-path-morph-animation-normalized-destination animation)
        progress)]))
  (scene-state-update
   state
   id
   (path-visual-with-path visual path)))

; apply-formula-parts-transform-animation : scene-state?
;                                            formula-parts-transform-animation?
;                                            finite-real?
;                                            -> scene-state?
;;   Replaces assembly parts with exact endpoints or sampled transition layers.
(define (apply-formula-parts-transform-animation state animation progress)
  (define id
    (formula-parts-transform-animation-target-id animation))
  (define assembly
    (scene-state-ref state id))
  (check-formula-transform-target assembly)
  (scene-state-update
   state
   id
   (formula-assembly-visual-with-parts
    assembly
    (formula-transition-plan-sample-parts
     (formula-parts-transform-animation-plan animation)
     progress))))

; apply-path-reveal-animation : scene-state? path-reveal-animation?
;                               finite-real? -> scene-state?
;;   Applies one compiled path-prefix reveal at progress.
(define (apply-path-reveal-animation state animation progress)
  (define id
    (path-reveal-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define visible-fraction
    (real-lerp (path-reveal-animation-from animation)
               (path-reveal-animation-to animation)
               progress))
  (scene-state-update
   state
   id
   (path-visual-with-path
    visual
    (path-geometry-partial
     (path-reveal-animation-path animation)
     0
     visible-fraction))))

; complete-compiled-animations : scene-state?
;                                (listof compiled-animation?)
;                                (-> finite-real? finite-real?)
;                                -> scene-state?
;;   Produces the structural endpoint after all animations complete.
(define (complete-compiled-animations state animations easing)
  (define sampled-state
    (apply-compiled-animations state animations 1 easing))
  (for/fold ([completed-state sampled-state])
            ([animation (in-list animations)])
    (finalize-compiled-animation completed-state animation)))

; finalize-compiled-animation : scene-state? compiled-animation? -> scene-state?
;;   Applies only the structural endpoint rule of one already-sampled animation.
;;   SCENE-AN uses this after all component values at a local boundary have been
;;   sampled, preserving historical simultaneous endpoint ordering.
(define (finalize-compiled-animation state animation)
  (unless (scene-state? state)
    (raise-argument-error
     'finalize-compiled-animation
     "scene-state?"
     state))
  (unless (compiled-animation? animation)
    (raise-argument-error
     'finalize-compiled-animation
     "compiled animation"
     animation))
  (cond
    [(and (opacity-animation? animation)
          (opacity-animation-remove-at-end? animation))
     (scene-state-remove
      state
      (opacity-animation-target-id animation))]
    [(and (opacity-animation? animation)
          (opacity-animation-force-to-at-end? animation))
     (define id
       (opacity-animation-target-id animation))
     (define visual
       (scene-state-ref state id))
     (scene-state-update
      state
      id
      (replace-visual-opacity
       'scene-play
       visual
       (opacity-animation-to animation)))]
    [(formula-parts-transform-animation? animation)
     (define id
       (formula-parts-transform-animation-target-id animation))
     (define assembly
       (scene-state-ref state id))
     (scene-state-update
      state
      id
      (formula-assembly-visual-with-parts
       assembly
       (formula-transition-plan-destination-parts
        (formula-parts-transform-animation-plan animation))))]
    [(and (path-reveal-animation? animation)
          (path-reveal-animation-remove-at-end? animation))
     (scene-state-remove
      state
      (path-reveal-animation-target-id animation))]
    [(path-reveal-animation? animation)
     (define id
       (path-reveal-animation-target-id animation))
     (define visual
       (scene-state-ref state id))
     (scene-state-update
      state
      id
      (path-visual-with-path
       visual
       (path-reveal-animation-path animation)))]
    [else
     state]))

; clamp-unit : any/c -> real?
;;   Validates value and clamps it to the closed unit interval.
(define (clamp-unit value)
  (unless (finite-real? value)
    (raise-arguments-error
     'animation-easing
     "an easing function must produce a finite real number"
     "result" value))
  (min 1 (max 0 value)))


;;;
;;; Validation
;;;

; check-path-motion-fraction : symbol? string? any/c -> void?
;;   Raises unless value is a finite real in the closed unit interval.
(define (check-path-motion-fraction who field-name value)
  (unless (and (finite-real? value)
               (<= 0 value 1))
    (raise-arguments-error
     who
     "path fractions must be finite reals in the closed unit interval"
     field-name value)))

; normalize-path-animation-source : symbol? any/c
;                                   -> (or/c path-geometry? symbol?)
;;   Converts one public path argument to immutable request data.
(define (normalize-path-animation-source who path)
  (cond
    [(path-geometry? path)
     path]
    [(path-visual? path)
     (visual-id path)]
    [(derived-visual? path)
     (visual-id path)]
    [(symbol? path)
     path]
    [else
     (raise-argument-error
      who
      "(or/c path-geometry? path-visual? derived-visual? symbol?)"
      path)]))

; resolve-path-animation-route : scene-state? visual?
;                                (or/c path-geometry? symbol?) symbol?
;                                finite-real? finite-real?
;                                -> path-geometry?
;;   Resolves and validates one continuous route in target coordinates.
(define (resolve-path-animation-route state target source operation start end)
  (define operation-name
    (symbol->string operation))
  (define path
    (cond
      [(path-geometry? source)
       source]
      [(symbol? source)
       (unless (scene-state-has? state source)
         (raise-arguments-error
          'scene-play
          (string-append operation-name
                         " requires its path Visual to be present at clip start")
          "path-visual-id" source))
       (define path-visual-value
         (scene-state-resolved-ref state source))
       (unless (path-visual? path-visual-value)
         (raise-arguments-error
          'scene-play
          (string-append operation-name " requires a path Visual route")
          "path-visual-id" source
          "visual" path-visual-value))
       (when (frame-space-visual? target)
         (raise-arguments-error
          'scene-play
          "a world-space path Visual cannot drive a frame-space target"
          "operation" operation
          "target-id" (visual-id target)
          "path-visual-id" source))
       (path-geometry-map-points
        (path-visual-path path-visual-value)
        (lambda (point)
          (affine-transform-apply-point
           (visual-transform path-visual-value)
           point)))]
      [else
       (raise-argument-error
        'resolve-path-animation-route
        "(or/c path-geometry? symbol?)"
        source)]))
  (check-path-animation-route path operation start end)
  path)

; check-path-animation-route : path-geometry? symbol? finite-real? finite-real?
;                              -> void?
;;   Requires one finite, positive-length, continuous subpath.
(define (check-path-animation-route path operation start end)
  (define operation-name
    (symbol->string operation))
  (define total-length
    (path-geometry-length path))
  (unless (and (finite-real? total-length)
               (positive? total-length))
    (raise-arguments-error
     'scene-play
     (string-append operation-name " requires a positive finite route length")
     "path-length" total-length
     "path" path))
  (define positive-subpath-count
    (for/sum ([subpath (in-list (path-geometry-subpaths path))])
      (if (positive? (path-subpath-length subpath)) 1 0)))
  (unless (= positive-subpath-count 1)
    (raise-arguments-error
     'scene-play
     (string-append operation-name
                    " requires one continuous positive-length subpath")
     "positive-subpath-count" positive-subpath-count
     "path" path))
  ;; Evaluate both requested endpoints now so transformed overflow or malformed
  ;; internal path data is rejected during clip compilation rather than sampling.
  (path-geometry-point-at path start)
  (path-geometry-point-at path end)
  (void))

; check-animation-scale : symbol? any/c -> void?
;;   Raises an argument error unless scale is positive and finite.
(define (check-animation-scale who scale)
  (unless (scale-factor? scale)
    (raise-argument-error
     who
     "positive finite real or vec2 with positive components"
     scale)))

; check-affine-animation-target : visual? symbol? -> void?
;;   Raises an error unless visual supports the requested affine component.
(define (check-affine-animation-target visual component)
  (unless (affine-visual? visual)
    (raise-arguments-error
     'scene-play
     "rotation and scaling require an affine Visual"
     "visual-id" (visual-id visual)
     "component" component
     "visual" visual)))


; check-scale-animation-endpoint : affine-visual? vec2? -> void?
;;   Checks that an affine Visual accepts a requested scale endpoint.
(define (check-scale-animation-endpoint visual scale)
  (define id
    (visual-id visual))
  (define result
    (visual-with-scale visual scale))
  (unless (and (visual? result)
               (affine-visual? result))
    (raise-arguments-error
     'scene-play
     "visual-with-scale must return an affine Visual"
     "visual-id" id
     "result" result))
  (unless (eq? (visual-id result) id)
    (raise-arguments-error
     'scene-play
     "visual-with-scale must preserve Visual identity"
     "expected-id" id
     "result-id" (visual-id result)))
  (unless (equal? (visual-scale result) scale)
    (raise-arguments-error
     'scene-play
     "visual-with-scale must install the requested scale"
     "visual-id" id
     "requested-scale" scale
     "result-scale" (visual-scale result)))
  (void))

; check-animation-opacity : symbol? any/c -> void?
;;   Raises an argument error unless opacity is in the closed unit interval.
(define (check-animation-opacity who opacity)
  (unless (opacity? opacity)
    (raise-argument-error
     who
     "finite real in [0, 1]"
     opacity)))

; check-animation-stroke-width : symbol? any/c -> void?
;;   Raises an argument error unless width is nonnegative and finite.
(define (check-animation-stroke-width who stroke-width)
  (unless (stroke-width? stroke-width)
    (raise-argument-error
     who
     "nonnegative finite real?"
     stroke-width)))

; check-stroke-width-request-target : symbol? any/c -> void?
;;   Validates a public stroke-width animation target argument.
(define (check-stroke-width-request-target who target)
  (unless (or (symbol? target)
              (and (visual? target)
                   (stroke-width-visual? target)))
    (raise-argument-error
     who
     "(or/c symbol? (and/c visual? stroke-width-visual?))"
     target))
  (when (and (visual? target)
             (stroke-width-visual? target))
    (checked-visual-stroke-width who target)))

; check-stroke-width-animation-target : visual? symbol? -> void?
;;   Raises an error unless visual supports valid semantic stroke width.
(define (check-stroke-width-animation-target visual operation)
  (unless (stroke-width-visual? visual)
    (raise-arguments-error
     'scene-play
     "stroke-width animation requires a stroke-width Visual"
     "visual-id" (visual-id visual)
     "operation" operation
     "visual" visual))
  (checked-visual-stroke-width 'scene-play visual))

; checked-visual-stroke-width : symbol? stroke-width-visual? -> stroke-width?
;;   Returns visual stroke width after checking the protocol result.
(define (checked-visual-stroke-width who visual)
  (define stroke-width
    (visual-stroke-width visual))
  (unless (stroke-width? stroke-width)
    (raise-arguments-error
     who
     "a stroke-width Visual must return a nonnegative finite real"
     "visual" visual
     "stroke-width" stroke-width))
  stroke-width)

; replace-visual-stroke-width : symbol? stroke-width-visual? stroke-width?
;                               -> stroke-width-visual?
;;   Replaces stroke width and validates the resulting Visual protocol value.
(define (replace-visual-stroke-width who visual stroke-width)
  (check-animation-stroke-width who stroke-width)
  (define id
    (visual-id visual))
  (define result
    (visual-with-stroke-width visual stroke-width))
  (unless (and (visual? result)
               (stroke-width-visual? result))
    (raise-arguments-error
     who
     "visual-with-stroke-width must return a stroke-width Visual"
     "visual-id" id
     "result" result))
  (unless (eq? (visual-id result) id)
    (raise-arguments-error
     who
     "visual-with-stroke-width must preserve Visual identity"
     "expected-id" id
     "result-id" (visual-id result)))
  (define result-stroke-width
    (checked-visual-stroke-width who result))
  ;; Use equal? rather than numeric = here. The protocol promises to install
  ;; the requested semantic endpoint exactly, including exact/inexact numeric
  ;; representation. A custom setter that silently turns exact 7 into 7.0 must
  ;; therefore be rejected even though the two values are numerically equal.
  (unless (equal? result-stroke-width stroke-width)
    (raise-arguments-error
     who
     "visual-with-stroke-width must install the requested stroke width exactly"
     "requested-stroke-width" stroke-width
     "result-stroke-width" result-stroke-width))
  result)

; check-animation-color-spec : symbol? any/c -> void?
;;   Raises an argument error unless color is a supported semantic color spec.
(define (check-animation-color-spec who color)
  (unless (color-spec? color)
    (raise-argument-error who "color-spec?" color)))

; check-fill-color-request-target : symbol? any/c -> void?
;;   Validates a public fill-color animation target argument.
(define (check-fill-color-request-target who target)
  (unless (or (symbol? target)
              (and (visual? target)
                   (fill-color-visual? target)))
    (raise-argument-error
     who
     "(or/c symbol? (and/c visual? fill-color-visual?))"
     target))
  (when (and (visual? target)
             (fill-color-visual? target))
    (checked-visual-fill-color who target)))

; check-stroke-color-request-target : symbol? any/c -> void?
;;   Validates a public stroke-color animation target argument.
(define (check-stroke-color-request-target who target)
  (unless (or (symbol? target)
              (and (visual? target)
                   (stroke-color-visual? target)))
    (raise-argument-error
     who
     "(or/c symbol? (and/c visual? stroke-color-visual?))"
     target))
  (when (and (visual? target)
             (stroke-color-visual? target))
    (checked-visual-stroke-color who target)))

; check-fill-color-animation-target : visual? symbol? -> void?
(define (check-fill-color-animation-target visual operation)
  (unless (fill-color-visual? visual)
    (raise-arguments-error
     'scene-play
     "fill-color animation requires a fill-color Visual"
     "visual-id" (visual-id visual)
     "operation" operation
     "visual" visual))
  (checked-visual-fill-color 'scene-play visual))

; check-stroke-color-animation-target : visual? symbol? -> void?
(define (check-stroke-color-animation-target visual operation)
  (unless (stroke-color-visual? visual)
    (raise-arguments-error
     'scene-play
     "stroke-color animation requires a stroke-color Visual"
     "visual-id" (visual-id visual)
     "operation" operation
     "visual" visual))
  (checked-visual-stroke-color 'scene-play visual))

; checked-visual-fill-color : symbol? fill-color-visual? -> color-spec?
(define (checked-visual-fill-color who visual)
  (define color
    (visual-fill-color visual))
  (unless (color-spec? color)
    (raise-arguments-error
     who
     "a fill-color Visual must return a supported color specification"
     "visual" visual
     "fill-color" color))
  color)

; checked-visual-stroke-color : symbol? stroke-color-visual? -> color-spec?
(define (checked-visual-stroke-color who visual)
  (define color
    (visual-stroke-color visual))
  (unless (color-spec? color)
    (raise-arguments-error
     who
     "a stroke-color Visual must return a supported color specification"
     "visual" visual
     "stroke-color" color))
  color)

; replace-visual-fill-color : symbol? fill-color-visual? color-spec?
;                             -> fill-color-visual?
(define (replace-visual-fill-color who visual color)
  (check-animation-color-spec who color)
  (define id (visual-id visual))
  (define result (visual-with-fill-color visual color))
  (unless (and (visual? result) (fill-color-visual? result))
    (raise-arguments-error
     who
     "visual-with-fill-color must return a fill-color Visual"
     "visual-id" id
     "result" result))
  (unless (eq? (visual-id result) id)
    (raise-arguments-error
     who
     "visual-with-fill-color must preserve Visual identity"
     "expected-id" id
     "result-id" (visual-id result)))
  (define result-color (checked-visual-fill-color who result))
  (unless (equal? result-color color)
    (raise-arguments-error
     who
     "visual-with-fill-color must install the requested fill color exactly"
     "requested-fill-color" color
     "result-fill-color" result-color))
  result)

; replace-visual-stroke-color : symbol? stroke-color-visual? color-spec?
;                               -> stroke-color-visual?
(define (replace-visual-stroke-color who visual color)
  (check-animation-color-spec who color)
  (define id (visual-id visual))
  (define result (visual-with-stroke-color visual color))
  (unless (and (visual? result) (stroke-color-visual? result))
    (raise-arguments-error
     who
     "visual-with-stroke-color must return a stroke-color Visual"
     "visual-id" id
     "result" result))
  (unless (eq? (visual-id result) id)
    (raise-arguments-error
     who
     "visual-with-stroke-color must preserve Visual identity"
     "expected-id" id
     "result-id" (visual-id result)))
  (define result-color (checked-visual-stroke-color who result))
  (unless (equal? result-color color)
    (raise-arguments-error
     who
     "visual-with-stroke-color must install the requested stroke color exactly"
     "requested-stroke-color" color
     "result-stroke-color" result-color))
  result)

; check-opacity-request-target : symbol? any/c -> void?
;;   Validates a public opacity-animation target argument.
(define (check-opacity-request-target who target)
  (unless (or (symbol? target)
              (and (visual? target)
                   (opacity-visual? target)))
    (raise-argument-error
     who
     "(or/c symbol? (and/c visual? opacity-visual?))"
     target))
  (when (and (visual? target)
             (opacity-visual? target))
    (checked-visual-opacity who target)))

; check-opacity-visual-value : symbol? any/c -> void?
;;   Validates a complete Visual supplied to an opacity introduction request.
(define (check-opacity-visual-value who visual)
  (unless (and (visual? visual)
               (opacity-visual? visual))
    (raise-argument-error
     who
     "(and/c visual? opacity-visual?)"
     visual))
  (visual-target-id visual who)
  (checked-visual-opacity who visual))

; check-opacity-animation-target : visual? symbol? -> void?
;;   Raises an error unless visual supports valid semantic opacity.
(define (check-opacity-animation-target visual operation)
  (unless (opacity-visual? visual)
    (raise-arguments-error
     'scene-play
     "opacity animation requires an opacity Visual"
     "visual-id" (visual-id visual)
     "operation" operation
     "visual" visual))
  (checked-visual-opacity 'scene-play visual))

; checked-visual-opacity : symbol? (and/c visual? opacity-visual?) -> opacity?
;;   Returns visual opacity after checking the protocol result.
(define (checked-visual-opacity who visual)
  (define opacity
    (visual-opacity visual))
  (unless (opacity? opacity)
    (raise-arguments-error
     who
     "an opacity Visual must return a finite real in [0, 1]"
     "visual" visual
     "opacity" opacity))
  opacity)

; replace-visual-opacity : symbol? (and/c visual? opacity-visual?) opacity?
;                          -> (and/c visual? opacity-visual?)
;;   Replaces opacity and validates the resulting Visual protocol value.
(define (replace-visual-opacity who visual opacity)
  (check-animation-opacity who opacity)
  (define id
    (visual-id visual))
  (define result
    (visual-with-opacity visual opacity))
  (unless (and (visual? result)
               (opacity-visual? result))
    (raise-arguments-error
     who
     "visual-with-opacity must return an opacity Visual"
     "visual-id" id
     "result" result))
  (unless (eq? (visual-id result) id)
    (raise-arguments-error
     who
     "visual-with-opacity must preserve Visual identity"
     "expected-id" id
     "result-id" (visual-id result)))
  (define result-opacity
    (checked-visual-opacity who result))
  (unless (= result-opacity opacity)
    (raise-arguments-error
     who
     "visual-with-opacity must install the requested opacity"
     "requested-opacity" opacity
     "result-opacity" result-opacity))
  result)

; check-absent-introduction-target : scene-state? symbol? symbol? -> void?
;;   Raises an error when a structural introduction target is already present.
(define (check-absent-introduction-target state id operation)
  (when (scene-state-has? state id)
    (raise-arguments-error
     'scene-play
     "an introduction request requires a Visual identity absent from the scene"
     "visual-id" id
     "operation" operation)))

; check-formula-transform-target : visual? -> void?
;;   Raises an error unless visual is a semantic formula assembly.
(define (check-formula-transform-target visual)
  (unless (formula-assembly-visual? visual)
    (raise-arguments-error
     'scene-play
     "transform-formula-parts requires a formula assembly"
     "visual-id" (visual-id visual)
     "visual" visual)))

; check-path-morph-request-arguments : symbol? any/c any/c -> void?
;;   Validates one public path-morph request constructor call.
(define (check-path-morph-request-arguments who target destination)
  (unless (or (symbol? target)
              (path-visual? target))
    (raise-argument-error
     who
     "(or/c path-visual? symbol?)"
     target))
  (unless (path-geometry? destination)
    (raise-argument-error who "path-geometry?" destination)))

; check-path-morph-target : visual? symbol? -> void?
;;   Raises an error unless visual is a built-in semantic path Visual.
(define (check-path-morph-target visual operation)
  (unless (path-visual? visual)
    (raise-arguments-error
     'scene-play
     (format "~a requires a path Visual" operation)
     "visual-id" (visual-id visual)
     "visual" visual)))

; check-path-animation-target : visual? symbol? -> void?
;;   Raises an error unless visual is a built-in semantic path Visual.
(define (check-path-animation-target visual operation)
  (unless (path-visual? visual)
    (raise-arguments-error
     'scene-play
     "Create and Uncreate require a path Visual"
     "visual-id" (visual-id visual)
     "operation" operation
     "visual" visual))
  (define path-length
    (path-geometry-length (path-visual-path visual)))
  (unless (finite-real? path-length)
    (raise-arguments-error
     'scene-play
     "Create and Uncreate require a finite path length"
     "visual-id" (visual-id visual)
     "operation" operation
     "path-length" path-length)))
