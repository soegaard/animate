#lang racket/base

;;;
;;; SCENE-DQ Robust Pointwise Map Tests
;;;

(require racket/list
         rackunit
         "../main.rkt"
         "../private/pointwise-map.rkt")

(module+ test
  (define (square-map point)
    (define x (vec2-x point))
    (define y (vec2-y point))
    (vec2 (- (* x x) (* y y)) (* 2 x y)))

  ;; Adaptive subdivision inserts points where a single mapped chord would
  ;; visibly miss the curved image of this line under z -> z^2.
  (define curved
    (pointwise-map-visual
     (line (vec2 -1 1) (vec2 1 1) #:id 'curve)
     square-map 1
     #:samples 1 #:tolerance 1/128 #:max-depth 8))
  (define curved-points
    (car (path-geometry-subpath-points (path-visual-path curved))))
  (check-true (> (length curved-points) 2))
  (check-equal? (car curved-points) (vec2 0 -2))
  (check-equal? (last curved-points) (vec2 0 2))

  ;; A failed sample is a discontinuity, not an instruction to draw one long
  ;; chord through a pole. Both surviving branches stay on their own side.
  (define (reciprocal-x point)
    (define x (vec2-x point))
    (if (zero? x)
        (error 'reciprocal-x "pole")
        (vec2 (/ 1 x) (vec2-y point))))
  (define split-curve
    (pointwise-map-visual
     (line (vec2 -1 0) (vec2 1 0) #:id 'reciprocal)
     reciprocal-x 1
     #:samples 1 #:tolerance 1/32 #:max-depth 8
     #:discontinuities 'split))
  (define split-subpaths
    (path-geometry-subpaths (path-visual-path split-curve)))
  (check-equal? (length split-subpaths) 2)
  (for ([subpath (in-list split-subpaths)])
    (define xs
      (map vec2-x (path-subpath-points subpath)))
    (check-true (or (andmap negative? xs) (andmap positive? xs))))
  (check-exn
   exn:fail?
   (lambda ()
     (pointwise-map-visual
      (line (vec2 -1 0) (vec2 1 0) #:id 'strict)
      reciprocal-x 1 #:samples 1 #:discontinuities 'error)))

  ;; The complex wrapper shares the same splitting policy, while retaining its
  ;; stricter default for accidental non-complex results.
  (define complex-pole
    (scene-play
     (scene-add (make-scene)
                (line (vec2 -1 0) (vec2 1 0) #:id 'complex-pole))
     (apply-complex-function
      'complex-pole
      (lambda (z)
        (if (zero? z) (error 'complex-reciprocal "pole") (/ 1 z)))
      #:samples 1 #:max-depth 7 #:discontinuities 'split)
     #:duration 1))
  (check-equal?
   (length
    (path-geometry-subpaths
     (path-visual-path (scene-visual-at complex-pole 'complex-pole 1))))
   2)

  ;; Differential inspection agrees with the analytic Jacobian of z -> z^2.
  (check-equal?
   (pointwise-jacobian square-map (vec2 1 2) #:step 1/1000)
   (linear2 2 -4 4 2))
  (check-equal?
   (pointwise-jacobian-determinant square-map (vec2 1 2) #:step 1/1000)
   20)
  (check-equal?
   (pointwise-orientation (lambda (point) (vec2 (- (vec2-x point))
                                                    (vec2-y point)))
                          (vec2 0 0))
   'reversing)

  ;; An inverse-map mesh is just an ordinary semantic group of mapped lines.
  (define mesh
    (inverse-map-mesh
     (lambda (point) point)
     #:id 'mesh #:x-count 3 #:y-count 3 #:samples 1))
  (check-true (group-visual? mesh))
  (check-equal? (length (group-visual-children mesh)) 6)

  ;; Domain colour is a finite semantic RGBA value, independent of a backend.
  (check-true (rgba-color? (complex-domain-color 0+1i)))
  (define colouring
    (complex-domain-coloring (lambda (z) (* z z))
                             #:id 'colouring #:columns 3 #:rows 2))
  (check-true (group-visual? colouring))
  (check-equal? (length (group-visual-children colouring)) 6))
