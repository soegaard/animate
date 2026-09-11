#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide parallel-at-distance example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction parallel-at-distance
  (given [l (line (point -3 -1) (point 3 -1))] [A (point 0 -1)]
         [unit (segment (point -3 -2) (point -1.5 -2))])
  (layout (focus A P) (label-side A 'below-right) (label-side P 'above-right))
  (style [l [color axis]] [m [color-family gold]])
  (step "Choose A on the given line and construct the perpendicular there."
    (expand [n (c:erect-perpendicular l A)] #:auxiliaries 'hide))
  (step "Copy the prescribed distance along this perpendicular."
    (expand [P (c:copy-segment unit (ray A (end-point n)))] #:auxiliaries 'hide))
  (step "Through P, construct the parallel to the original line."
    [m (c:parallel-through-point l P)])
  (step "The perpendicular segment AP measures the distance between the parallels."
    [AP (segment A P)]
    [corner (marker (perpendicular l AP #:at A))]
    [arrows (marker (parallel l m))]
    (hide n))
  (assert (parallel l m) (on A l) (on P m)
          (equal-length unit AP) (perpendicular l AP #:at A))
  (result A P AP l m))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline parallel-at-distance #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "parallel-at-distance"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
