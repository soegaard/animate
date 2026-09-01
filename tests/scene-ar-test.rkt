#lang racket/base

;;;
;;; SCENE-AR Duration-Scaled Composition Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define dot
    (circle #:id 'dot
            #:radius 1/2
            #:center origin
            #:fill "seagreen"))

  (define other
    (rectangle #:id 'other
               #:width 1
               #:height 1
               #:center (vec2 -4 -2)
               #:fill "slateblue"))

  (define (visual-at scene time id)
    (scene-state-ref (scene-sample scene time) id))

  ;; timed may now wrap a composition, and timed wrappers may be direct children
  ;; of any Visual composition. Cameras and nested timed wrappers remain invalid.
  (define timed-sequence
    (timed
     (succession (move-to dot (vec2 2 0))
                 (rotate-by dot 2))
     #:start 1
     #:duration 4))
  (check-true (timed-animation-request? timed-sequence))
  (check-true
   (succession-animation-request?
    (succession (move-to dot (vec2 1 0))
                (timed (rotate-by dot 1) #:duration 2))))
  (check-true
   (animation-group-animation-request?
    (animation-group (move-to dot (vec2 1 0))
                     (timed (rotate-by dot 1) #:start 1 #:duration 1))))
  (check-true
   (lagged-start-animation-request?
    (lagged-start (move-to dot (vec2 1 0))
                  (timed (rotate-by dot 1) #:duration 2)
                  #:lag-ratio 1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (timed (camera-pan-to (vec2 1 0)) #:duration 1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (timed (timed (move-to dot (vec2 1 0)) #:duration 1)
                      #:duration 1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (succession (camera-pan-to (vec2 1 0)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (timed (succession (move-to dot (vec2 1 0)))
             #:start 2
             #:duration 2)
      #:duration 3)))

  ;; A nested timed child contributes start+duration intrinsic units. With spans
  ;; 1,2,1 inside D=8 the concrete sequence intervals are [0,2], [2,6], [6,8].
  (define weighted-sequence
    (scene-play
     (scene-add (make-scene) dot)
     (succession
      (move-to dot (vec2 2 0))
      (timed (rotate-by dot 4) #:duration 2)
      (scale-by dot 2))
     #:duration 8))
  (check-equal? (visual-position (visual-at weighted-sequence 1 'dot))
                (vec2 1 0))
  (check-equal? (visual-position (visual-at weighted-sequence 2 'dot))
                (vec2 2 0))
  (check-equal? (visual-rotation (visual-at weighted-sequence 3 'dot))
                1)
  (check-equal? (visual-rotation (visual-at weighted-sequence 5 'dot))
                3)
  (check-equal? (visual-rotation (visual-at weighted-sequence 6 'dot))
                4)
  (check-equal? (visual-scale (visual-at weighted-sequence 7 'dot))
                (vec2 3/2 3/2))
  (check-equal? (visual-scale (visual-at weighted-sequence 8 'dot))
                (vec2 2 2))

  ;; A timed child's start is part of its intrinsic span. Here the outer spans are
  ;; 1 and 2 in D=6. The first child uses [0,2]; the second reserves [2,6], with
  ;; a scaled two-second delay and active rotation only during [4,6].
  (define delayed-child
    (scene-play
     (scene-add (make-scene) dot)
     (succession
      (move-to dot (vec2 2 0))
      (timed (rotate-by dot 2) #:start 1 #:duration 1))
     #:duration 6))
  (check-equal? (visual-position (visual-at delayed-child 2 'dot))
                (vec2 2 0))
  (check-equal? (visual-rotation (visual-at delayed-child 3 'dot))
                0)
  (check-equal? (visual-rotation (visual-at delayed-child 4 'dot))
                0)
  (check-equal? (visual-rotation (visual-at delayed-child 5 'dot))
                1)
  (check-equal? (visual-rotation (visual-at delayed-child 6 'dot))
                2)

  ;; A top-level timed composition keeps literal seconds. The wrapped succession
  ;; is inactive before t=1, fills [1,5], then holds its exact endpoint to t=6.
  (define absolute-timed-composite
    (scene-play
     (scene-add (make-scene) dot)
     (timed
      (succession (move-to dot (vec2 4 0))
                  (rotate-by dot 2))
      #:start 1
      #:duration 4)
     #:duration 6))
  (check-equal? (visual-position (visual-at absolute-timed-composite 1/2 'dot))
                origin)
  (check-equal? (visual-position (visual-at absolute-timed-composite 2 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at absolute-timed-composite 3 'dot))
                (vec2 4 0))
  (check-equal? (visual-rotation (visual-at absolute-timed-composite 4 'dot))
                1)
  (check-equal? (visual-rotation (visual-at absolute-timed-composite 5 'dot))
                2)
  (check-equal? (visual-rotation (visual-at absolute-timed-composite 6 'dot))
                2)

  ;; A timed composition can itself be one weighted succession child. Bare
  ;; compositions remain one unit, preserving AO-AQ parent allocation unless the
  ;; composition is explicitly wrapped. The timed middle branch gets four of
  ;; eight seconds, then divides those four seconds equally internally.
  (define weighted-composite-child
    (scene-play
     (scene-add (make-scene) dot other)
     (succession
      (move-to dot (vec2 2 0))
      (timed
       (succession (move-to other (vec2 0 -2))
                   (scale-by other 2))
       #:duration 2)
      (rotate-by dot 2))
     #:duration 8))
  (check-equal? (visual-position (visual-at weighted-composite-child 2 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at weighted-composite-child 3 'other))
                (vec2 -2 -2))
  (check-equal? (visual-position (visual-at weighted-composite-child 4 'other))
                (vec2 0 -2))
  (check-equal? (visual-scale (visual-at weighted-composite-child 5 'other))
                (vec2 3/2 3/2))
  (check-equal? (visual-scale (visual-at weighted-composite-child 6 'other))
                (vec2 2 2))
  (check-equal? (visual-rotation (visual-at weighted-composite-child 7 'dot))
                1)

  ;; Parallel groups scale shorter direct spans against the longest one. In D=4
  ;; the plain dot child has span 1 and ends at t=2; the timed other child has
  ;; span 2 and uses the full four seconds.
  (define duration-scaled-group
    (scene-play
     (scene-add (make-scene) dot other)
     (animation-group
      (move-to dot (vec2 4 0))
      (timed (move-to other (vec2 4 -2)) #:duration 2))
     #:duration 4))
  (check-equal? (visual-position (visual-at duration-scaled-group 1 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at duration-scaled-group 2 'dot))
                (vec2 4 0))
  (check-equal? (visual-position (visual-at duration-scaled-group 2 'other))
                (vec2 0 -2))
  (check-equal? (visual-position (visual-at duration-scaled-group 3 'dot))
                (vec2 4 0))
  (check-equal? (visual-position (visual-at duration-scaled-group 3 'other))
                (vec2 2 -2))

  ;; A delayed timed group child reserves its delay in the same scaled span. The
  ;; plain child ends at t=2 and the delayed child moves only during [2,4].
  (define delayed-group-child
    (scene-play
     (scene-add (make-scene) dot other)
     (animation-group
      (move-to dot (vec2 4 0))
      (timed (move-to other (vec2 4 -2)) #:start 1 #:duration 1))
     #:duration 4))
  (check-equal? (visual-position (visual-at delayed-group-child 1 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at delayed-group-child 1 'other))
                (vec2 -4 -2))
  (check-equal? (visual-position (visual-at delayed-group-child 2 'dot))
                (vec2 4 0))
  (check-equal? (visual-position (visual-at delayed-group-child 2 'other))
                (vec2 -4 -2))
  (check-equal? (visual-position (visual-at delayed-group-child 3 'other))
                (vec2 0 -2))

  ;; Generalized lagged timing uses direct child spans. With r=1 it is exactly
  ;; the weighted succession rule: spans 1 and 2 map to [0,2] and [2,6].
  (define weighted-unit-lag
    (scene-play
     (scene-add (make-scene) dot)
     (lagged-start
      (move-to dot (vec2 2 0))
      (timed (move-to dot (vec2 4 0)) #:duration 2)
      #:lag-ratio 1)
     #:duration 6))
  (check-equal? (visual-position (visual-at weighted-unit-lag 1 'dot))
                (vec2 1 0))
  (check-equal? (visual-position (visual-at weighted-unit-lag 2 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at weighted-unit-lag 4 'dot))
                (vec2 3 0))
  (check-equal? (visual-position (visual-at weighted-unit-lag 6 'dot))
                (vec2 4 0))

  ;; The r=1 identity is exact even with inexact timing values, so touching
  ;; same-component children do not acquire a floating-point overlap.
  (define inexact-unit-lag
    (scene-play
     (scene-add (make-scene) dot)
     (lagged-start
      (move-to dot (vec2 2 0))
      (timed (move-to dot (vec2 4 0)) #:duration 2.0)
      #:lag-ratio 1.0)
     #:duration 6.0))
  (check-equal? (visual-position (visual-at inexact-unit-lag 6.0 'dot))
                (vec2 4 0))

  ;; An intermediate lag ratio uses unequal direct spans rather than reverting to
  ;; the old equal-duration AQ formula. With spans 1 and 2 and r=1/2 the raw
  ;; intervals are [0,1] and [1/2,5/2]; scaling that envelope to D=5 gives
  ;; concrete intervals [0,2] and [1,5].
  (define weighted-half-lag
    (scene-play
     (scene-add (make-scene) dot other)
     (lagged-start
      (move-to dot (vec2 4 0))
      (timed (move-to other (vec2 4 -2)) #:duration 2)
      #:lag-ratio 1/2)
     #:duration 5))
  (check-equal? (visual-position (visual-at weighted-half-lag 1 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at weighted-half-lag 1 'other))
                (vec2 -4 -2))
  (check-equal? (visual-position (visual-at weighted-half-lag 3 'other))
                (vec2 0 -2))
  (check-equal? (visual-position (visual-at weighted-half-lag 5 'other))
                (vec2 4 -2))

  ;; With r=0 the same explicit spans have animation-group timing: both start at
  ;; zero, the one-unit child is scaled to two seconds, and the two-unit child to
  ;; the full four seconds.
  (define weighted-zero-lag
    (scene-play
     (scene-add (make-scene) dot other)
     (lagged-start
      (move-to dot (vec2 4 0))
      (timed (move-to other (vec2 4 -2)) #:duration 2)
      #:lag-ratio 0)
     #:duration 4))
  (check-equal? (visual-position (visual-at weighted-zero-lag 1 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at weighted-zero-lag 2 'other))
                (vec2 0 -2))
  (check-equal? (visual-position (visual-at weighted-zero-lag 4 'other))
                (vec2 4 -2))

  ;; A timed composite easing becomes the inherited easing of every descendant
  ;; leaf. The outer square easing restarts independently on each sequence child.
  (define (square progress)
    (* progress progress))
  (define eased-composite
    (scene-play
     (scene-add (make-scene) dot)
     (timed
      (succession (move-to dot (vec2 2 0))
                  (move-to dot (vec2 4 0)))
      #:duration 2
      #:easing square)
     #:duration 2))
  (check-equal? (visual-position (visual-at eased-composite 1/2 'dot))
                (vec2 1/2 0))
  (check-equal? (visual-position (visual-at eased-composite 3/2 'dot))
                (vec2 5/2 0))

  ;; A nested timed child may override a timed composite's inherited easing. The
  ;; first half keeps square easing; the second half explicitly restores linear.
  (define overridden-composite-easing
    (scene-play
     (scene-add (make-scene) dot)
     (timed
      (succession
       (move-to dot (vec2 2 0))
       (timed (move-to dot (vec2 4 0))
              #:duration 1
              #:easing linear))
      #:duration 4
      #:easing square)
     #:duration 4))
  (check-equal? (visual-position (visual-at overridden-composite-easing 1 'dot))
                (vec2 1/2 0))
  (check-equal? (visual-position (visual-at overridden-composite-easing 3 'dot))
                (vec2 3 0))

  ;; Structural introduction remains local to a timed composite. Before t=1 the
  ;; badge is absent; fade-in and movement then divide [1,5] sequentially.
  (define badge
    (rectangle #:id 'badge
               #:width 2
               #:height 1
               #:center (vec2 -3 0)
               #:fill "gold"
               #:opacity 4/5))
  (define introduced-composite
    (scene-play
     (make-scene)
     (timed
      (succession (fade-in badge)
                  (move-to 'badge (vec2 3 0)))
      #:start 1
      #:duration 4)
     #:duration 6))
  (check-false (scene-state-has? (scene-sample introduced-composite 1/2) 'badge))
  (check-true (scene-state-has? (scene-sample introduced-composite 1) 'badge))
  (check-equal? (visual-opacity (visual-at introduced-composite 1 'badge)) 0)
  (check-equal? (visual-opacity (visual-at introduced-composite 2 'badge)) 2/5)
  (check-equal? (visual-position (visual-at introduced-composite 4 'badge))
                origin)
  (check-equal? (visual-position (visual-at introduced-composite 5 'badge))
                (vec2 3 0))

  ;; Conflict validation runs after duration scaling. These two same-component
  ;; group leaves overlap concretely and remain invalid.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (animation-group
       (move-to dot (vec2 2 0))
       (timed (move-to dot (vec2 4 0)) #:duration 2))
      #:duration 4)))

  ;; camera-follow consumes the scaled nested schedule directly.
  (define follow-camera
    (make-camera #:width 320 #:height 180 #:world-width 12 #:center origin))
  (define followed
    (scene-play
     (scene-add (make-scene #:camera follow-camera) dot)
     (timed
      (succession
       (move-to dot (vec2 2 0))
       (timed (move-to dot (vec2 4 0)) #:duration 2))
      #:duration 6)
     (camera-follow dot)
     #:duration 6))
  (check-equal? (camera-center (scene-camera-at followed 1))
                (vec2 1 0))
  (check-equal? (camera-center (scene-camera-at followed 2))
                (vec2 2 0))
  (check-equal? (camera-center (scene-camera-at followed 4))
                (vec2 3 0))
  (check-equal? (camera-center (scene-camera-at followed 6))
                (vec2 4 0)))
