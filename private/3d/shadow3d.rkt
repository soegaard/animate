#lang racket/base

;;;
;;; Immutable shadow descriptors
;;;

;; V7 deliberately defines only renderer-neutral shadow intent.  It is safe to
;; attach to directional and spot lights now; V8/V9 are responsible for turning
;; that intent into software/GPU depth maps.

(require "../geometry.rkt"
         "bounds3.rkt")

(provide shadow-settings3d
         shadow-settings3d?
         shadow-bias3d
         shadow-bias3d?
         shadow-bias3d-world-normal-offset
         shadow-bias3d-slope-scale
         shadow-bias3d-constant-depth-offset
         shadow-bias3d-pcf-radius-texels
         shadow-settings3d-bias
         shadow-settings3d-map-size
         shadow-settings3d-depth-bias
         shadow-settings3d-normal-bias
         shadow-settings3d-pcf-radius
         shadow-settings3d-bounds
         shadow-settings3d-near
         shadow-settings3d-far
         shadow-settings3d-prepared-bounds-key
         directional-shadow3d
         directional-shadow3d?
         directional-shadow3d-settings
         spot-shadow3d
         spot-shadow3d?
         spot-shadow3d-settings
         shadow3d?
         shadow3d-kind
         shadow3d-settings
         ;; Renderer-private helpers keep the compatibility path explicit.
         shadow-settings3d-legacy-bias?
         shadow-settings3d-effective-pcf-radius)

;; Shadow-bias3d is the renderer-independent public model.  All distance
;; values are in world units; `slope-scale` is multiplied by a derived world
;; texel size, and the PCF radius is a count of shadow-map texels.  That keeps
;; an author from having to tune a normalized software depth number separately
;; from an OpenGL projection-depth number.
(struct shadow-bias3d-value
  (world-normal-offset slope-scale constant-depth-offset pcf-radius-texels)
  #:transparent)

(define shadow-bias3d? shadow-bias3d-value?)
(define shadow-bias3d-world-normal-offset
  shadow-bias3d-value-world-normal-offset)
(define shadow-bias3d-slope-scale shadow-bias3d-value-slope-scale)
(define shadow-bias3d-constant-depth-offset
  shadow-bias3d-value-constant-depth-offset)
(define shadow-bias3d-pcf-radius-texels
  shadow-bias3d-value-pcf-radius-texels)

(define (shadow-bias3d #:world-normal-offset [world-normal-offset 0]
                       #:slope-scale [slope-scale 0]
                       #:constant-depth-offset [constant-depth-offset 0]
                       #:pcf-radius-texels [pcf-radius-texels 1])
  (for ([value (in-list (list world-normal-offset slope-scale
                              constant-depth-offset))]
        [name (in-list '(world-normal-offset slope-scale
                         constant-depth-offset))])
    (unless (and (finite-real? value) (>= value 0))
      (raise-arguments-error 'shadow-bias3d "nonnegative finite shadow-bias value"
                             "field" name "value" value)))
  (unless (exact-nonnegative-integer? pcf-radius-texels)
    (raise-argument-error 'shadow-bias3d
                          "exact-nonnegative-integer? as #:pcf-radius-texels"
                          pcf-radius-texels))
  (shadow-bias3d-value world-normal-offset slope-scale constant-depth-offset
                        pcf-radius-texels))

(struct shadow-settings3d-value
  (map-size depth-bias normal-bias pcf-radius bias bounds near far prepared-bounds-key)
  #:transparent)

(define shadow-settings3d? shadow-settings3d-value?)
(define shadow-settings3d-map-size shadow-settings3d-value-map-size)
(define shadow-settings3d-depth-bias shadow-settings3d-value-depth-bias)
(define shadow-settings3d-normal-bias shadow-settings3d-value-normal-bias)
(define shadow-settings3d-pcf-radius shadow-settings3d-value-pcf-radius)
(define shadow-settings3d-bias shadow-settings3d-value-bias)
(define shadow-settings3d-bounds shadow-settings3d-value-bounds)
(define shadow-settings3d-near shadow-settings3d-value-near)
(define shadow-settings3d-far shadow-settings3d-value-far)
(define shadow-settings3d-prepared-bounds-key
  shadow-settings3d-value-prepared-bounds-key)

;; `bounds` is an explicit world-space shadow region. #f tells V8 to use a
;; direct current-frame caster fit with a diagnostic; retained map caching can
;; use the named prepared-bound identity without mutable global state.  The
;; original depth/normal/PCF keywords remain so existing authored scenes retain
;; their images.  New code should pass `#:bias` with a `shadow-bias3d` value.
(define (shadow-settings3d #:map-size [map-size 1024]
                           #:bias [bias #f]
                           #:depth-bias [depth-bias #f]
                           #:normal-bias [normal-bias #f]
                           #:pcf-radius [pcf-radius #f]
                           #:bounds [bounds #f]
                           #:near [near #f]
                           #:far [far #f]
                           #:prepared-bounds-key [prepared-bounds-key #f])
  (unless (exact-positive-integer? map-size)
    (raise-argument-error 'shadow-settings3d "exact-positive-integer? as #:map-size" map-size))
  (unless (or (not bias) (shadow-bias3d? bias))
    (raise-argument-error 'shadow-settings3d "#f or shadow-bias3d? as #:bias" bias))
  (when (and bias (or depth-bias normal-bias pcf-radius))
    (raise-arguments-error
     'shadow-settings3d
     "either semantic #:bias or legacy #:depth-bias/#:normal-bias/#:pcf-radius values"
     "bias" bias
     "depth-bias" depth-bias
     "normal-bias" normal-bias
     "pcf-radius" pcf-radius))
  (define resolved-depth-bias (or depth-bias 1/1000))
  (define resolved-normal-bias (or normal-bias 1/100))
  (define resolved-pcf-radius (or pcf-radius 1))
  (for ([value (in-list (list resolved-depth-bias resolved-normal-bias))]
        [name (in-list '(depth-bias normal-bias))])
    (unless (and (finite-real? value) (>= value 0))
      (raise-arguments-error 'shadow-settings3d "nonnegative finite bias"
                             "field" name "value" value)))
  (unless (exact-nonnegative-integer? resolved-pcf-radius)
    (raise-argument-error 'shadow-settings3d
                          "exact-nonnegative-integer? as #:pcf-radius" pcf-radius))
  (when bounds
    (unless (aabb3? bounds)
      (raise-argument-error 'shadow-settings3d "#f or aabb3? as #:bounds" bounds))
    (when (aabb3-empty? bounds)
      (raise-arguments-error 'shadow-settings3d "a nonempty explicit shadow bounds"
                             "bounds" bounds)))
  (for ([value (in-list (list near far))]
        [name (in-list '(near far))])
    (unless (or (not value) (and (finite-real? value) (positive? value)))
      (raise-arguments-error 'shadow-settings3d "#f or positive finite real"
                             "field" name "value" value)))
  (when (and near far (>= near far))
    (raise-arguments-error 'shadow-settings3d "#:near less than #:far"
                           "near" near "far" far))
  (unless (or (not prepared-bounds-key) (symbol? prepared-bounds-key))
    (raise-argument-error 'shadow-settings3d
                          "#f or symbol? as #:prepared-bounds-key" prepared-bounds-key))
  (shadow-settings3d-value map-size resolved-depth-bias resolved-normal-bias
                           resolved-pcf-radius bias bounds near far
                           prepared-bounds-key))

(define (shadow-settings3d-legacy-bias? settings)
  (unless (shadow-settings3d? settings)
    (raise-argument-error 'shadow-settings3d-legacy-bias? "shadow-settings3d?" settings))
  (not (shadow-settings3d-bias settings)))

(define (shadow-settings3d-effective-pcf-radius settings)
  (unless (shadow-settings3d? settings)
    (raise-argument-error 'shadow-settings3d-effective-pcf-radius
                          "shadow-settings3d?" settings))
  (define bias (shadow-settings3d-bias settings))
  (if bias
      (shadow-bias3d-pcf-radius-texels bias)
      (shadow-settings3d-pcf-radius settings)))

(struct directional-shadow3d-value (settings) #:transparent)
(struct spot-shadow3d-value (settings) #:transparent)

(define directional-shadow3d? directional-shadow3d-value?)
(define directional-shadow3d-settings directional-shadow3d-value-settings)
(define spot-shadow3d? spot-shadow3d-value?)
(define spot-shadow3d-settings spot-shadow3d-value-settings)

(define (directional-shadow3d #:settings [settings (shadow-settings3d)])
  (check-settings 'directional-shadow3d settings)
  (directional-shadow3d-value settings))

(define (spot-shadow3d #:settings [settings (shadow-settings3d)])
  (check-settings 'spot-shadow3d settings)
  (spot-shadow3d-value settings))

(define (shadow3d? value)
  (or (directional-shadow3d? value) (spot-shadow3d? value)))

(define (shadow3d-kind shadow)
  (cond [(directional-shadow3d? shadow) 'directional]
        [(spot-shadow3d? shadow) 'spot]
        [else (raise-argument-error 'shadow3d-kind "shadow3d?" shadow)]))

(define (shadow3d-settings shadow)
  (cond [(directional-shadow3d? shadow) (directional-shadow3d-settings shadow)]
        [(spot-shadow3d? shadow) (spot-shadow3d-settings shadow)]
        [else (raise-argument-error 'shadow3d-settings "shadow3d?" shadow)]))

(define (check-settings who value)
  (unless (shadow-settings3d? value)
    (raise-argument-error who "shadow-settings3d? as #:settings" value)))
