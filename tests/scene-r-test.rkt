#lang racket/base

;;;
;;; SCENE-R Sampled Function Graph Tests
;;;

;; Tests deterministic sampling, gaps, clipping, jump handling, axes alignment,
;; validation, path-Visual construction, and ordinary path animation behavior.


;;;
;;; Imports
;;;

(require rackunit
         "../main.rkt")


(module+ test
  ; unit-axes : axes-visual?
  ;;   Gives axes whose numeric and local geometric units are equal.
  (define unit-axes
    (axes #:id 'unit-axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -2 2 1)
          #:x-length 4
          #:y-length 4
          #:x-tip? #f
          #:y-tip? #f))

  ;; Uniform sampling includes both endpoints and preserves increasing order.
  ; linear-path : path-geometry?
  ;;   Gives five exact samples of y = x.
  (define linear-path
    (sample-function-path unit-axes
                          values
                          #:sample-count 5))

  (check-equal?
   (path-geometry-subpath-points linear-path)
   (list
    (list (vec2 -2 -2)
          (vec2 -1 -1)
          origin
          (vec2 1 1)
          (vec2 2 2))))

  ; sampled-xs : (box/c (listof finite-real?))
  ;;   Records one complete sampling traversal in reverse call order.
  (define sampled-xs
    (box '()))

  (void
   (sample-function-path
    unit-axes
    (lambda (x)
      (set-box! sampled-xs
                (cons x (unbox sampled-xs)))
      x)
    #:sample-count 5))

  (check-equal? (reverse (unbox sampled-xs))
                (list -2 -1 0 1 2))

  ;; A false or non-finite result creates an explicit break instead of a line.
  ; broken-path : path-geometry?
  ;;   Gives two disconnected line runs around x = 0.
  (define broken-path
    (sample-function-path
     unit-axes
     (lambda (x)
       (if (zero? x)
           #f
           x))
     #:sample-count 5))

  (check-equal?
   (path-geometry-subpath-points broken-path)
   (list
    (list (vec2 -2 -2)
          (vec2 -1 -1))
    (list (vec2 1 1)
          (vec2 2 2))))

  ; nonfinite-path : path-geometry?
  ;;   Gives the same two runs when the missing value is positive infinity.
  (define nonfinite-path
    (sample-function-path
     unit-axes
     (lambda (x)
       (if (zero? x)
           +inf.0
           x))
     #:sample-count 5))

  (check-equal? nonfinite-path broken-path)

  ; negative-infinity-path : path-geometry?
  ;;   Gives the same runs when the missing value is negative infinity.
  (define negative-infinity-path
    (sample-function-path
     unit-axes
     (lambda (x)
       (if (zero? x)
           -inf.0
           x))
     #:sample-count 5))

  ; nan-path : path-geometry?
  ;;   Gives the same runs when the missing value is NaN.
  (define nan-path
    (sample-function-path
     unit-axes
     (lambda (x)
       (if (zero? x)
           +nan.0
           x))
     #:sample-count 5))

  (check-equal? negative-infinity-path broken-path)
  (check-equal? nan-path broken-path)

  ; isolated-sample-path : path-geometry?
  ;;   Gives no visible path when only one sample is finite.
  (define isolated-sample-path
    (sample-function-path
     unit-axes
     (lambda (x)
       (if (zero? x)
           0
           #f))
     #:sample-count 3))

  (check-true (path-geometry-empty? isolated-sample-path))

  ;; Clipping trims line segments to the displayed axes rectangle.
  ; clipping-axes : axes-visual?
  ;;   Gives a two-by-two coordinate rectangle.
  (define clipping-axes
    (axes #:id 'clipping-axes
          #:x-range (axis-range -1 1 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 2
          #:y-length 2
          #:x-tip? #f
          #:y-tip? #f))

  ; clipped-path : path-geometry?
  ;;   Gives the visible part of y = 2x inside the coordinate rectangle.
  (define clipped-path
    (sample-function-path clipping-axes
                          (lambda (x) (* 2 x))
                          #:sample-count 3))

  (check-equal?
   (path-geometry-subpath-points clipped-path)
   (list
    (list (vec2 -1/2 -1)
          origin
          (vec2 1/2 1))))

  ; unclipped-path : path-geometry?
  ;;   Gives the same samples without rectangular clipping.
  (define unclipped-path
    (sample-function-path clipping-axes
                          (lambda (x) (* 2 x))
                          #:sample-count 3
                          #:clip? #f))

  (check-equal?
   (path-geometry-subpath-points unclipped-path)
   (list
    (list (vec2 -1 -2)
          origin
          (vec2 1 2))))

  ;; Clipping switches to exact represented values when an inexact difference
  ;; would overflow. The visible boundary segment is retained.
  ; extreme-path : path-geometry?
  ;;   Gives a line crossing the box between very large finite y values.
  (define extreme-path
    (sample-function-path
     clipping-axes
     (lambda (x)
       (if (negative? x)
           -1e308
           1e308))
     #:sample-count 2))

  ; extreme-points : (listof vec2?)
  ;;   Gives the two clipped boundary endpoints.
  (define extreme-points
    (car
     (path-geometry-subpath-points extreme-path)))

  (check-equal? (length extreme-points) 2)
  (check-equal? (vec2-y (car extreme-points)) -1)
  (check-equal? (vec2-y (car (cdr extreme-points))) 1)

  ;; Sampling bounds may exceed the displayed range; clipping still uses axes.
  ; extended-domain-path : path-geometry?
  ;;   Gives y = 0 clipped from x = -2 through x = 2 to the displayed range.
  (define extended-domain-path
    (sample-function-path clipping-axes
                          (lambda (_x) 0)
                          #:x-min -2
                          #:x-max 2
                          #:sample-count 3))

  (check-equal?
   (path-geometry-subpath-points extended-domain-path)
   (list
    (list (vec2 -1 0)
          origin
          (vec2 1 0))))

  ;; An explicit maximum jump can prevent a connection across a discontinuity.
  ; jump-axes : axes-visual?
  ;;   Gives a tall range that retains both step-function levels.
  (define jump-axes
    (axes #:id 'jump-axes
          #:x-range (axis-range -1 1 1)
          #:y-range (axis-range -20 20 10)
          #:x-length 2
          #:y-length 4
          #:x-tip? #f
          #:y-tip? #f))

  ; jump-path : path-geometry?
  ;;   Gives only the non-jumping right-hand run.
  (define jump-path
    (sample-function-path
     jump-axes
     (lambda (x)
       (if (negative? x) -10 10))
     #:sample-count 3
     #:max-jump 5))

  (check-equal?
   (path-geometry-subpath-points jump-path)
   (list
    (list (vec2 0 1)
          (vec2 1 1))))

  ; connected-jump-path : path-geometry?
  ;;   Gives the same samples connected when no jump threshold is requested.
  (define connected-jump-path
    (sample-function-path
     jump-axes
     (lambda (x)
       (if (negative? x) -10 10))
     #:sample-count 3))

  (check-equal?
   (path-geometry-subpath-points connected-jump-path)
   (list
    (list (vec2 -1 -1)
          (vec2 0 1)
          (vec2 1 1))))

  ;; Invalid procedure results and sampling failures remain visible errors.
  (check-exn
   #rx"must return a real number or #f"
   (lambda ()
     (sample-function-path unit-axes
                           (lambda (_x) 'not-a-number)
                           #:sample-count 2)))

  (check-exn
   #rx"sampling procedure raised an exception"
   (lambda ()
     (sample-function-path
      unit-axes
      (lambda (_x)
        (error 'sample "deliberate failure"))
      #:sample-count 2)))

  (check-exn
   #rx"must return exactly one value"
   (lambda ()
     (sample-function-path
      unit-axes
      (lambda (_x)
        (values 1 2))
      #:sample-count 2)))

  ;; Public sampling arguments are validated before procedure invocation.
  (check-exn exn:fail:contract?
             (lambda ()
               (sample-function-path 'not-axes values)))
  (check-exn exn:fail:contract?
             (lambda ()
               (sample-function-path unit-axes
                                     (lambda () 0))))
  (check-exn exn:fail:contract?
             (lambda ()
               (sample-function-path unit-axes
                                     values
                                     #:sample-count 1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (sample-function-path unit-axes
                                     values
                                     #:clip? 'yes)))
  (check-exn exn:fail:contract?
             (lambda ()
               (sample-function-path unit-axes
                                     values
                                     #:max-jump -1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (sample-function-path unit-axes
                                     values
                                     #:x-min 1
                                     #:x-max 1)))

  ;; Graph identity and style are checked before the sampling procedure runs.
  ; sampling-call-count : (box/c exact-nonnegative-integer?)
  ;;   Counts calls made by one procedure used with invalid graph metadata.
  (define sampling-call-count
    (box 0))

  ; counted-function : finite-real? -> finite-real?
  ;;   Records one invocation and returns its input.
  (define (counted-function x)
    (set-box! sampling-call-count
              (add1 (unbox sampling-call-count)))
    x)

  (check-exn exn:fail:contract?
             (lambda ()
               (function-graph unit-axes
                               counted-function
                               #:id "not-a-symbol")))
  (check-equal? (unbox sampling-call-count) 0)
  (check-exn exn:fail:contract?
             (lambda ()
               (function-graph unit-axes
                               values
                               #:id 'invalid-opacity
                               #:opacity 2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (function-graph unit-axes
                               values
                               #:id 'invalid-stroke
                               #:stroke-width -1)))

  ;; function-graph returns an ordinary path Visual with an axes transform
  ;; snapshot. Existing path operations therefore work without graph-specific
  ;; animation code.
  ; transformed-axes : axes-visual?
  ;;   Gives translated, rotated, and non-uniformly scaled axes.
  (define transformed-axes
    (axes #:id 'transformed-axes
          #:center (vec2 3 -2)
          #:rotation 1/4
          #:scale (vec2 2 1/2)
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 8
          #:y-length 2
          #:x-tip? #f
          #:y-tip? #f))

  ; graph : path-visual?
  ;;   Gives y = x/2 aligned with transformed-axes.
  (define graph
    (function-graph transformed-axes
                    (lambda (x) (/ x 2))
                    #:id 'graph
                    #:sample-count 5
                    #:opacity 3/4
                    #:stroke "crimson"
                    #:stroke-width 4))

  (check-true (path-visual? graph))
  (check-equal? (visual-id graph) 'graph)
  (check-equal? (visual-transform graph)
                (visual-transform transformed-axes))
  (check-equal? (visual-opacity graph) 3/4)
  (check-equal? (path-visual-fill graph) #f)
  (check-equal? (path-visual-stroke graph) "crimson")
  (check-equal? (path-visual-stroke-width graph) 4)

  ; graph-local-end : vec2?
  ;;   Gives the local endpoint representing numeric coordinate (2, 1).
  (define graph-local-end
    (car
     (reverse
      (car
       (path-geometry-subpath-points
        (path-visual-path graph))))))

  (check-equal? graph-local-end
                (vec2 4 1))

  ; graph-end : vec2?
  ;;   Gives that endpoint after the copied graph transform.
  (define graph-end
    (affine-transform-apply-point
     (visual-transform graph)
     graph-local-end))

  ; axes-end : vec2?
  ;;   Gives the same numeric coordinate through the axes conversion API.
  (define axes-end
    (axes-coordinates->point transformed-axes 2 1))

  (check-= (vec2-x graph-end)
           (vec2-x axes-end)
           1e-12)
  (check-= (vec2-y graph-end)
           (vec2-y axes-end)
           1e-12)

  ;; A graph is a path Visual and participates in Create directly.
  ; graph-creation : scene?
  ;;   Creates graph over one second from an initially empty path.
  (define graph-creation
    (scene-play (make-scene)
                (create graph)
                #:duration 1))

  (check-true
   (path-geometry-empty?
    (path-visual-path
     (scene-state-ref
      (scene-sample graph-creation 0)
      'graph))))
  (check-false
   (path-geometry-empty?
    (path-visual-path
     (scene-state-ref
      (scene-sample graph-creation 1/2)
      'graph))))
  (check-equal?
   (scene-state-ref
    (scene-sample graph-creation 1)
    'graph)
   graph))
