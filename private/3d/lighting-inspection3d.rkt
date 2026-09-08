#lang racket/base

;;; Pure material, light, and fragment-lighting inspection

;; This module deliberately mirrors the documented lighting equation without
;; owning a renderer, cache, or GUI control.  It makes preview inspection
;; reproducible from immutable authoring values and leaves a future renderer
;; free to provide measured shadow factors through the named optional hash.

(require racket/list
         racket/math
         "../color-style.rkt"
         "../geometry.rkt"
         "color-space3d.rkt"
         "light-attenuation3d.rkt"
         "light3d.rkt"
         "material3d.rkt"
         "shadow3d.rkt"
         "vec3.rkt")

(provide (struct-out material-inspection3d)
         (struct-out light-inspection3d)
         (struct-out fragment-light-sample3d)
         (struct-out fragment-lighting-report3d)
         material3d-inspection
         light3d-inspection
         fragment-lighting-inspection3d)

;; `fields` values are immutable hashes so a preview, REPL, or documentation
;; renderer can choose its own presentation without parsing prose.
(struct material-inspection3d (material fields) #:transparent)
(struct light-inspection3d (light fields) #:transparent)

;; A non-ambient term records every scalar in the evaluator before colour is
;; multiplied in. Ambient terms truthfully use #f for geometric quantities.
(struct fragment-light-sample3d
  (id kind direction distance attenuation cone facing shadow-factor shadow-state
      diffuse-energy specular-energy diffuse-linear specular-linear)
  #:transparent)

;; `pre-tone-map` and `final-srgb` are straight-alpha colour values in their
;; respective representations. `diagnostics` calls out intentionally unknown
;; renderer facts, notably a descriptor with no supplied sampled map factor.
(struct fragment-lighting-report3d
  (world-point normal view-direction material light-samples pre-tone-map final-srgb diagnostics)
  #:transparent)

(define (material3d-inspection material)
  (unless (material3d? material)
    (raise-argument-error 'material3d-inspection "material3d?" material))
  (material-inspection3d
   material
   (hasheq 'base-colour (material3d-color material)
           'normal-mode (material3d-shading material)
           'lighting-model (material3d-lighting material)
           'ambient (material3d-ambient material)
           'diffuse (material3d-diffuse material)
           'specular (material3d-specular material)
           'specular-colour (material3d-specular-color material)
           'roughness (material3d-roughness material)
           'derived-specular-exponent (material3d-specular-exponent material)
           'emission (material3d-emission material)
           'emission-strength (material3d-emission-strength material)
           'double-sided? (material3d-double-sided? material)
           'casts-shadow? (material3d-casts-shadow? material)
           'receives-shadow? (material3d-receives-shadow? material))))

(define (light3d-inspection light)
  (unless (light3d? light)
    (raise-argument-error 'light3d-inspection "light3d?" light))
  (light-inspection3d
   light
   (hash-set
    (case (light3d-kind light)
      [(ambient)
       (hasheq 'id (light3d-id light) 'type 'ambient
               'colour (light3d-color light) 'intensity (light3d-intensity light))]
      [(directional)
       (hasheq 'id (light3d-id light) 'type 'directional
               'direction (directional-light3d-direction light)
               'colour (light3d-color light) 'intensity (light3d-intensity light))]
      [(point)
       (hasheq 'id (light3d-id light) 'type 'point
               'position (point-light3d-position light)
               'colour (light3d-color light) 'intensity (light3d-intensity light)
               'attenuation (light-attenuation3d->datum (point-light3d-attenuation light))
               'range (point-light3d-range light))]
      [(spot)
       (hasheq 'id (light3d-id light) 'type 'spot
               'position (spot-light3d-position light)
               'direction (spot-light3d-direction light)
               'colour (light3d-color light) 'intensity (light3d-intensity light)
               'attenuation (light-attenuation3d->datum (spot-light3d-attenuation light))
               'range (spot-light3d-range light)
               'inner-angle (spot-light3d-inner-angle light)
               'outer-angle (spot-light3d-outer-angle light))])
    'shadow (shadow3d->datum (light3d-shadow light)))))

;; fragment-lighting-inspection3d : material3d? (listof light3d?) vec3? vec3?
;;                                 vec3? [#:tone-map tone-map3d?]
;;                                 [#:shadow-factors immutable-hash?]
;;                                 -> fragment-lighting-report3d?
;; `shadow-factors` maps light ids to an exact sampled fraction in [0,1]. A
;; shadow descriptor not represented in that hash stays numerically lit and is
;; marked `not-sampled`; a preview must never invent hidden renderer state.
(define (fragment-lighting-inspection3d material lights world-point normal camera-position
                                        #:tone-map [tone-map default-tone-map3d]
                                        #:shadow-factors [shadow-factors #hasheq()])
  (unless (material3d? material)
    (raise-argument-error 'fragment-lighting-inspection3d "material3d?" material))
  (unless (and (list? lights) (andmap light3d? lights))
    (raise-argument-error 'fragment-lighting-inspection3d "(listof light3d?)" lights))
  (unless (and (vec3? world-point) (vec3? normal) (vec3? camera-position))
    (raise-argument-error 'fragment-lighting-inspection3d
                          "world point, normal, and camera position as vec3?"
                          (list world-point normal camera-position)))
  (unless (tone-map3d? tone-map)
    (raise-argument-error 'fragment-lighting-inspection3d "tone-map3d?" tone-map))
  (unless (and (hash? shadow-factors) (immutable? shadow-factors))
    (raise-argument-error 'fragment-lighting-inspection3d "immutable-hash?" shadow-factors))
  (define unit-normal (safe-normalize normal z-axis3))
  (define view-direction (safe-normalize (vec3- camera-position world-point) z-axis3))
  (define base (rgba-srgb->linear (material3d-color material)))
  (define specular-colour (rgba-srgb->linear (material3d-specular-color material)))
  (define emission (rgba-srgb->linear (material3d-emission material)))
  (define-values (samples diffuse-total specular-total diagnostics)
    (for/fold ([reversed '()]
               [diffuse-acc (linear-rgba3d 0 0 0 (linear-rgba3d-alpha base))]
               [specular-acc (linear-rgba3d 0 0 0 (linear-rgba3d-alpha base))]
               [diagnostics '()])
              ([light (in-list lights)])
      (define-values (sample diffuse specular diagnostic)
        (light-fragment-sample light material world-point unit-normal view-direction shadow-factors))
      (values (cons sample reversed)
              (linear+ diffuse diffuse-acc)
              (linear+ specular specular-acc)
              (if diagnostic (cons diagnostic diagnostics) diagnostics))))
  (define pre-tone-map
    (if (eq? (material3d-shading material) 'unlit)
        (linear+ base (linear-scale emission (material3d-emission-strength material)))
        (linear+
         (linear+
          (linear* base diffuse-total)
          (linear* specular-colour specular-total))
         (linear-scale emission (material3d-emission-strength material)))))
  (fragment-lighting-report3d
   world-point unit-normal view-direction material (reverse samples) pre-tone-map
   (rgba-linear->srgb (tone-map3d-apply tone-map pre-tone-map))
   (reverse diagnostics)))

(define (light-fragment-sample light material point normal view-direction shadow-factors)
  (cond
    [(ambient-light3d? light)
     (define energy (* (ambient-light3d-intensity light) (material3d-ambient material)))
     (define contribution (linear-scale (rgba-srgb->linear (ambient-light3d-color light)) energy))
     (values (fragment-light-sample3d
              (ambient-light3d-id light) 'ambient #f #f 1 1 1 1 'not-applicable
              energy 0 contribution (linear-zero))
             contribution (linear-zero) #f)]
    [else
     (define-values (direction distance attenuation cone colour)
       (non-ambient-sample light point normal))
     (define facing (max 0 (vec3-dot normal direction)))
     (define-values (shadow shadow-state diagnostic)
       (shadow-sample-info light material shadow-factors))
     (define energy (* (light3d-intensity light) attenuation cone shadow))
     (define diffuse-energy (* (material3d-diffuse material) energy facing))
     (define specular-energy
       (if (and (eq? (material3d-lighting material) 'blinn-phong) (positive? facing))
           (let ([half-vector (safe-normalize (vec3+ direction view-direction) normal)])
             (* (material3d-specular material) energy
                (expt (max 0 (vec3-dot normal half-vector))
                      (material3d-specular-exponent material))))
           0))
     (values
      (fragment-light-sample3d
       (light3d-id light) (light3d-kind light) direction distance attenuation cone facing
       shadow shadow-state diffuse-energy specular-energy
       (linear-scale (rgba-srgb->linear colour) diffuse-energy)
       (linear-scale (rgba-srgb->linear colour) specular-energy))
      (linear-scale (rgba-srgb->linear colour) diffuse-energy)
      (linear-scale (rgba-srgb->linear colour) specular-energy)
      diagnostic)]))

(define (non-ambient-sample light point normal)
  (cond
    [(directional-light3d? light)
     (values (vec3-scale -1 (directional-light3d-direction light)) #f 1 1
             (directional-light3d-color light))]
    [(point-light3d? light)
     (define displacement (vec3- (point-light3d-position light) point))
     (define distance (vec3-length displacement))
     (values (safe-normalize displacement normal) distance
             (finite-attenuation (point-light3d-attenuation light) (point-light3d-range light) distance)
             1 (point-light3d-color light))]
    [(spot-light3d? light)
     (define displacement (vec3- (spot-light3d-position light) point))
     (define distance (vec3-length displacement))
     (define direction (safe-normalize displacement normal))
     (define outward (vec3-scale -1 direction))
     (define cosine (max -1 (min 1 (vec3-dot (spot-light3d-direction light) outward))))
     (define angle (if (zero? distance) 0 (acos cosine)))
     (values direction distance
             (finite-attenuation (spot-light3d-attenuation light) (spot-light3d-range light) distance)
             (spot-cone-factor3d (spot-light3d-inner-angle light)
                                 (spot-light3d-outer-angle light) angle)
             (spot-light3d-color light))]
    [else
     (raise-argument-error 'fragment-lighting-inspection3d "non-ambient light3d?" light)]))

(define (finite-attenuation attenuation range distance)
  (if (and range (> distance range))
      0
      (light-attenuation3d-factor attenuation distance)))

(define (shadow-sample-info light material factors)
  (cond [(not (light3d-shadow light)) (values 1 'none #f)]
        [(not (material3d-receives-shadow? material))
         (values 1 'receiver-policy-disabled #f)]
        [(hash-has-key? factors (light3d-id light))
         (define factor (hash-ref factors (light3d-id light)))
         (unless (and (finite-real? factor) (<= 0 factor 1))
           (raise-arguments-error 'fragment-lighting-inspection3d
                                  "shadow factors in [0, 1]"
                                  "light-id" (light3d-id light) "factor" factor))
         (values factor 'sampled #f)]
        [else
         (values 1 'not-sampled
                 (hasheq 'kind 'shadow-factor-unavailable
                         'light-id (light3d-id light)
                         'reason 'renderer-map-not-supplied))]))

(define (light-attenuation3d->datum attenuation)
  (hasheq 'mode (light-attenuation3d-mode attenuation)
          'parameters (light-attenuation3d-parameters attenuation)))

(define (shadow3d->datum shadow)
  (and shadow
       (let ([settings (shadow3d-settings shadow)])
         (define bias (shadow-settings3d-bias settings))
         (hasheq 'kind (shadow3d-kind shadow)
                 'map-size (shadow-settings3d-map-size settings)
                 'bias-model (if bias 'semantic-world 'legacy-depth)
                 'semantic-bias
                 (and bias
                      (hasheq
                       'world-normal-offset
                       (shadow-bias3d-world-normal-offset bias)
                       'slope-scale (shadow-bias3d-slope-scale bias)
                       'constant-depth-offset
                       (shadow-bias3d-constant-depth-offset bias)
                       'pcf-radius-texels
                       (shadow-bias3d-pcf-radius-texels bias)))
                 'depth-bias (shadow-settings3d-depth-bias settings)
                 'normal-bias (shadow-settings3d-normal-bias settings)
                 'pcf-radius (shadow-settings3d-pcf-radius settings)
                 'bounds (shadow-settings3d-bounds settings)
                 'near (shadow-settings3d-near settings)
                 'far (shadow-settings3d-far settings)
                 'prepared-bounds-key (shadow-settings3d-prepared-bounds-key settings)))))

(define (safe-normalize value fallback)
  (if (zero? (vec3-length value)) fallback (vec3-normalize value)))

(define (linear-zero) (linear-rgba3d 0 0 0 1))

(define (linear+ first second)
  (linear-rgba3d (+ (linear-rgba3d-red first) (linear-rgba3d-red second))
                (+ (linear-rgba3d-green first) (linear-rgba3d-green second))
                (+ (linear-rgba3d-blue first) (linear-rgba3d-blue second))
                (linear-rgba3d-alpha first)))

(define (linear-scale color scalar)
  (linear-rgba3d (* scalar (linear-rgba3d-red color))
                (* scalar (linear-rgba3d-green color))
                (* scalar (linear-rgba3d-blue color))
                (linear-rgba3d-alpha color)))

(define (linear* first second)
  (linear-rgba3d (* (linear-rgba3d-red first) (linear-rgba3d-red second))
                (* (linear-rgba3d-green first) (linear-rgba3d-green second))
                (* (linear-rgba3d-blue first) (linear-rgba3d-blue second))
                (linear-rgba3d-alpha first)))
