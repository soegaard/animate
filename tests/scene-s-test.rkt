#lang racket/base

;;;
;;; SCENE-S Parametric Curve and Data Plot Tests
;;;

;; Tests ordered parameter domains, coordinate-valued sampling, point-series
;; gaps, explicit interpolation, clipping, transform snapshots, and timelines.


;;;
;;; Imports
;;;

(require rackunit
         "../main.rkt")


(module+ test
  ;; Parameter ranges preserve traversal direction and reject unusable spans.
  ; forward-domain : parameter-range?
  ;;   Gives an increasing closed parameter domain.
  (define forward-domain
    (parameter-range -1 1))

  ; reverse-domain : parameter-range?
  ;;   Gives the same endpoints in decreasing traversal order.
  (define reverse-domain
    (parameter-range 1 -1))

  (check-equal? (parameter-range-start forward-domain) -1)
  (check-equal? (parameter-range-end forward-domain) 1)
  (check-equal? (parameter-range-start reverse-domain) 1)
  (check-equal? (parameter-range-end reverse-domain) -1)
  (check-exn exn:fail:contract?
             (lambda ()
               (parameter-range 1 1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (parameter-range -1e308 1e308)))

  ;; Interpolation names are explicit and closed.
  (check-true (curve-interpolation? 'linear))
  (check-true (curve-interpolation? 'smooth))
  (check-false (curve-interpolation? 'spline))
  (check-false (curve-interpolation? "smooth"))

  ; unit-axes : axes-visual?
  ;;   Gives axes whose numeric and local coordinate units are identical.
  (define unit-axes
    (axes #:id 'unit-axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -2 2 1)
          #:x-length 4
          #:y-length 4
          #:stroke-width 0
          #:tick-size 0
          #:x-tip? #f
          #:y-tip? #f))

  ;; Parametric sampling includes both endpoints and follows domain order.
  ; sampled-parameters : (box/c (listof finite-real?))
  ;;   Records parameter values in procedure-call order.
  (define sampled-parameters
    (box '()))

  ; reverse-parabola-path : path-geometry?
  ;;   Gives a decreasing traversal of the parabola from t = 1 to t = -1.
  (define reverse-parabola-path
    (sample-parametric-path
     unit-axes
     (lambda (parameter)
       (set-box! sampled-parameters
                 (cons parameter (unbox sampled-parameters)))
       (vec2 parameter (* parameter parameter)))
     #:parameter-range reverse-domain
     #:sample-count 3))

  (check-equal? (reverse (unbox sampled-parameters))
                '(1 0 -1))
  (check-equal?
   (path-geometry-subpath-points reverse-parabola-path)
   (list
    (list (vec2 1 1)
          (vec2 0 0)
          (vec2 -1 1))))

  ;; Explicit #f values split parametric runs without retaining the procedure.
  ; broken-parametric-path : path-geometry?
  ;;   Gives two line runs separated at parameter zero.
  (define broken-parametric-path
    (sample-parametric-path
     unit-axes
     (lambda (parameter)
       (if (zero? parameter)
           #f
           (vec2 parameter parameter)))
     #:parameter-range forward-domain
     #:sample-count 5))

  (check-equal?
   (path-geometry-subpath-points broken-parametric-path)
   (list
    (list (vec2 -1 -1)
          (vec2 -1/2 -1/2))
    (list (vec2 1/2 1/2)
          (vec2 1 1))))

  ;; Procedure result shape and failures remain visible at the sampling boundary.
  (check-exn
   #rx"must return a vec2 value or #f"
   (lambda ()
     (sample-parametric-path unit-axes
                             (lambda (_parameter) 1)
                             #:sample-count 2)))
  (check-exn
   #rx"must return exactly one value"
   (lambda ()
     (sample-parametric-path
      unit-axes
      (lambda (_parameter)
        (values origin origin))
      #:sample-count 2)))
  (check-exn
   #rx"sampling procedure raised an exception"
   (lambda ()
     (sample-parametric-path
      unit-axes
      (lambda (_parameter)
        (error 'parametric "deliberate failure"))
      #:sample-count 2)))

  ;; Invalid interpolation is rejected before the sampling procedure is called.
  ; invalid-option-call-count : (box/c exact-nonnegative-integer?)
  ;;   Counts calls made by a procedure supplied with an invalid option.
  (define invalid-option-call-count
    (box 0))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (sample-parametric-path
      unit-axes
      (lambda (parameter)
        (set-box! invalid-option-call-count
                  (add1 (unbox invalid-option-call-count)))
        (vec2 parameter 0))
      #:sample-count 2
      #:interpolation 'spline)))
  (check-equal? (unbox invalid-option-call-count) 0)
  (check-exn
   exn:fail:contract?
   (lambda ()
     (sample-function-path unit-axes
                           values
                           #:sample-count 2
                           #:interpolation 'spline)))

  ;; Ordered data input preserves explicit gaps and does not reorder x values.
  ; broken-data-path : path-geometry?
  ;;   Gives two data runs in their supplied traversal order.
  (define broken-data-path
    (data-series-path
     unit-axes
     (list (vec2 1 0)
           (vec2 0 1)
           #f
           (vec2 -1 0)
           (vec2 0 -1))))

  (check-equal?
   (path-geometry-subpath-points broken-data-path)
   (list
    (list (vec2 1 0)
          (vec2 0 1))
    (list (vec2 -1 0)
          (vec2 0 -1))))

  (check-true
   (path-geometry-empty?
    (data-series-path unit-axes '())))
  (check-true
   (path-geometry-empty?
    (data-series-path unit-axes (list origin))))
  (check-exn exn:fail:contract?
             (lambda ()
               (data-series-path unit-axes
                                 (list origin 'bad-point))))

  ;; Maximum distance is Euclidean in numeric-coordinate units.
  ; limited-data-path : path-geometry?
  ;;   Keeps only the first adjacent pair within distance one.
  (define limited-data-path
    (data-series-path
     unit-axes
     (list origin
           (vec2 1 0)
           (vec2 3 0))
     #:clip? #f
     #:max-distance 1))

  (check-equal?
   (path-geometry-subpath-points limited-data-path)
   (list
    (list origin
          (vec2 1 0))))

  ; limited-parametric-path : path-geometry?
  ;;   Applies the same Euclidean threshold to adjacent parametric samples.
  (define limited-parametric-path
    (sample-parametric-path
     unit-axes
     (lambda (parameter)
       (if (= parameter 2)
           (vec2 3 0)
           (vec2 parameter 0)))
     #:parameter-range (parameter-range 0 2)
     #:sample-count 3
     #:clip? #f
     #:max-distance 1))

  (check-equal?
   (path-geometry-subpath-points limited-parametric-path)
   (list
    (list origin
          (vec2 1 0))))

  ;; Segment clipping creates exact boundary endpoints before interpolation.
  ; clipping-axes : axes-visual?
  ;;   Gives a two-by-two visible coordinate rectangle.
  (define clipping-axes
    (axes #:id 'clipping-axes
          #:x-range (axis-range -1 1 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 2
          #:y-length 2
          #:stroke-width 0
          #:tick-size 0
          #:x-tip? #f
          #:y-tip? #f))

  ; clipped-data-path : path-geometry?
  ;;   Gives the visible portion of one horizontal segment.
  (define clipped-data-path
    (data-series-path clipping-axes
                      (list (vec2 -2 0)
                            (vec2 2 0))))

  (check-equal?
   (path-geometry-subpath-points clipped-data-path)
   (list
    (list (vec2 -1 0)
          (vec2 1 0))))

  ;; Numeric coordinates use the axes' independent local unit lengths.
  ; anisotropic-axes : axes-visual?
  ;;   Gives two local x units and one local y unit per numeric coordinate.
  (define anisotropic-axes
    (axes #:id 'anisotropic-axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -2 2 1)
          #:x-length 8
          #:y-length 4
          #:stroke-width 0
          #:tick-size 0
          #:x-tip? #f
          #:y-tip? #f))

  (check-equal?
   (path-geometry-subpath-points
    (data-series-path anisotropic-axes
                      (list origin (vec2 1 1))
                      #:clip? #f))
   (list
    (list origin
          (vec2 2 1))))

  ;; Linear and smooth modes produce explicit line and cubic segment kinds.
  ; interpolation-points : (listof vec2?)
  ;;   Gives three points for exact Catmull-Rom control checks.
  (define interpolation-points
    (list origin
          (vec2 1 1)
          (vec2 2 0)))

  ; linear-data-path : path-geometry?
  ;;   Gives piecewise-linear interpolation through interpolation-points.
  (define linear-data-path
    (data-series-path unit-axes
                      interpolation-points
                      #:clip? #f
                      #:interpolation 'linear))

  ; smooth-data-path : path-geometry?
  ;;   Gives Catmull-Rom cubic interpolation through the same points.
  (define smooth-data-path
    (data-series-path unit-axes
                      interpolation-points
                      #:clip? #f
                      #:interpolation 'smooth))

  ; linear-segments : (listof line-path-segment?)
  ;;   Gives the stored segments of linear-data-path.
  (define linear-segments
    (path-subpath-segments
     (car (path-geometry-subpaths linear-data-path))))

  ; smooth-segments : (listof cubic-bezier-path-segment?)
  ;;   Gives the stored segments of smooth-data-path.
  (define smooth-segments
    (path-subpath-segments
     (car (path-geometry-subpaths smooth-data-path))))

  (check-true (andmap line-path-segment? linear-segments))
  (check-true (andmap cubic-bezier-path-segment? smooth-segments))
  (check-equal?
   (path-geometry-subpath-points smooth-data-path)
   (list interpolation-points))
  (check-equal?
   (cubic-bezier-path-segment-control1 (car smooth-segments))
   (vec2 1/6 1/6))
  (check-equal?
   (cubic-bezier-path-segment-control2 (car smooth-segments))
   (vec2 2/3 1))

  ;; A two-point smooth run remains exactly collinear through one cubic.
  ; two-point-smooth-path : path-geometry?
  ;;   Gives a straight cubic from zero to three.
  (define two-point-smooth-path
    (data-series-path unit-axes
                      (list origin (vec2 3 0))
                      #:clip? #f
                      #:interpolation 'smooth))

  ; two-point-segment : cubic-bezier-path-segment?
  ;;   Gives the one line-equivalent cubic segment.
  (define two-point-segment
    (car
     (path-subpath-segments
      (car (path-geometry-subpaths two-point-smooth-path)))))

  (check-equal?
   (cubic-bezier-path-segment-control1 two-point-segment)
   (vec2 1 0))
  (check-equal?
   (cubic-bezier-path-segment-control2 two-point-segment)
   (vec2 2 0))

  ;; Smooth clipping clamps controls to the convex visible rectangle.
  ; corner-points : (listof vec2?)
  ;;   Gives a turn whose unconstrained middle tangent leaves the x range.
  (define corner-points
    (list (vec2 -1 0)
          (vec2 1 0)
          (vec2 1 1)
          (vec2 -1 1)))

  ; unclipped-smooth : path-geometry?
  ;;   Keeps the original overshooting Catmull-Rom control point.
  (define unclipped-smooth
    (data-series-path clipping-axes
                      corner-points
                      #:clip? #f
                      #:interpolation 'smooth))

  ; clipped-smooth : path-geometry?
  ;;   Clamps smooth controls after clipping the sample segments.
  (define clipped-smooth
    (data-series-path clipping-axes
                      corner-points
                      #:interpolation 'smooth))

  ; unclipped-middle : cubic-bezier-path-segment?
  ;;   Gives the middle cubic before control clamping.
  (define unclipped-middle
    (cadr
     (path-subpath-segments
      (car (path-geometry-subpaths unclipped-smooth)))))

  ; clipped-middle : cubic-bezier-path-segment?
  ;;   Gives the middle cubic after control clamping.
  (define clipped-middle
    (cadr
     (path-subpath-segments
      (car (path-geometry-subpaths clipped-smooth)))))

  (check-equal?
   (vec2-x (cubic-bezier-path-segment-control1 unclipped-middle))
   4/3)
  (check-equal?
   (vec2-x (cubic-bezier-path-segment-control1 clipped-middle))
   1)

  ;; Existing function graphs retain linear defaults and gain smooth mode.
  ; default-function-path : path-geometry?
  ;;   Gives the original piecewise-linear function-graph behavior.
  (define default-function-path
    (sample-function-path unit-axes
                          (lambda (x) (* x x))
                          #:x-min -1
                          #:x-max 1
                          #:sample-count 3))

  ; smooth-function-path : path-geometry?
  ;;   Gives smooth cubic interpolation through the same function samples.
  (define smooth-function-path
    (sample-function-path unit-axes
                          (lambda (x) (* x x))
                          #:x-min -1
                          #:x-max 1
                          #:sample-count 3
                          #:interpolation 'smooth))

  (check-true
   (andmap line-path-segment?
           (path-subpath-segments
            (car (path-geometry-subpaths default-function-path)))))
  (check-true
   (andmap cubic-bezier-path-segment?
           (path-subpath-segments
            (car (path-geometry-subpaths smooth-function-path)))))

  ; smooth-function-graph : path-visual?
  ;;   Gives the public graph wrapper with smooth cubic geometry.
  (define smooth-function-graph
    (function-graph unit-axes
                    (lambda (x) (* x x))
                    #:id 'smooth-function-graph
                    #:x-min -1
                    #:x-max 1
                    #:sample-count 3
                    #:interpolation 'smooth))

  (check-true
   (andmap cubic-bezier-path-segment?
           (path-subpath-segments
            (car
             (path-geometry-subpaths
              (path-visual-path smooth-function-graph))))))

  ;; Plot constructors validate style before sampling and copy the axes transform.
  ; transformed-axes : axes-visual?
  ;;   Gives translated, rotated, and non-uniformly scaled axes.
  (define transformed-axes
    (axes #:id 'transformed-axes
          #:center (vec2 3 -2)
          #:rotation 1/4
          #:scale (vec2 2 1/2)
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -2 2 1)
          #:x-length 4
          #:y-length 4))

  ; sampled-call-count : (box/c exact-nonnegative-integer?)
  ;;   Counts calls to a procedure used with invalid plot metadata.
  (define sampled-call-count
    (box 0))

  ; counted-parametric : finite-real? -> vec2?
  ;;   Records one invocation and returns a horizontal coordinate.
  (define (counted-parametric parameter)
    (set-box! sampled-call-count
              (add1 (unbox sampled-call-count)))
    (vec2 parameter 0))

  (check-exn exn:fail:contract?
             (lambda ()
               (parametric-curve transformed-axes
                                 counted-parametric
                                 #:id "not-a-symbol")))
  (check-equal? (unbox sampled-call-count) 0)

  ; sampled-curve : path-visual?
  ;;   Gives one smooth transformed-axes snapshot.
  (define sampled-curve
    (parametric-curve transformed-axes
                      (lambda (parameter)
                        (vec2 parameter parameter))
                      #:id 'sampled-curve
                      #:parameter-range forward-domain
                      #:sample-count 3
                      #:interpolation 'smooth
                      #:stroke "crimson"
                      #:stroke-width 4))

  ; sampled-data-plot : path-visual?
  ;;   Gives one styled data-series axes snapshot.
  (define sampled-data-plot
    (data-plot transformed-axes
               interpolation-points
               #:id 'sampled-data-plot
               #:clip? #f
               #:opacity 3/4
               #:stroke "seagreen"
               #:stroke-width 5))

  (check-equal? (visual-transform sampled-curve)
                (visual-transform transformed-axes))
  (check-equal? (visual-transform sampled-data-plot)
                (visual-transform transformed-axes))
  (check-equal? (visual-opacity sampled-data-plot) 3/4)
  (check-equal? (path-visual-stroke sampled-curve) "crimson")
  (check-equal? (path-visual-stroke-width sampled-data-plot) 5)

  ;; Parametric and data plots remain ordinary path Visuals on the timeline.
  ; entrance : scene?
  ;;   Creates both paths over one second.
  (define entrance
    (scene-play (make-scene)
                (create sampled-curve)
                (create sampled-data-plot)
                #:duration 1))

  ; completed-state : scene-state?
  ;;   Gives the exact structural endpoint after both Create requests.
  (define completed-state
    (scene-sample entrance 1))

  (check-equal? (scene-state-count completed-state) 2)
  (check-true (path-visual?
               (scene-state-ref completed-state 'sampled-curve)))
  (check-true (path-visual?
               (scene-state-ref completed-state 'sampled-data-plot))))
