#lang racket/base

;;; Software shadow-map values and sampling

(require racket/vector
         "../geometry.rkt"
         "bounds3.rkt"
         "camera3d.rkt"
         "light3d.rkt"
         "raster-target3d.rkt"
         "shadow3d.rkt"
         "vec3.rkt")

(provide (struct-out shadow-map3d)
         make-shadow-map3d
         shadow-map3d-factor
         shadow-light-camera3d)

;; `depth` is an immutable top-left vector of positive light-camera depths.
;; It belongs to the semantic preparation, never to a caller's mutable raster
;; target, so cached samples cannot be changed by a later colour pass.
(struct shadow-map3d (width height depth camera settings bounds diagnostics)
  #:transparent
  #:guard
  (lambda (width height depth camera settings bounds diagnostics who)
    (unless (exact-positive-integer? width)
      (raise-argument-error who "exact-positive-integer? as width" width))
    (unless (exact-positive-integer? height)
      (raise-argument-error who "exact-positive-integer? as height" height))
    (unless (and (vector? depth) (immutable? depth)
                 (= (vector-length depth) (* width height))
                 (for/and ([value (in-vector depth)])
                   (or (and (finite-real? value) (positive? value))
                       (eqv? value +inf.0))))
      (raise-arguments-error
       who "an immutable width-by-height vector of positive depths or +inf.0"
       "width" width "height" height "depth" depth))
    (unless (camera3d? camera)
      (raise-argument-error who "camera3d?" camera))
    (unless (shadow-settings3d? settings)
      (raise-argument-error who "shadow-settings3d?" settings))
    (unless (and (aabb3? bounds) (not (aabb3-empty? bounds)))
      (raise-argument-error who "nonempty aabb3?" bounds))
    (unless (and (hash? diagnostics) (immutable? diagnostics))
      (raise-argument-error who "immutable hash?" diagnostics))
    (values width height depth camera settings bounds diagnostics)))

(define (make-shadow-map3d target camera settings bounds diagnostics)
  (unless (raster-target3d? target)
    (raise-argument-error 'make-shadow-map3d "raster-target3d?" target))
  (shadow-map3d (raster-target3d-width target) (raster-target3d-height target)
                (vector->immutable-vector (vector-copy (raster-target3d-depth-values target)))
                camera settings bounds diagnostics))

;; Bias is evaluated in the same positive forward-depth unit stored in the
;; map.  Outside a map is explicitly unshadowed, as required for a finite
;; fitted directional map and for spots beyond their selected far plane.
(define (shadow-map3d-factor map world-position world-normal light-direction)
  (unless (shadow-map3d? map)
    (raise-argument-error 'shadow-map3d-factor "shadow-map3d?" map))
  (unless (and (vec3? world-position) (vec3? world-normal) (vec3? light-direction))
    (raise-argument-error 'shadow-map3d-factor "vec3? position, normal, and light direction"
                          (list world-position world-normal light-direction)))
  (define camera (shadow-map3d-camera map))
  (define ndc (camera3d-project camera world-position #:aspect 1))
  (cond [(or (not ndc) (> (abs (vec2-x ndc)) 1) (> (abs (vec2-y ndc)) 1)) 1]
        [else
         (define depth (camera3d-view-depth camera world-position))
         (define settings (shadow-map3d-settings map))
         (define incoming (vec3-scale -1 (vec3-normalize light-direction)))
         (define bias (+ (shadow-settings3d-depth-bias settings)
                         (* (shadow-settings3d-normal-bias settings)
                            (- 1 (max 0 (vec3-dot (vec3-normalize world-normal) incoming))))))
         (define center-x (inexact->exact (floor (* (shadow-map3d-width map)
                                                    (/ (+ (vec2-x ndc) 1) 2)))))
         (define center-y (inexact->exact (floor (* (shadow-map3d-height map)
                                                    (/ (- 1 (vec2-y ndc)) 2)))))
         (define radius (shadow-settings3d-pcf-radius settings))
         (define-values (lit samples)
           (for*/fold ([lit 0] [samples 0])
                      ([dy (in-range (- radius) (add1 radius))]
                       [dx (in-range (- radius) (add1 radius))])
             (define x (+ center-x dx))
             (define y (+ center-y dy))
             (if (and (<= 0 x) (< x (shadow-map3d-width map))
                      (<= 0 y) (< y (shadow-map3d-height map)))
                 (let ([stored (vector-ref (shadow-map3d-depth map)
                                           (+ x (* y (shadow-map3d-width map))))])
                   (values (+ lit (if (<= depth (+ stored bias)) 1 0)) (add1 samples)))
                 (values (+ lit 1) (add1 samples)))))
         (/ lit samples)]))

;; A light camera is fitted to a selected world-space bound. Directional maps
;; use a square orthographic footprint; a spot follows its authored cone.
(define (shadow-light-camera3d light settings bounds)
  (unless (or (directional-light3d? light) (spot-light3d? light))
    (raise-argument-error 'shadow-light-camera3d "directional-light3d? or spot-light3d?" light))
  (unless (and (aabb3? bounds) (not (aabb3-empty? bounds)))
    (raise-argument-error 'shadow-light-camera3d "nonempty aabb3?" bounds))
  (define direction (if (directional-light3d? light)
                        (directional-light3d-direction light)
                        (spot-light3d-direction light)))
  (cond [(directional-light3d? light)
         (directional-shadow-camera direction settings bounds)]
        [else
         (spot-shadow-camera light direction settings bounds)]))

;; Directional lights have no source point, so use the same deterministic
;; light-space basis as V7's prepared-bound calculation. The orthographic
;; square covers every caster corner. A named prepared-bound key enables
;; texel-centre snapping, which keeps an authored stable bound from drifting
;; when the view camera moves.
(define (directional-shadow-camera direction settings bounds)
  (define-values (right up) (shadow-basis direction))
  (define coordinates
    (for/list ([corner (in-list (aabb-corners bounds))])
      (vector (vec3-dot corner right)
              (vec3-dot corner up)
              (vec3-dot corner direction))))
  (define min-x (apply min (map (lambda (coordinate) (vector-ref coordinate 0)) coordinates)))
  (define max-x (apply max (map (lambda (coordinate) (vector-ref coordinate 0)) coordinates)))
  (define min-y (apply min (map (lambda (coordinate) (vector-ref coordinate 1)) coordinates)))
  (define max-y (apply max (map (lambda (coordinate) (vector-ref coordinate 1)) coordinates)))
  (define min-z (apply min (map (lambda (coordinate) (vector-ref coordinate 2)) coordinates)))
  (define max-z (apply max (map (lambda (coordinate) (vector-ref coordinate 2)) coordinates)))
  (define spatial-span (max (- max-x min-x) (- max-y min-y) (- max-z min-z)))
  (define margin (max 1e-4 (* 1e-3 (max 1 spatial-span))))
  (define base-side (max (- max-x min-x) (- max-y min-y) margin))
  ;; Add a texel-sized guard band on all sides. It avoids a caster exactly on
  ;; the half-open raster edge disappearing from the depth map.
  (define side (+ base-side (* 2 margin)))
  (define raw-center-x (/ (+ min-x max-x) 2))
  (define raw-center-y (/ (+ min-y max-y) 2))
  (define texel (/ side (shadow-settings3d-map-size settings)))
  (define (snap coordinate)
    (* texel (round (/ coordinate texel))))
  (define center-x
    (if (shadow-settings3d-prepared-bounds-key settings) (snap raw-center-x) raw-center-x))
  (define center-y
    (if (shadow-settings3d-prepared-bounds-key settings) (snap raw-center-y) raw-center-y))
  (define near (or (shadow-settings3d-near settings) margin))
  (define covered-far (+ (- max-z min-z) (* 2 margin)))
  (define far (or (shadow-settings3d-far settings) covered-far))
  (define effective-far (max far (+ near margin)))
  (define position
    (vec3+
     (vec3+ (vec3-scale center-x right) (vec3-scale center-y up))
     (vec3-scale (- min-z margin) direction)))
  (orthographic-camera3d #:position position #:look-at (vec3+ position direction)
                         #:near near #:far effective-far #:vertical-size side))

;; A spot has a real source and its own authored cone. Its far plane either
;; follows an explicit setting, a finite light range, or the deepest selected
;; caster corner; the latter two are padded enough to retain an edge sample.
(define (spot-shadow-camera light direction settings bounds)
  (define position (spot-light3d-position light))
  (define depths
    (for/list ([corner (in-list (aabb-corners bounds))])
      (vec3-dot (vec3- corner position) direction)))
  (define positive-depths (filter positive? depths))
  (define nearest (if (null? positive-depths) 1e-4 (apply min positive-depths)))
  (define farthest (if (null? positive-depths) 1 (apply max positive-depths)))
  (define margin (max 1e-4 (* 1e-3 (max 1 farthest))))
  (define near (or (shadow-settings3d-near settings)
                   (max 1e-4 (- nearest margin))))
  (define covered-far (+ farthest margin))
  (define range (spot-light3d-range light))
  (define far (or (shadow-settings3d-far settings)
                  (if range (min range covered-far) covered-far)))
  ;; A source inside a caster can make an automatically chosen near plane
  ;; exceed a deliberately short finite range. Keep the camera constructor's
  ;; invariant and allow the empty/ineligible region to remain unshadowed.
  (define effective-far (max far (+ near 1e-4)))
  (perspective-camera3d #:position position #:look-at (vec3+ position direction)
                        #:near near #:far effective-far
                        #:vertical-field-of-view (* 2 (spot-light3d-outer-angle light))))

(define (shadow-basis direction)
  (define reference-up
    (if (< (abs (vec3-dot direction y-axis3)) 9/10) y-axis3 x-axis3))
  (define right (vec3-normalize (vec3-cross reference-up direction)))
  (values right (vec3-cross direction right)))

(define (aabb-corners bounds)
  (define minimum (aabb3-minimum bounds))
  (define maximum (aabb3-maximum bounds))
  (for*/list ([x (in-list (list (vec3-x minimum) (vec3-x maximum)))]
              [y (in-list (list (vec3-y minimum) (vec3-y maximum)))]
              [z (in-list (list (vec3-z minimum) (vec3-z maximum)))])
    (vec3 x y z)))
