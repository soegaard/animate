#lang racket/base

;;;
;;; SCENE-V Point Marker, Scatter, and Area Tests
;;;

;; Tests semantic marker values, deterministic scatter identities and order,
;; filled function and data areas, clipping, affine snapshots, and timelines.


;;;
;;; Imports
;;;

(require rackunit
         (only-in racket/list take)
         "../main.rkt")


(module+ test
  ;; Marker shape names form one explicit closed set.
  (for ([shape (in-list
                '(circle square diamond triangle-up triangle-down))])
    (check-true (point-marker-shape? shape)))
  (check-false (point-marker-shape? 'cross))
  (check-false (point-marker-shape? "circle"))

  ; marker : point-marker-visual?
  ;;   Gives one explicitly styled diamond marker.
  (define marker
    (point-marker #:id 'marker
                  #:center (vec2 2 -1)
                  #:rotation 1/4
                  #:scale (vec2 2 1/2)
                  #:opacity 3/4
                  #:shape 'diamond
                  #:size 2/5
                  #:fill "gold"
                  #:stroke "navy"
                  #:stroke-width 3))

  (check-true (point-marker-visual? marker))
  (check-equal? (visual-id marker) 'marker)
  (check-equal? (visual-position marker) (vec2 2 -1))
  (check-equal? (visual-rotation marker) 1/4)
  (check-equal? (visual-scale marker) (vec2 2 1/2))
  (check-equal? (visual-opacity marker) 3/4)
  (check-equal? (point-marker-visual-shape marker) 'diamond)
  (check-equal? (point-marker-visual-size marker) 2/5)
  (check-equal? (point-marker-visual-fill marker) "gold")
  (check-equal? (point-marker-visual-stroke marker) "navy")
  (check-equal? (point-marker-visual-stroke-width marker) 3)

  ; moved-marker : point-marker-visual?
  ;;   Gives marker after an immutable generic position update.
  (define moved-marker
    (visual-with-position marker origin))

  (check-true (point-marker-visual? moved-marker))
  (check-equal? (visual-id moved-marker) 'marker)
  (check-equal? (visual-position moved-marker) origin)
  (check-equal? (visual-position marker) (vec2 2 -1))

  (check-exn exn:fail:contract?
             (lambda ()
               (point-marker #:id 'bad
                             #:shape 'cross)))
  (check-exn exn:fail:contract?
             (lambda ()
               (point-marker #:id 'bad
                             #:size 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (point-marker #:id 'bad
                             #:stroke-width -1)))

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

  ;; Scatter input order is preserved while gaps and clipped points are omitted.
  ; scatter : group-visual?
  ;;   Gives three visible markers from five indexed input positions.
  (define scatter
    (scatter-plot unit-axes
                  (list (vec2 -1 -1)
                        #f
                        (vec2 0 1)
                        (vec2 3 0)
                        (vec2 2 2))
                  #:id 'samples
                  #:shape 'square
                  #:size 1/4))

  ; scatter-children : (listof point-marker-visual?)
  ;;   Gives visible markers in original input order.
  (define scatter-children
    (group-visual-children scatter))

  (check-equal? (map visual-id scatter-children)
                '(samples-marker-0
                  samples-marker-2
                  samples-marker-4))
  (check-equal? (map visual-position scatter-children)
                (list (vec2 -1 -1)
                      (vec2 0 1)
                      (vec2 2 2)))
  (check-true (andmap point-marker-visual? scatter-children))
  (check-equal? (visual-id scatter) 'samples)
  (check-equal? (visual-position scatter) origin)

  ;; Scatter points outside the display can be retained explicitly.
  ; unclipped-scatter : group-visual?
  ;;   Gives one marker beyond the visible x range.
  (define unclipped-scatter
    (scatter-plot unit-axes
                  (list (vec2 3 0))
                  #:id 'unclipped
                  #:clip? #f))

  (check-equal? (map visual-position
                     (group-visual-children unclipped-scatter))
                (list (vec2 3 0)))

  ;; A transformed axes snapshot affects positions while markers start upright.
  ; transformed-axes : axes-visual?
  ;;   Gives translated, rotated, and nonuniformly scaled axes.
  (define transformed-axes
    (visual-with-scale
     (visual-with-rotation
      (visual-with-position unit-axes (vec2 5 -2))
      1/2)
     (vec2 2 3)))

  ; transformed-scatter : group-visual?
  ;;   Gives one marker positioned through the transformed axes snapshot.
  (define transformed-scatter
    (scatter-plot transformed-axes
                  (list (vec2 1 1))
                  #:id 'transformed-scatter))

  ; transformed-marker : point-marker-visual?
  ;;   Gives the local marker child of transformed-scatter.
  (define transformed-marker
    (car (group-visual-children transformed-scatter)))

  (check-equal? (visual-position transformed-scatter) (vec2 5 -2))
  (check-equal? (visual-rotation transformed-scatter) 1/2)
  (check-equal? (visual-position transformed-marker) (vec2 2 3))
  (check-equal? (visual-rotation transformed-marker) -1/2)

  ;; Function areas close each visible run to the requested baseline.
  ; linear-area-path : path-geometry?
  ;;   Gives one closed region under y = x and above y = 0.
  (define linear-area-path
    (sample-function-area-path unit-axes
                               values
                               #:sample-count 3
                               #:clip? #f))

  ; linear-area-subpath : path-subpath?
  ;;   Gives the single closed area run.
  (define linear-area-subpath
    (car (path-geometry-subpaths linear-area-path)))

  (check-true (path-subpath-closed? linear-area-subpath))
  (check-equal?
   (path-subpath-points linear-area-subpath)
   (list (vec2 -2 0)
         (vec2 -2 -2)
         origin
         (vec2 2 2)
         (vec2 2 0)))

  ;; Every discontinuous graph run becomes an independent closed region.
  ; broken-area-path : path-geometry?
  ;;   Gives two regions separated by an explicit function gap at zero.
  (define broken-area-path
    (sample-function-area-path
     unit-axes
     (lambda (x)
       (if (zero? x)
           #f
           x))
     #:sample-count 5
     #:clip? #f))

  (check-equal? (length (path-geometry-subpaths broken-area-path)) 2)
  (check-true
   (andmap path-subpath-closed?
           (path-geometry-subpaths broken-area-path)))

  ;; A clipped baseline is clamped to the visible y interval.
  ; clipped-baseline-path : path-geometry?
  ;;   Gives an area whose requested baseline ten is clamped to y = 2.
  (define clipped-baseline-path
    (sample-function-area-path unit-axes
                               (lambda (_x) 0)
                               #:baseline 10
                               #:sample-count 2))

  (check-equal?
   (path-subpath-start
    (car (path-geometry-subpaths clipped-baseline-path)))
   (vec2 -2 2))

  ; unclipped-baseline-path : path-geometry?
  ;;   Gives the same area with the actual baseline ten retained.
  (define unclipped-baseline-path
    (sample-function-area-path unit-axes
                               (lambda (_x) 0)
                               #:baseline 10
                               #:sample-count 2
                               #:clip? #f))

  (check-equal?
   (path-subpath-start
    (car (path-geometry-subpaths unclipped-baseline-path)))
   (vec2 -2 10))

  ;; Smooth graph segments remain semantic cubics inside the closed region.
  ; smooth-area-path : path-geometry?
  ;;   Gives one smooth cubic region through three samples.
  (define smooth-area-path
    (sample-function-area-path
     unit-axes
     (lambda (x) (* x x))
     #:sample-count 3
     #:clip? #f
     #:interpolation 'smooth))

  ; smooth-area-segments : (listof path-segment?)
  ;;   Gives baseline edges around the cubic graph segments.
  (define smooth-area-segments
    (path-subpath-segments
     (car (path-geometry-subpaths smooth-area-path))))

  (check-true (line-path-segment? (car smooth-area-segments)))
  (check-true
   (andmap cubic-bezier-path-segment?
           (take (cdr smooth-area-segments) 2)))
  (check-true (line-path-segment? (car (reverse smooth-area-segments))))

  ;; Ordered data areas preserve explicit run order and gaps.
  ; data-area-path-value : path-geometry?
  ;;   Gives two closed data regions in supplied order.
  (define data-area-path-value
    (data-series-area-path
     unit-axes
     (list (vec2 -2 1)
           (vec2 -1 2)
           #f
           (vec2 1 -1)
           (vec2 2 -2))
     #:clip? #f))

  (check-equal? (length (path-geometry-subpaths data-area-path-value)) 2)
  (check-equal?
   (map path-subpath-start
        (path-geometry-subpaths data-area-path-value))
   (list (vec2 -2 0)
         (vec2 1 0)))

  ;; Styled area Visuals copy the complete axes transform snapshot.
  ; styled-area : path-visual?
  ;;   Gives a custom filled function area.
  (define styled-area
    (function-area transformed-axes
                   (lambda (x) x)
                   #:id 'styled-area
                   #:sample-count 3
                   #:clip? #f
                   #:opacity 1/3
                   #:fill "gold"
                   #:stroke "brown"
                   #:stroke-width 2))

  (check-equal? (visual-transform styled-area)
                (visual-transform transformed-axes))
  (check-equal? (visual-opacity styled-area) 1/3)
  (check-equal? (path-visual-fill styled-area) "gold")
  (check-equal? (path-visual-stroke styled-area) "brown")
  (check-equal? (path-visual-stroke-width styled-area) 2)

  ;; Marker groups and area paths use ordinary timeline operations.
  ; entrance : scene?
  ;;   Fades the scatter group and area into one scene.
  (define entrance
    (scene-play (make-scene)
                (fade-in scatter)
                (fade-in styled-area)
                #:duration 1))

  ; completed-state : scene-state?
  ;;   Gives the exact structural endpoint of both fade-in requests.
  (define completed-state
    (scene-sample entrance 1))

  (check-equal? (scene-state-count completed-state) 2)
  (check-true (group-visual?
               (scene-state-ref completed-state 'samples)))
  (check-true (path-visual?
               (scene-state-ref completed-state 'styled-area))))
