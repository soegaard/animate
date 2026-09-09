#lang racket/base

;;;
;;; Prepared stable shadow bounds and identities
;;;

;; This is deliberately a preparation contract, not a shadow-map renderer.
;; V8 and V9 consume the prepared result.  Keeping it pure lets a project
;; sample its intended frame range once and makes any absence of stable bounds
;; visible in the future renderer diagnostics rather than causing shimmer by
;; accident.

(require racket/list
         "../color-style.rkt"
         "../render-color-context.rkt"
         "affine3.rkt"
         "bounds3.rkt"
         "compiled-view3d.rkt"
         "light3d.rkt"
         "material3d.rkt"
         "shadow3d.rkt"
         "vec3.rkt"
         "view3d-visual.rkt")

(provide (struct-out prepared-shadow-bounds3d)
         prepare-shadow-bounds3d
         prepared-shadow-bounds3d-key
         shadow-map3d-identity)

(struct prepared-shadow-bounds3d
  (light-id frame-range bounds light-space-bounds diagnostics)
  #:transparent
  #:guard
  (lambda (light-id frame-range bounds light-space-bounds diagnostics who)
    (unless (symbol? light-id)
      (raise-argument-error who "symbol? light-id" light-id))
    (check-frame-range who frame-range)
    (check-nonempty-bounds who bounds 'bounds)
    (check-nonempty-bounds who light-space-bounds 'light-space-bounds)
    (unless (and (hash? diagnostics) (immutable? diagnostics))
      (raise-argument-error who "immutable hash? diagnostics" diagnostics))
    (values light-id frame-range bounds light-space-bounds diagnostics)))

;; `views` is either one sampled `view3d` or a nonempty ordered list of sampled
;; views from the project's target frame range.  A stable map intentionally
;; rejects a changing shadow-light pose: callers must prepare each pose range
;; separately rather than reuse a geometrically invalid light-space box.
(define (prepare-shadow-bounds3d views #:light-id light-id
                                 #:frame-range [frame-range #f])
  (unless (symbol? light-id)
    (raise-argument-error 'prepare-shadow-bounds3d "symbol? as #:light-id" light-id))
  (define samples (normalize-view-samples views))
  (define effective-frame-range
    (or frame-range (cons 0 (sub1 (length samples)))))
  (check-frame-range 'prepare-shadow-bounds3d effective-frame-range)
  (unless (= (add1 (- (cdr effective-frame-range) (car effective-frame-range)))
             (length samples))
    (raise-arguments-error 'prepare-shadow-bounds3d
                           "a frame range whose inclusive size matches sampled views"
                           "frame-range" effective-frame-range
                           "view-count" (length samples)))
  (define first-light (shadow-light-for-view (car samples) light-id))
  (define first-shadow (light3d-shadow first-light))
  (unless first-shadow
    (raise-arguments-error 'prepare-shadow-bounds3d
                           "a directional or spot light with an attached shadow descriptor"
                           "light-id" light-id))
  (define pose (shadow-light-pose first-light))
  (for ([view (in-list (cdr samples))])
    (define current-light (shadow-light-for-view view light-id))
    (unless (and (equal? pose (shadow-light-pose current-light))
                 (equal? first-shadow (light3d-shadow current-light)))
      (raise-arguments-error
       'prepare-shadow-bounds3d
       "sampled views with one stable shadow-light pose and settings"
       "light-id" light-id
       "first-pose" pose
       "different-pose" (shadow-light-pose current-light))))
  (define settings (shadow3d-settings first-shadow))
  (define caster-bounds
    (for/fold ([accumulated aabb3-empty]) ([view (in-list samples)])
      (aabb3-union accumulated (view-caster-bounds view))))
  (define bounds (or (shadow-settings3d-bounds settings) caster-bounds))
  (check-nonempty-bounds 'prepare-shadow-bounds3d bounds 'bounds)
  (define light-space-bounds (bounds-in-light-space bounds first-light))
  (prepared-shadow-bounds3d
   light-id effective-frame-range bounds light-space-bounds
   (hasheq 'source (if (shadow-settings3d-bounds settings) 'explicit 'opaque-casters)
           'view-count (length samples)
           'light-kind (light3d-kind first-light)
           'stable-light-pose? #t
           'prepared-bounds-key (shadow-settings3d-prepared-bounds-key settings))))

;; This value intentionally excludes the view camera.  It changes precisely
;; when depth-map content could change: caster geometry/transform/policy,
;; shadow-light pose/settings, or prepared bounds.
(define (shadow-map3d-identity view light-id prepared)
  (unless (view3d? view)
    (raise-argument-error 'shadow-map3d-identity "view3d?" view))
  (unless (symbol? light-id)
    (raise-argument-error 'shadow-map3d-identity "symbol? light-id" light-id))
  (unless (prepared-shadow-bounds3d? prepared)
    (raise-argument-error 'shadow-map3d-identity "prepared-shadow-bounds3d?" prepared))
  (unless (eq? light-id (prepared-shadow-bounds3d-light-id prepared))
    (raise-arguments-error 'shadow-map3d-identity
                           "a prepared bound for the requested light"
                           "light-id" light-id
                           "prepared-light-id" (prepared-shadow-bounds3d-light-id prepared)))
  (define light (shadow-light-for-view view light-id))
  (define shadow (light3d-shadow light))
  (unless shadow
    (raise-arguments-error 'shadow-map3d-identity
                           "a light whose shadow descriptor remains attached"
                           "light-id" light-id))
  (define compiled (compile-view3d view))
  (vector-immutable
   'shadow-map3d-v1
   (for/list ([instance (in-vector (compiled-view3d-instances compiled))]
              #:when (instance-shadow-caster? instance))
     (vector-immutable (compiled-instance3d-geometry-key instance)
                       (compiled-instance3d-world-transform instance)
                       (material3d-casts-shadow? (compiled-instance3d-material instance))
                       (material3d-receives-shadow? (compiled-instance3d-material instance))
                       (compiled-instance3d-opacity instance)
                       (rgba-color-alpha
                        (material3d-color (compiled-instance3d-material instance)))))
   (shadow-light-pose light)
   (shadow3d-settings shadow)
   (prepared-shadow-bounds3d-key prepared)))

(define (prepared-shadow-bounds3d-key prepared)
  (unless (prepared-shadow-bounds3d? prepared)
    (raise-argument-error 'prepared-shadow-bounds3d-key "prepared-shadow-bounds3d?" prepared))
  (vector-immutable 'prepared-shadow-bounds3d-v1
                    (prepared-shadow-bounds3d-light-id prepared)
                    (prepared-shadow-bounds3d-frame-range prepared)
                    (prepared-shadow-bounds3d-bounds prepared)
                    (prepared-shadow-bounds3d-light-space-bounds prepared)))

(define (normalize-view-samples views)
  (cond [(view3d? views) (list views)]
        [(and (list? views) (pair? views) (andmap view3d? views)) views]
        [else
         (raise-argument-error 'prepare-shadow-bounds3d
                               "view3d? or nonempty (listof view3d?)" views)]))

(define (shadow-light-for-view view light-id)
  (define light
    (for/first ([candidate (in-list (view3d-lights view))]
                #:when (eq? (light3d-id candidate) light-id))
      candidate))
  (unless light
    (raise-arguments-error 'prepare-shadow-bounds3d
                           "a view containing the requested light ID"
                           "light-id" light-id))
  (unless (or (directional-light3d? light) (spot-light3d? light))
    (raise-arguments-error 'prepare-shadow-bounds3d
                           "a directional or spot light"
                           "light-id" light-id "light" light))
  light)

(define (shadow-light-pose light)
  (cond [(directional-light3d? light)
         (vector-immutable 'directional (directional-light3d-direction light))]
        [(spot-light3d? light)
         (vector-immutable 'spot (spot-light3d-position light)
                           (spot-light3d-direction light))]
        [else (raise-argument-error 'shadow-light-pose "directional or spot light" light)]))

(define (view-caster-bounds view)
  (define compiled (compile-view3d view))
  (define geometry-by-key
    (for/hash ([geometry (in-vector (compiled-view3d-geometries compiled))])
      (values (compiled-geometry3d-key geometry) geometry)))
  (for/fold ([accumulated aabb3-empty])
            ([instance (in-vector (compiled-view3d-instances compiled))])
    (if (instance-shadow-caster? instance)
        (let ([geometry (hash-ref geometry-by-key (compiled-instance3d-geometry-key instance))])
          (aabb3-union
           accumulated
           (aabb3-transform (compiled-geometry3d-local-bounds geometry)
                            (compiled-instance3d-world-transform instance))))
        accumulated)))

;; V7's policy is intentionally conservative and visible: only opaque mesh
;; instances with an affirmative material policy cast.  Strokes, markers,
;; billboards, and every transparent surface stay out of a shadow map.
(define (instance-shadow-caster? instance)
  (define material (compiled-instance3d-material instance))
  (and (material3d-casts-shadow? material)
       (= (compiled-instance3d-opacity instance) 1)
       (= (rgba-color-alpha
           (resolve-color-in-context
            (material3d-color material)
            (current-or-default-render-color-context)))
          1)))

(define (bounds-in-light-space bounds light)
  (define-values (origin forward)
    (cond [(directional-light3d? light)
           (values origin3 (directional-light3d-direction light))]
          [(spot-light3d? light)
           (values (spot-light3d-position light) (spot-light3d-direction light))]
          [else (raise-argument-error 'bounds-in-light-space "directional or spot light" light)]))
  (define reference-up
    (if (< (abs (vec3-dot forward y-axis3)) 9/10) y-axis3 x-axis3))
  (define right (vec3-normalize (vec3-cross reference-up forward)))
  (define up (vec3-cross forward right))
  (aabb3-from-points
   (for/list ([corner (in-list (aabb-corners bounds))])
     (define displacement (vec3- corner origin))
     (vec3 (vec3-dot displacement right)
           (vec3-dot displacement up)
           (vec3-dot displacement forward)))))

(define (aabb-corners bounds)
  (define minimum (aabb3-minimum bounds))
  (define maximum (aabb3-maximum bounds))
  (for*/list ([x (in-list (list (vec3-x minimum) (vec3-x maximum)))]
              [y (in-list (list (vec3-y minimum) (vec3-y maximum)))]
              [z (in-list (list (vec3-z minimum) (vec3-z maximum)))])
    (vec3 x y z)))

(define (check-frame-range who value)
  (unless (and (pair? value) (exact-nonnegative-integer? (car value))
               (exact-nonnegative-integer? (cdr value)) (<= (car value) (cdr value)))
    (raise-argument-error who
                          "(cons/c exact-nonnegative-integer? exact-nonnegative-integer?) with start <= end"
                          value)))

(define (check-nonempty-bounds who value field)
  (unless (aabb3? value)
    (raise-arguments-error who "aabb3? bounds" "field" field "value" value))
  (when (aabb3-empty? value)
    (raise-arguments-error who "nonempty shadow bounds" "field" field "value" value)))
