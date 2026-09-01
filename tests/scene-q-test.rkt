#lang racket/base

;;;
;;; SCENE-Q Arrow and Axes Tests
;;;

;; Tests semantic arrow endpoints, tips, Cartesian ranges, coordinate mapping,
;; affine updates, group participation, and ordinary timeline animation.


;;;
;;; Imports
;;;

(require (only-in racket/math pi)
         rackunit
         "../main.rkt")


(module+ test
  ; comparison-tolerance : positive-real?
  ;;   Gives the tolerance used for trigonometric coordinate checks.
  (define comparison-tolerance
    1e-10)

  ;; Axis ranges preserve bounds and produce ordered nonzero tick values.
  ; horizontal-range : axis-range?
  ;;   Gives an asymmetric range with a two-unit tick step.
  (define horizontal-range
    (axis-range -3 5 2))

  (check-equal? (axis-range-minimum horizontal-range) -3)
  (check-equal? (axis-range-maximum horizontal-range) 5)
  (check-equal? (axis-range-tick-step horizontal-range) 2)
  (check-equal? (axis-range-tick-values horizontal-range)
                '(-2 2 4))
  (check-true (axis-range-contains? horizontal-range -3))
  (check-true (axis-range-contains? horizontal-range 0))
  (check-true (axis-range-contains? horizontal-range 5))
  (check-false (axis-range-contains? horizontal-range 6))
  (check-false (axis-range-contains? horizontal-range +inf.0))

  ;; A fixed inexact tolerance keeps ordinary decimal endpoint ticks.
  ; decimal-ticks : (listof real?)
  ;;   Gives the regular nonzero ticks for an inexact decimal range.
  (define decimal-ticks
    (axis-range-tick-values
     (axis-range -0.3 0.3 0.1)))

  (check-equal? (length decimal-ticks) 6)
  (for ([actual (in-list decimal-ticks)]
        [expected (in-list '(-0.3 -0.2 -0.1 0.1 0.2 0.3))])
    (check-= actual expected 1e-12))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (axes #:id 'bad-linear-range
           #:x-range (axis-range 1 3 1))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (axis-range -1 -1 1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (axis-range -1 1 0)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (axis-range-tick-values 'not-a-range)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (axis-range-tick-values
      (axis-range -1 1 1e-320))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (axis-range -1e308 1e308 1)))

  ;; Arrow endpoints are containing-system points derived from local semantic
  ;; geometry and the current affine transform.
  ; diagonal-arrow : arrow-visual?
  ;;   Gives one single-tipped diagonal arrow centered at the origin.
  (define diagonal-arrow
    (arrow (vec2 -2 -1)
           (vec2 2 1)
           #:id 'diagonal-arrow
           #:stroke "crimson"
           #:stroke-width 4
           #:tip-length 2/5
           #:tip-width 1/3))

  (check-true (visual? diagonal-arrow))
  (check-true (affine-visual? diagonal-arrow))
  (check-true (opacity-visual? diagonal-arrow))
  (check-equal? (visual-id diagonal-arrow) 'diagonal-arrow)
  (check-equal? (visual-position diagonal-arrow) origin)
  (check-equal? (arrow-visual-start diagonal-arrow)
                (vec2 -2 -1))
  (check-equal? (arrow-visual-end diagonal-arrow)
                (vec2 2 1))
  (check-equal? (arrow-visual-point-at diagonal-arrow 0)
                (vec2 -2 -1))
  (check-equal? (arrow-visual-point-at diagonal-arrow 1/2)
                origin)
  (check-equal? (arrow-visual-point-at diagonal-arrow 1)
                (vec2 2 1))
  (check-= (arrow-visual-length diagonal-arrow)
           (sqrt 20)
           comparison-tolerance)
  (check-equal? (arrow-visual-stroke diagonal-arrow) "crimson")
  (check-equal? (arrow-visual-stroke-width diagonal-arrow) 4)
  (check-equal? (arrow-visual-tip-length diagonal-arrow) 2/5)
  (check-equal? (arrow-visual-tip-width diagonal-arrow) 1/3)
  (check-false (arrow-visual-start-tip? diagonal-arrow))
  (check-true (arrow-visual-end-tip? diagonal-arrow))

  ; double-arrow : arrow-visual?
  ;;   Gives a horizontal arrow with tips at both endpoints.
  (define double-arrow
    (arrow (vec2 -2 0)
           (vec2 2 0)
           #:id 'double-arrow
           #:start-tip? #t
           #:end-tip? #t))

  (check-true (arrow-visual-start-tip? double-arrow))
  (check-true (arrow-visual-end-tip? double-arrow))

  ;; Generic immutable updates preserve arrow identity and semantic style.
  ; moved-arrow : arrow-visual?
  ;;   Gives diagonal-arrow with its midpoint moved to (3, 4).
  (define moved-arrow
    (visual-with-position diagonal-arrow (vec2 3 4)))

  (check-equal? (visual-id moved-arrow) 'diagonal-arrow)
  (check-equal? (visual-position moved-arrow) (vec2 3 4))
  (check-equal? (arrow-visual-start moved-arrow) (vec2 1 3))
  (check-equal? (arrow-visual-end moved-arrow) (vec2 5 5))
  (check-equal? (arrow-visual-stroke moved-arrow) "crimson")

  ; rotated-arrow : arrow-visual?
  ;;   Gives a horizontal arrow rotated one quarter turn around its midpoint.
  (define rotated-arrow
    (visual-with-rotation double-arrow (/ pi 2)))

  (check-= (vec2-x (arrow-visual-start rotated-arrow))
           0
           comparison-tolerance)
  (check-= (vec2-y (arrow-visual-start rotated-arrow))
           -2
           comparison-tolerance)
  (check-= (vec2-x (arrow-visual-end rotated-arrow))
           0
           comparison-tolerance)
  (check-= (vec2-y (arrow-visual-end rotated-arrow))
           2
           comparison-tolerance)

  ; scaled-arrow : arrow-visual?
  ;;   Gives a non-uniformly scaled horizontal arrow.
  (define scaled-arrow
    (visual-with-scale double-arrow (vec2 2 1/2)))

  (check-equal? (arrow-visual-start scaled-arrow) (vec2 -4 0))
  (check-equal? (arrow-visual-end scaled-arrow) (vec2 4 0))
  (check-equal? (visual-opacity
                 (visual-with-opacity diagonal-arrow 1/4))
                1/4)

  (check-exn
   exn:fail:contract?
   (lambda ()
     (arrow origin origin #:id 'zero-arrow)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (arrow origin (vec2 1 0)
            #:id 'bad-tip
            #:tip-length 0)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (arrow origin (vec2 1 0)
            #:id 'bad-width
            #:tip-width -1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (arrow-visual-point-at diagonal-arrow 3/2)))

  ;; Axes map numeric coordinates through their range lengths and affine
  ;; transform. Coordinate queries are allowed outside the displayed ranges.
  ; coordinate-axes : axes-visual?
  ;;   Gives asymmetric ranges with known local unit lengths.
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:center (vec2 10 -5)
          #:x-range (axis-range -2 6 2)
          #:y-range (axis-range -1 3 1)
          #:x-length 8
          #:y-length 8
          #:stroke "navy"
          #:stroke-width 3
          #:tick-size 1/5
          #:tip-length 2/5
          #:tip-width 3/10
          #:x-tip? #t
          #:y-tip? #f))

  (check-true (visual? coordinate-axes))
  (check-true (affine-visual? coordinate-axes))
  (check-true (opacity-visual? coordinate-axes))
  (check-equal? (axes-visual-x-range coordinate-axes)
                (axis-range -2 6 2))
  (check-equal? (axes-visual-y-range coordinate-axes)
                (axis-range -1 3 1))
  (check-equal? (axes-visual-x-length coordinate-axes) 8)
  (check-equal? (axes-visual-y-length coordinate-axes) 8)
  (check-equal? (axes-x-unit-length coordinate-axes) 1)
  (check-equal? (axes-y-unit-length coordinate-axes) 2)
  (check-equal? (axes-visual-stroke coordinate-axes) "navy")
  (check-equal? (axes-visual-stroke-width coordinate-axes) 3)
  (check-equal? (axes-visual-tick-size coordinate-axes) 1/5)
  (check-equal? (axes-visual-tip-length coordinate-axes) 2/5)
  (check-equal? (axes-visual-tip-width coordinate-axes) 3/10)
  (check-true (axes-visual-x-tip? coordinate-axes))
  (check-false (axes-visual-y-tip? coordinate-axes))
  (check-equal? (axes-coordinates->point coordinate-axes 2 1)
                (vec2 12 -3))
  (check-equal? (axes-coordinates->point coordinate-axes 8 -2)
                (vec2 18 -9))
  (check-equal? (axes-point->coordinates coordinate-axes
                                          (vec2 12 -3))
                (vec2 2 1))

  ; transformed-axes : axes-visual?
  ;;   Gives coordinate-axes with rotation and non-uniform scale.
  (define transformed-axes
    (visual-with-transform
     coordinate-axes
     (make-affine-transform #:translation (vec2 -3 4)
                            #:rotation (/ pi 3)
                            #:scale (vec2 2 1/2))))

  ; transformed-point : vec2?
  ;;   Gives one transformed coordinate for round-trip validation.
  (define transformed-point
    (axes-coordinates->point transformed-axes 3/2 -1/4))

  ; recovered-coordinates : vec2?
  ;;   Gives the numeric coordinates recovered from transformed-point.
  (define recovered-coordinates
    (axes-point->coordinates transformed-axes transformed-point))

  (check-= (vec2-x recovered-coordinates)
           3/2
           comparison-tolerance)
  (check-= (vec2-y recovered-coordinates)
           -1/4
           comparison-tolerance)

  (check-exn
   exn:fail:contract?
   (lambda ()
     (axes #:id 'bad-axes #:x-length 0)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (axes #:id 'bad-unit-length
           #:x-range (axis-range -1e-308 1e-308 1e-308)
           #:x-length 1e308)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (axes #:id 'bad-tick #:tick-size -1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (axes #:id 'bad-flag #:x-tip? 'yes)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (axes-coordinates->point coordinate-axes +inf.0 0)))

  ;; Arrows and axes are ordinary affine group children and ordinary timeline
  ;; participants at the top level.
  ; diagram : group-visual?
  ;;   Gives a semantic group containing axes and an arrow.
  (define diagram
    (group (list coordinate-axes diagonal-arrow)
           #:id 'diagram))

  (check-equal? (map visual-id (group-visual-children diagram))
                '(coordinate-axes diagonal-arrow))

  ; initial-scene : scene?
  ;;   Gives a scene with separately targetable axes and arrow Visuals.
  (define initial-scene
    (scene-add (make-scene)
               coordinate-axes
               diagonal-arrow))

  ; animated-scene : scene?
  ;;   Animates disjoint transform and opacity components concurrently.
  (define animated-scene
    (scene-play initial-scene
                (move-to coordinate-axes origin)
                (rotate-to coordinate-axes 1/2)
                (scale-to coordinate-axes (vec2 2 1/2))
                (fade-to coordinate-axes 1/2)
                (move-to diagonal-arrow (vec2 4 0))
                (rotate-to diagonal-arrow -1/2)
                #:duration 2))

  ; midpoint-state : scene-state?
  ;;   Gives the state halfway through the concurrent animation.
  (define midpoint-state
    (scene-sample animated-scene 1))

  ; midpoint-axes : axes-visual?
  ;;   Gives coordinate-axes at the halfway sample.
  (define midpoint-axes
    (scene-state-ref midpoint-state 'coordinate-axes))

  ; midpoint-arrow : arrow-visual?
  ;;   Gives diagonal-arrow at the halfway sample.
  (define midpoint-arrow
    (scene-state-ref midpoint-state 'diagonal-arrow))

  (check-equal? (visual-position midpoint-axes) (vec2 5 -5/2))
  (check-equal? (visual-rotation midpoint-axes) 1/4)
  (check-equal? (visual-scale midpoint-axes) (vec2 3/2 3/4))
  (check-equal? (visual-opacity midpoint-axes) 3/4)
  (check-equal? (visual-position midpoint-arrow) (vec2 2 0))
  (check-equal? (visual-rotation midpoint-arrow) -1/4)
  (check-equal? (scene-duration animated-scene) 2))
