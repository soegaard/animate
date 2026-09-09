#lang racket/base

;;;
;;; Pure progressive-reveal fronts
;;;

;; Front values deliberately contain no renderer or scene state. A caller
;; supplies the layout box frozen for one lifecycle clip and receives a valid
;; local hard-clip path for any direct progress sample.

(require (only-in racket/math pi)
         "geometry.rkt"
         "layout-box.rkt"
         "path-geometry.rkt")

(provide reveal-front?
         linear-reveal-front
         linear-reveal-front?
         radial-reveal-front
         radial-reveal-front?
         reveal-front-path)

(struct linear-reveal-front-value (direction origin padding)
  #:transparent)

(struct radial-reveal-front-value (center start-radius padding)
  #:transparent)

(define (reveal-front? value)
  (or (linear-reveal-front-value? value)
      (radial-reveal-front-value? value)))

(define linear-reveal-front? linear-reveal-front-value?)
(define radial-reveal-front? radial-reveal-front-value?)

;; linear-reveal-front : vec2? [#:origin (or/c 'automatic vec2?)]
;;                       [#:padding nonnegative-finite-real?] -> reveal-front?
;; `direction` is normalized at construction. Padding is a fraction of the
;; larger frozen-box dimension, so it is invariant under unit changes.
(define (linear-reveal-front direction
                            #:origin [origin 'automatic]
                            #:padding [padding 1/20])
  (linear-reveal-front-value
   (normalize-front-direction 'linear-reveal-front direction)
   (check-front-reference 'linear-reveal-front origin)
   (check-front-padding 'linear-reveal-front padding)))

;; radial-reveal-front : [#:center (or/c 'automatic vec2?)]
;;                       [#:start-radius nonnegative-finite-real?]
;;                       [#:padding nonnegative-finite-real?] -> reveal-front?
(define (radial-reveal-front #:center [center 'automatic]
                            #:start-radius [start-radius 0]
                            #:padding [padding 1/20])
  (radial-reveal-front-value
   (check-front-reference 'radial-reveal-front center)
   (check-nonnegative-finite-real 'radial-reveal-front "start radius" start-radius)
   (check-front-padding 'radial-reveal-front padding)))

;; reveal-front-path : reveal-front? layout-box? unit-real?
;;                    [#:world-units-per-pixel positive-finite-real?]
;;                    [#:max-error-pixels positive-finite-real?]
;;                    -> path-geometry?
;; Progress zero returns empty path geometry whenever the authored start front
;; has no area. This avoids constructing a degenerate zero-area clip polygon.
(define (reveal-front-path front box progress
                          #:world-units-per-pixel [world-units-per-pixel 1/64]
                          #:max-error-pixels [max-error-pixels 1/2])
  (unless (reveal-front? front)
    (raise-argument-error 'reveal-front-path "reveal-front?" front))
  (unless (layout-box? box)
    (raise-argument-error 'reveal-front-path "layout-box?" box))
  (unless (and (finite-real? progress) (<= 0 progress 1))
    (raise-argument-error 'reveal-front-path "finite real in the closed unit interval" progress))
  (unless (and (finite-real? world-units-per-pixel)
               (positive? world-units-per-pixel))
    (raise-argument-error 'reveal-front-path
                          "positive finite real as #:world-units-per-pixel"
                          world-units-per-pixel))
  (unless (and (finite-real? max-error-pixels)
               (positive? max-error-pixels))
    (raise-argument-error 'reveal-front-path
                          "positive finite real as #:max-error-pixels"
                          max-error-pixels))
  (cond
    [(linear-reveal-front-value? front)
     (linear-front-path front box progress)]
    [else (radial-front-path front box progress world-units-per-pixel
                             max-error-pixels)]))

(define (linear-front-path front box progress)
  (define expanded (expand-layout-box box (linear-reveal-front-value-padding front)))
  (define corners (layout-box-corners expanded))
  (define direction (linear-reveal-front-value-direction front))
  (define reference
    (front-reference-point (linear-reveal-front-value-origin front) expanded))
  (define reference-projection (dot direction reference))
  (define span
    (apply max
           (for/list ([corner (in-list corners)])
             (abs (- (dot direction corner) reference-projection)))))
  (define threshold
    (+ reference-projection (* (- (* 2 progress) 1) span)))
  (polygon-or-empty
   (clip-polygon-at-or-below corners direction threshold)))

(define (radial-front-path front box progress world-units-per-pixel
                           max-error-pixels)
  (define expanded (expand-layout-box box (radial-reveal-front-value-padding front)))
  (define center
    (front-reference-point (radial-reveal-front-value-center front) expanded))
  (define final-radius
    (apply max
           (for/list ([corner (in-list (layout-box-corners expanded))])
             (point-distance center corner))))
  (define start-radius (radial-reveal-front-value-start-radius front))
  (define radius
    (+ start-radius (* progress (max 0 (- final-radius start-radius)))))
  (if (zero? radius)
      empty-path-geometry
      (let ([segments (radial-segment-count radius world-units-per-pixel
                                            max-error-pixels)])
        (polygon-path
       (for/list ([index (in-range segments)])
         (define angle (* 2 pi (/ index segments)))
         ;; The polygon circumscribes, rather than inscribes, the mathematical
         ;; disk so an endpoint radius that reaches every box corner cannot
         ;; leave a one-pixel corner unmasked between sample vertices.
         (define polygon-radius (/ radius (cos (/ pi segments))))
         (vec2 (+ (vec2-x center) (* polygon-radius (cos angle)))
               (+ (vec2-y center) (* polygon-radius (sin angle)))))))))

;; The chord sagitta of an n-gon is r * (1 - cos(pi/n)). Choose the smallest
;; useful n whose projected error is below the requested pixel budget, then
;; clamp it so a malformed or gigantic author box cannot create an unbounded
;; renderer allocation. The enclosing polygon still guarantees endpoint
;; coverage of every layout-box corner.
(define (radial-segment-count radius world-units-per-pixel max-error-pixels)
  (define projected-radius (/ radius world-units-per-pixel))
  (define raw
    (if (zero? projected-radius)
        16
        (let* ([tolerance
                (min max-error-pixels (max 1/1024 projected-radius))]
               [ratio
                (max -1 (min 1 (- 1 (/ tolerance projected-radius))))])
          (ceiling (/ pi (acos ratio))))))
  (min 1024 (max 16 raw)))

;; Keeps a local rectangular front clipped by the half-plane dot(p,d) <= t.
;; This is pure Sutherland--Hodgman clipping, so oblique directions use exactly
;; the same geometry as cardinal directions and need no raster backend.
(define (clip-polygon-at-or-below points direction threshold)
  (define (inside? point) (<= (dot direction point) threshold))
  (define (intersection first second)
    (define first-projection (dot direction first))
    (define second-projection (dot direction second))
    (define denominator (- second-projection first-projection))
    (define fraction
      (if (zero? denominator)
          0
          (/ (- threshold first-projection) denominator)))
    (vec2-lerp first second (min 1 (max 0 fraction))))
  (for/fold ([output '()])
            ([first (in-list points)]
             [second (in-list (append (cdr points) (list (car points))))])
    (define first-inside? (inside? first))
    (define second-inside? (inside? second))
    (cond
      [(and first-inside? second-inside?) (append output (list second))]
      [(and first-inside? (not second-inside?))
       (append output (list (intersection first second)))]
      [(and (not first-inside?) second-inside?)
       (append output (list (intersection first second) second))]
      [else output])))

(define (polygon-or-empty points)
  (cond
    [(< (length points) 3) empty-path-geometry]
    [(zero? (polygon-double-area points)) empty-path-geometry]
    [else (polygon-path points)]))

(define (polygon-double-area points)
  (for/sum ([first (in-list points)]
            [second (in-list (append (cdr points) (list (car points))))])
    (- (* (vec2-x first) (vec2-y second))
       (* (vec2-y first) (vec2-x second)))))

(define (layout-box-corners box)
  (list (vec2 (layout-box-left box) (layout-box-bottom box))
        (vec2 (layout-box-right box) (layout-box-bottom box))
        (vec2 (layout-box-right box) (layout-box-top box))
        (vec2 (layout-box-left box) (layout-box-top box))))

(define (expand-layout-box box padding)
  (define extent
    (* padding (max (layout-box-width box) (layout-box-height box))))
  (layout-box (- (layout-box-left box) extent)
              (- (layout-box-bottom box) extent)
              (+ (layout-box-right box) extent)
              (+ (layout-box-top box) extent)))

(define (front-reference-point value box)
  (if (eq? value 'automatic) (layout-box-center box) value))

(define (dot left right)
  (+ (* (vec2-x left) (vec2-x right))
     (* (vec2-y left) (vec2-y right))))

(define (point-distance first second)
  (define dx (- (vec2-x second) (vec2-x first)))
  (define dy (- (vec2-y second) (vec2-y first)))
  (sqrt (+ (* dx dx) (* dy dy))))

(define (normalize-front-direction who direction)
  (unless (and (vec2? direction)
               (finite-real? (vec2-x direction))
               (finite-real? (vec2-y direction)))
    (raise-argument-error who "vec2 with finite components" direction))
  (define scale (max (abs (vec2-x direction)) (abs (vec2-y direction))))
  (unless (positive? scale)
    (raise-arguments-error who "a nonzero direction" "direction" direction))
  (define scaled-x (/ (vec2-x direction) scale))
  (define scaled-y (/ (vec2-y direction) scale))
  (define magnitude (sqrt (+ (* scaled-x scaled-x) (* scaled-y scaled-y))))
  (vec2 (/ scaled-x magnitude) (/ scaled-y magnitude)))

(define (check-front-reference who value)
  (unless (or (eq? value 'automatic)
              (and (vec2? value)
                   (finite-real? (vec2-x value))
                   (finite-real? (vec2-y value))))
    (raise-argument-error who "(or/c 'automatic vec2-with-finite-components?)" value))
  value)

(define (check-front-padding who value)
  (check-nonnegative-finite-real who "padding" value))

(define (check-nonnegative-finite-real who label value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-arguments-error who
                           (string-append "a nonnegative finite " label)
                           "value" value))
  value)
