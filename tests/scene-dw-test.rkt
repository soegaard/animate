#lang racket/base

;;;
;;; SCENE-DW Time-Dependent Homotopy Tests
;;;

(require racket/list
         rackunit
         "../main.rkt")

(define (visual-points visual)
  (car (path-geometry-subpath-points (path-visual-path visual))))

(module+ test
  ;; Squaring alpha makes the midpoint distinguish a genuine homotopy from
  ;; endpoint-map interpolation: H((0, 1), 1/2) ends at x = 1/4, whereas an
  ;; endpoint map blended at 1/2 would incorrectly give x = 1/2.
  (define vertical
    (line (vec2 0 0) (vec2 0 1) #:id 'vertical #:stroke "navy"))
  (define shear-homotopy
    (lambda (point alpha)
      (vec2 (+ (vec2-x point)
               (* alpha alpha (vec2-y point)))
            (vec2-y point))))
  (define homotopy-scene
    (scene-play
     (scene-add (make-scene) vertical)
     (apply-homotopy 'vertical shear-homotopy #:samples 1 #:adaptive? #f)
     #:duration 2))

  ;; The exact author-provided source remains in the scene at the clip start.
  (check-equal? (scene-visual-at homotopy-scene 'vertical 0) vertical)
  (define midpoint
    (scene-visual-at homotopy-scene 'vertical 1))
  (check-true (path-visual? midpoint))
  (check-equal? (visual-points midpoint)
                (list (vec2 0 0) (vec2 1/4 1)))
  (define endpoint
    (scene-visual-at homotopy-scene 'vertical 2))
  (check-equal? (visual-points endpoint)
                (list (vec2 0 0) (vec2 1 1)))

  ;; Sampling order does not enter the result: each time evaluates the same
  ;; source and local alpha without retaining frame history.
  (check-equal?
   (scene-visual-at homotopy-scene 'vertical 1)
   midpoint)
  (check-equal?
   (scene-visual-at homotopy-scene 'vertical 1/2)
   (scene-visual-at homotopy-scene 'vertical 1/2))

  ;; A nested target is mapped in world coordinates, then correctly rebased
  ;; into its enclosing group without altering its sibling.
  (define guide
    (line (vec2 0 -1) (vec2 1 -1) #:id 'guide #:stroke "gray"))
  (define nested-scene
    (scene-play
     (scene-add
      (make-scene)
      (group (list vertical guide) #:id 'diagram #:center (vec2 2 0)))
     (apply-homotopy '(diagram vertical) shear-homotopy
                       #:samples 1 #:adaptive? #f)
     #:duration 1))
  (define rebased-curve
    (scene-visual-at nested-scene '(diagram vertical) 1))
  (check-true (affine-map-visual? rebased-curve))
  (define world-curve (affine-map-visual-content rebased-curve))
  (check-equal? (visual-points world-curve)
                (list (vec2 2 0) (vec2 3 1)))
  (check-equal? (scene-visual-at nested-scene '(diagram guide) 1) guide)

  ;; Failed phase samples honour the established split/error policy instead of
  ;; drawing a false chord through a singularity.
  (define split-scene
    (scene-play
     (scene-add (make-scene)
                (line (vec2 -1 0) (vec2 1 0) #:id 'split-line))
     (apply-homotopy
      'split-line
      (lambda (point alpha)
        (if (and (positive? alpha) (zero? (vec2-x point)))
            (error 'split-homotopy "pole")
            point))
      #:samples 1 #:max-depth 7 #:discontinuities 'split)
     #:duration 1))
  (define split-result (scene-visual-at split-scene 'split-line 1))
  (check-equal?
   (length (path-geometry-subpaths (path-visual-path split-result)))
   2)
  (check-exn
   exn:fail?
   (lambda ()
     (apply-homotopy 'vertical (lambda (_point) origin))))

  ;; The complex wrapper shares the same direct-at-phase rule and validates
  ;; its complex result before returning to world-space geometry.
  (define complex-scene
    (scene-play
     (scene-add (make-scene)
                (line (vec2 0 0) (vec2 0 1) #:id 'complex-line))
     (apply-complex-homotopy
      'complex-line
      (lambda (z alpha) (+ z (* alpha alpha)))
      #:samples 1 #:adaptive? #f)
     #:duration 2))
  (check-equal?
   (visual-points (scene-visual-at complex-scene 'complex-line 1))
   (list (vec2 1/4 0) (vec2 1/4 1)))
  (check-exn
   exn:fail?
   (lambda ()
     (scene-visual-at
      (scene-play
       (scene-add (make-scene) vertical)
       (apply-complex-homotopy 'vertical
                                (lambda (_z _alpha) "not complex"))
       #:duration 1)
      'vertical
      1))))
