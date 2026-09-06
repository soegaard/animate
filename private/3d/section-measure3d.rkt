#lang racket/base

;;;
;;; Pure Measurements of Closed Section Components
;;;

(require racket/list
         "plane-basis3d.rkt" "clipping3d.rkt" "ray-plane.rkt" "vec3.rkt")

(provide section3d-area section3d-centroid section3d-perimeter section3d-second-moments)

(define (closed-components who section)
  (unless (section3d? section) (raise-argument-error who "section3d?" section))
  (define components (filter section-component3d-closed? (section3d-components section)))
  (unless (pair? components)
    (raise-arguments-error who "a section with at least one closed component" "section" section))
  components)

(struct section-loop-measure3d (points coordinates raw-area signed-area) #:transparent)

;; Section graph reconstruction yields a set of simple closed loops.  A nested
;; loop represents a hole even when all loops share the section-plane winding,
;; so measurements classify it by deterministic containment depth rather than
;; assuming the source mesh's triangle orientation encodes fill polarity.
(define (section-loop-measures who section)
  (define basis (section3d-basis section))
  (define loops
    (map section-component3d-points (closed-components who section)))
  (for/list ([points (in-list loops)])
    (define coordinates
      (for/list ([point (in-list points)]) (plane-basis3d-project basis point)))
    (define raw-area (signed-area2 coordinates))
    (define probe (car coordinates))
    (define depth
      (for/sum ([other (in-list loops)]
                #:when (not (eq? other points)))
        (if (point-in-polygon? probe
                               (for/list ([point (in-list other)])
                                 (plane-basis3d-project basis point)))
            1
            0)))
    (section-loop-measure3d points coordinates raw-area
                            (* (if (even? depth) 1 -1) (abs raw-area)))))

(define (section3d-area section)
  (for/sum ([loop (in-list (section-loop-measures 'section3d-area section))])
    (section-loop-measure3d-signed-area loop)))

(define (section3d-perimeter section)
  (for/sum ([component (in-list (closed-components 'section3d-perimeter section))])
    (define points (section-component3d-points component))
    (for/sum ([point (in-list points)] [next (in-list (append (cdr points) (list (car points))))])
      (vec3-distance point next))))

;; Uses the exact shoelace centroid of every loop, with nested loops subtracted
;; as holes.  The result lives in the section plane and therefore preserves the
;; plane's original 3D position rather than returning local coordinates.
(define (section3d-centroid section)
  (define basis (section3d-basis section))
  (define loops (section-loop-measures 'section3d-centroid section))
  (define total (for/sum ([loop (in-list loops)]) (section-loop-measure3d-signed-area loop)))
  (if (zero? total)
      (plane3-point (section3d-plane section))
      (vec3-scale
       (/ 1 total)
       (for/fold ([sum origin3]) ([loop (in-list loops)])
         (vec3+ sum
                (vec3-scale (section-loop-measure3d-signed-area loop)
                            (plane-basis3d-unproject basis
                                                     (polygon-centroid2
                                                      (section-loop-measure3d-coordinates loop)))))))))

;; Returns `(vector Iuu Ivv Iuv)` about the plane-basis origin.  Nested loops
;; are subtracted, which makes the result useful for annular sections as well
;; as ordinary convex cuts.
(define (section3d-second-moments section)
  (define loops (section-loop-measures 'section3d-second-moments section))
  (define-values (iuu ivv iuv)
    (for/fold ([iuu 0] [ivv 0] [iuv 0]) ([loop (in-list loops)])
      (define-values (loop-iuu loop-ivv loop-iuv)
        (polygon-second-moments2 (section-loop-measure3d-coordinates loop)))
      ;; The closed-loop formula carries its input winding.  Restore the
      ;; intended fill sign (outer positive, hole negative) explicitly.
      (define orientation-factor
        (cond [(positive? (section-loop-measure3d-raw-area loop)) 1]
              [(negative? (section-loop-measure3d-raw-area loop)) -1]
              [else 0]))
      (define fill-factor
        (if (negative? (section-loop-measure3d-signed-area loop)) -1 1))
      (define factor (* orientation-factor fill-factor))
      (values (+ iuu (* factor loop-iuu))
              (+ ivv (* factor loop-ivv))
              (+ iuv (* factor loop-iuv)))))
  (vector iuu ivv iuv))

(define (signed-area2 coordinates)
  (/ (for/sum ([point (in-list coordinates)]
               [next (in-list (append (cdr coordinates) (list (car coordinates))))])
       (- (* (vector-ref point 0) (vector-ref next 1))
          (* (vector-ref next 0) (vector-ref point 1))))
     2))

(define (polygon-centroid2 coordinates)
  (define twice-area (* 2 (signed-area2 coordinates)))
  (if (zero? twice-area)
      (vector 0 0)
      (let-values ([(sum-u sum-v)
                    (for/fold ([sum-u 0] [sum-v 0])
                              ([point (in-list coordinates)]
                               [next (in-list (append (cdr coordinates)
                                                      (list (car coordinates))))])
                      (define cross
                        (- (* (vector-ref point 0) (vector-ref next 1))
                           (* (vector-ref next 0) (vector-ref point 1))))
                      (values (+ sum-u (* (+ (vector-ref point 0) (vector-ref next 0)) cross))
                              (+ sum-v (* (+ (vector-ref point 1) (vector-ref next 1)) cross))))])
        (vector (/ sum-u (* 3 twice-area))
                (/ sum-v (* 3 twice-area))))))

(define (polygon-second-moments2 coordinates)
  (for/fold ([iuu 0] [ivv 0] [iuv 0])
            ([point (in-list coordinates)]
             [next (in-list (append (cdr coordinates) (list (car coordinates))))])
    (define u0 (vector-ref point 0))
    (define v0 (vector-ref point 1))
    (define u1 (vector-ref next 0))
    (define v1 (vector-ref next 1))
    (define cross (- (* u0 v1) (* u1 v0)))
    (values (+ iuu (/ (* cross (+ (* v0 v0) (* v0 v1) (* v1 v1))) 12))
            (+ ivv (/ (* cross (+ (* u0 u0) (* u0 u1) (* u1 u1))) 12))
            (+ iuv (/ (* cross (+ (* u0 v1) (* 2 u0 v0) (* 2 u1 v1) (* u1 v0))) 24)))))

(define (point-in-polygon? point polygon)
  ;; Ray casting with a deterministic horizontal ray.  Section loops are
  ;; simple and disjoint at this stage; a probe lying exactly on another loop
  ;; is treated as outside rather than making containment depend on epsilon.
  (for/fold ([inside? #f])
            ([first (in-list polygon)]
             [second (in-list (append (cdr polygon) (list (car polygon))))])
    (define first-y (vector-ref first 1))
    (define second-y (vector-ref second 1))
    (define crosses?
      (not (eq? (> first-y (vector-ref point 1))
                (> second-y (vector-ref point 1)))))
    (define x-at-y
      (if (= first-y second-y)
          +inf.0
          (+ (vector-ref first 0)
             (* (- (vector-ref point 1) first-y)
                (/ (- (vector-ref second 0) (vector-ref first 0))
                   (- second-y first-y))))))
    (if (and crosses? (< (vector-ref point 0) x-at-y))
        (not inside?)
        inside?)))
