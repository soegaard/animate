#lang racket/base

;;; SCENE-3D-I Plane Section Topology Tests

(require rackunit
         "../3d.rkt")

(module+ test
  (define cube (cube3d 2 #:id 'cube))
  (define plane (plane3 origin3 x-axis3))
  (define section (section-by-plane3d cube plane))

  ;; The cube's central cut is one closed square.  Triangle boundaries may add
  ;; collinear samples, but never a second component or an open chain.
  (check-true (section3d? section))
  (check-equal? (length (section3d-loops section)) 1)
  (check-equal? (section3d-chains section) '())
  (check-true (>= (length (car (section3d-loops section))) 4))
  (for ([point (in-list (car (section3d-loops section)))])
    (check-true (<= (abs (vec3-x point)) 1e-7)))

  ;; Section geometry can be put directly into a spatial view without guessing
  ;; that every input has exactly one loop.
  (define curves (section-curve3d cube plane #:id 'cut))
  (check-true (group3d? curves))
  (check-equal? (length (group3d-children curves)) 1)

  ;; Section curves retain a source mesh's authored placement envelope.
  (define shifted
    (cube3d 2 #:id 'shifted
            #:transform (make-transform3 #:translation (vec3 3 0 0))))
  (check-equal? (spatial-position (section-curve3d shifted plane #:id 'shifted-cut))
                (vec3 3 0 0)))
