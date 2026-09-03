#lang racket/base

;;;
;;; SCENE-CQ Adaptive Function-Plot Tests
;;;

(require rackunit
         racket/list
         "../main.rkt")

(define (point-count path)
  (for/sum ([run (in-list (path-geometry-subpath-points path))])
    (length run)))

(define (run-on-one-side? run x)
  (or (andmap (lambda (point) (<= (vec2-x point) x)) run)
      (andmap (lambda (point) (>= (vec2-x point) x)) run)))

(module+ test
  (define plot-axes
    (axes #:id 'axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -3 3 1)
          #:x-length 4 #:y-length 6
          #:x-tip? #f #:y-tip? #f))

  ;; An exact division-by-zero evaluation is a gap for the adaptive sampler.
  ;; Refinement preserves both reciprocal branches instead of connecting them
  ;; across the visible plotting rectangle.
  (define reciprocal
    (sample-adaptive-function-path
     plot-axes (lambda (x) (/ 1 x))
     #:x-min -1 #:x-max 1
     #:initial-sample-count 5 #:max-depth 7 #:max-deviation 1/100))
  (define reciprocal-runs (path-geometry-subpath-points reciprocal))
  (check-equal? (length reciprocal-runs) 2)
  (check-true (andmap (lambda (run) (run-on-one-side? run 0)) reciprocal-runs))

  ;; Poles need not occur at an initial sample. The same midpoint/error rule
  ;; finds the two tangent poles and retains the three visible branches.
  (define tangent
    (sample-adaptive-function-path
     plot-axes tan
     #:x-min -2 #:x-max 2
     #:initial-sample-count 17 #:max-depth 10 #:max-deviation 1/100))
  (check-true (>= (length (path-geometry-subpath-points tangent)) 3))

  ;; A high-frequency but continuous curve receives substantially more samples
  ;; than its initial exploration grid when the chord-deviation bound demands
  ;; it. A sharp rational bend gets similar local refinement.
  (define oscillating
    (sample-adaptive-function-path
     plot-axes (lambda (x) (sin (* 30 x)))
     #:x-min -1 #:x-max 1
     #:initial-sample-count 17 #:max-depth 10 #:max-deviation 1/100))
  (check-true (> (point-count oscillating) 100))

  ;; Midpoint-only testing would accept this polynomial as a perfectly flat
  ;; chord: its endpoints and midpoint are all zero. Quarter probes expose its
  ;; two bends and force a subdivision.
  (define midpoint-alias
    (sample-adaptive-function-path
     plot-axes
     (lambda (x) (* x (- x 1/2) (- x 1)))
     #:x-min 0 #:x-max 1 #:initial-sample-count 2
     #:max-depth 5 #:max-deviation 1/100))
  (check-true (> (point-count midpoint-alias) 2))

  ;; A tighter display-space tolerance deliberately adds dense samples around
  ;; the peaks and troughs of the high-frequency stress curve.
  (define finely-oscillating
    (sample-adaptive-function-path
     plot-axes (lambda (x) (sin (* 30 x)))
     #:x-min -1 #:x-max 1
     #:initial-sample-count 17 #:max-depth 10 #:max-deviation 1/1000))
  (check-true (> (point-count finely-oscillating) 800))
  (define sharp-rational
    (sample-adaptive-function-path
     plot-axes (lambda (x) (/ 1 (+ 1 (* 100 x x))))
     #:x-min -1 #:x-max 1
     #:initial-sample-count 5 #:max-depth 10 #:max-deviation 1/100))
  (check-true (> (point-count sharp-rational) 20))

  ;; Exclusions split the requested domain before sampling, including an
  ;; explicit gap for a finite formula where no automatic discontinuity exists.
  (define excluded
    (sample-adaptive-function-path
     plot-axes values #:x-min -1 #:x-max 1
     #:excluded-intervals (list (cons -1/4 1/4))
     #:max-deviation 0))
  (define excluded-runs (path-geometry-subpath-points excluded))
  (check-equal? (length excluded-runs) 2)
  (check-true
   (andmap
    (lambda (run)
      (or (andmap (lambda (point) (<= (vec2-x point) -1/4)) run)
          (andmap (lambda (point) (>= (vec2-x point) 1/4)) run)))
    excluded-runs))

  ;; The visual wrapper is an ordinary immutable path Visual with the axes
  ;; transform copied at construction time, just like function-graph.
  (define plotted
    (adaptive-function-graph
     plot-axes (lambda (x) (* x x)) #:id 'adaptive
     #:max-deviation 1/100 #:stroke "purple" #:stroke-width 4))
  (check-true (path-visual? plotted))
  (check-equal? (visual-id plotted) 'adaptive)
  (check-equal? (visual-stroke-width plotted) 4)

  ;; Every control is validated before the callback can run.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (sample-adaptive-function-path plot-axes values #:max-depth -1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (sample-adaptive-function-path
      plot-axes values #:excluded-intervals (list (cons 1 -1)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (adaptive-function-graph plot-axes values #:id "not-a-symbol"))))
