#lang racket/base

;;;
;;; Tubular Spatial Meshes
;;;

;; Converts a deterministic centre-line sample sequence into an opaque tube
;; mesh.  The construction is pure; renderers receive ordinary `mesh3d`
;; values and therefore retain the same clipping, depth, and lighting rules as
;; every other spatial surface.


;;;
;;; Imports and Exports
;;;

(require racket/list
         (only-in racket/math pi)
         "../geometry.rkt"
         "bounds3.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide tube3d
         tube3d-mesh
         tube3d-sanitize-points)


;;;
;;; Public Construction
;;;

; tube3d : (or/c (listof vec3?) (vectorof vec3?)) #:id symbol?
;          [#:radius positive-finite-real?] [#:sides exact-integer?]
;          [#:closed? boolean?] [#:caps? boolean?] [#:color color-spec?]
;          [#:transform transform3?] [#:opacity spatial-opacity?]
;          [#:width-mode 'world] -> mesh3d?
;;   Creates a physical-radius tube around consecutive centre-line samples.
;;   Screen-space widths are deliberately not accepted: they require a
;; depth-aware raster policy and are not interchangeable with world radii.
(define (tube3d points
                #:id id
                #:radius [radius 1/20]
                #:sides [sides 8]
                #:closed? [closed? #f]
                #:caps? [caps? #t]
                #:color [color "steelblue"]
                #:transform [transform identity-transform3]
                #:opacity [opacity 1]
                #:width-mode [width-mode 'world])
  (check-width-mode 'tube3d width-mode)
  (tube3d-mesh points
               #:id id #:radius radius #:sides sides #:closed? closed?
               #:caps? caps? #:color color #:transform transform #:opacity opacity))

; tube3d-mesh : (or/c (listof vec3?) (vectorof vec3?)) #:id symbol? ... -> mesh3d?
;;   Internal shared constructor for curves, segments, and arrow shafts.
(define (tube3d-mesh points
                     #:id id
                     #:radius [radius 1/20]
                     #:sides [sides 8]
                     #:closed? [closed? #f]
                     #:caps? [caps? #t]
                     #:color [color "steelblue"]
                     #:transform [transform identity-transform3]
                     #:opacity [opacity 1])
  (unless (symbol? id)
    (raise-argument-error 'tube3d "symbol?" id))
  (unless (and (finite-real? radius) (positive? radius))
    (raise-argument-error 'tube3d "positive finite radius" radius))
  (unless (and (exact-integer? sides) (>= sides 3))
    (raise-argument-error 'tube3d "exact integer at least 3" sides))
  (unless (boolean? closed?)
    (raise-argument-error 'tube3d "boolean?" closed?))
  (unless (boolean? caps?)
    (raise-argument-error 'tube3d "boolean?" caps?))
  (define centres (tube3d-sanitize-points points #:closed? closed?))
  (when (< (length centres) 2)
    (raise-arguments-error
     'tube3d "at least two distinct centre-line points"
     "points" points))
  (define frames (parallel-transport-frames centres closed?))
  (define ring-count (length centres))
  (define vertices
    (list->vector
     (append
      (apply append
             (for/list ([centre (in-list centres)]
                        [frame (in-list frames)])
               (for/list ([side (in-range sides)])
                 (define normal (first frame))
                 (define binormal (second frame))
                 (define angle (* 2 pi (/ side sides)))
                 (vec3+
                  centre
                  (vec3-scale
                   radius
                   (vec3+ (vec3-scale (cos angle) normal)
                          (vec3-scale (sin angle) binormal)))))))
      (if (and caps? (not closed?))
          (list (first centres) (last centres))
          '()))))
  (define side-rings (if closed? ring-count (sub1 ring-count)))
  (define side-triangles
    (for*/list ([ring (in-range side-rings)]
                [side (in-range sides)])
      (define next-ring (modulo (add1 ring) ring-count))
      (define next-side (modulo (add1 side) sides))
      (define a (+ (* ring sides) side))
      (define b (+ (* ring sides) next-side))
      (define c (+ (* next-ring sides) next-side))
      (define d (+ (* next-ring sides) side))
      (list (vector a b c) (vector a c d))))
  (define cap-triangles
    (cond
      [(and caps? (not closed?))
       (define start-centre-index (* ring-count sides))
       (define end-centre-index (add1 (* ring-count sides)))
       (define last-ring (sub1 ring-count))
       (append
        (for/list ([side (in-range sides)])
          (vector start-centre-index
                  (modulo (add1 side) sides)
                  side))
        (for/list ([side (in-range sides)])
          (vector end-centre-index
                  (+ (* last-ring sides) side)
                  (+ (* last-ring sides) (modulo (add1 side) sides)))))]
      [else '()]))
  ;; A tube has deliberately explicit longitudinal and ring edges.  This keeps
  ;; wireframe curves recognisable rather than exposing triangulation diagonals.
  (define edges
    (list->vector
     (append
      (for*/list ([ring (in-range side-rings)] [side (in-range sides)])
        (vector (+ (* ring sides) side)
                (+ (* (modulo (add1 ring) ring-count) sides) side)))
      (for*/list ([ring (in-range ring-count)] [side (in-range sides)])
        (vector (+ (* ring sides) side)
                (+ (* ring sides) (modulo (add1 side) sides)))))))
  (mesh3d #:id id
          #:vertices vertices
          #:triangles
          (list->vector
           (append (apply append side-triangles) cap-triangles))
          #:edges edges
          #:material (material3d #:color color #:shading 'unlit #:double-sided? #t)
          #:transform transform #:opacity opacity
          #:wireframe-color color #:wireframe-width 2))


;;;
;;; Sample and Frame Preparation
;;;

; tube3d-sanitize-points : (or/c (listof vec3?) (vectorof vec3?))
;                          [#:closed? boolean?] -> (listof vec3?)
;;   Copies samples and drops adjacent repeats, including a redundant closing
;;   endpoint.  A zero tangent is never invented from repeated samples.
(define (tube3d-sanitize-points points #:closed? [closed? #f])
  (unless (or (list? points) (vector? points))
    (raise-argument-error 'tube3d "list or vector of vec3 values" points))
  (unless (boolean? closed?)
    (raise-argument-error 'tube3d-sanitize-points "boolean?" closed?))
  (define copied
    (for/list ([point (in-list (if (vector? points) (vector->list points) points))])
      (unless (vec3? point)
        (raise-argument-error 'tube3d "list or vector of vec3 values" points))
      point))
  (define distinct
    (reverse
     (for/fold ([kept '()]) ([point (in-list copied)])
       (cond [(null? kept) (list point)]
             [(zero? (vec3-distance point (car kept))) kept]
             [else (cons point kept)]))))
  (if (and closed? (>= (length distinct) 2)
           (zero? (vec3-distance (first distinct) (last distinct))))
      (drop-right distinct 1)
      distinct))

; parallel-transport-frames : (listof vec3?) boolean?
;                             -> (listof (list/c vec3? vec3?))
;;   Carries one normal through successive tangent planes by projection.  At a
;; reversal, where that projection vanishes, a deterministic least-aligned
;; world axis supplies the new normal instead of producing NaNs or random spin.
(define (parallel-transport-frames centres closed?)
  (define tangents (centre-tangents centres closed?))
  (define initial (initial-normal (first tangents)))
  (let loop ([remaining-tangents tangents] [previous-normal initial] [frames '()])
    (cond [(null? remaining-tangents) (reverse frames)]
          [else
           (define tangent (car remaining-tangents))
           (define projected
             (vec3- previous-normal
                    (vec3-scale (vec3-dot previous-normal tangent) tangent)))
           (define normal
             (if (zero? (vec3-length projected))
                 (initial-normal tangent)
                 (vec3-normalize projected)))
           (define binormal (vec3-normalize (vec3-cross tangent normal)))
           (loop (cdr remaining-tangents) normal
                 (cons (list normal binormal) frames))])))

(define (centre-tangents centres closed?)
  (define count (length centres))
  (for/list ([index (in-range count)])
    (define previous-index (if (zero? index) (if closed? (sub1 count) 0) (sub1 index)))
    (define next-index (if (= index (sub1 count)) (if closed? 0 (sub1 count)) (add1 index)))
    (define previous (list-ref centres previous-index))
    (define current (list-ref centres index))
    (define next (list-ref centres next-index))
    (define incoming (vec3- current previous))
    (define outgoing (vec3- next current))
    (define candidate
      (cond [(and (zero? index) (not closed?)) (vec3- next current)]
            [(and (= index (sub1 count)) (not closed?)) (vec3- current previous)]
            [else (vec3- next previous)]))
    ;; A sharp U-turn has a vanishing centred tangent.  Prefer its outgoing
    ;; direction (or the only available incoming one) instead of attempting to
    ;; normalize zero; repeated samples were already removed earlier.
    (vec3-normalize
     (if (zero? (vec3-length candidate))
         (if (positive? (vec3-length outgoing)) outgoing incoming)
         candidate))))

(define (initial-normal tangent)
  (define candidates (list x-axis3 y-axis3 z-axis3))
  (define guide
    (argmin (lambda (axis) (abs (vec3-dot tangent axis))) candidates))
  (vec3-normalize (vec3-cross tangent guide)))

(define (check-width-mode who value)
  (unless (eq? value 'world)
    (raise-arguments-error
     who
     "a physical `world` width; depth-aware screen widths are not implemented"
     "width-mode" value)))
