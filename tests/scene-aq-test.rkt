#lang racket/base

;;;
;;; SCENE-AQ Lagged-Start Composition Tests
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

  ;; lagged-start is a first-class Visual/camera composition. It accepts
  ;; separate children or one list, and all three composition forms may nest.
  (define staggered
    (lagged-start (move-to dot (vec2 4 0))
                  (rotate-by dot 2)
                  (scale-by dot 2)
                  #:lag-ratio 1/2))
  (check-true (lagged-start-animation-request? staggered))
  (check-true
   (lagged-start-animation-request?
    (lagged-start
     (list (move-to dot (vec2 1 0))
           (rotate-by dot 1))
     #:lag-ratio 1/3)))
  (check-true
   (succession-animation-request?
    (succession staggered
                (animation-group (fade-to dot 1/2)
                                 (rotate-by dot 1)))))
  (check-true
   (animation-group-animation-request?
    (animation-group
     staggered
     (succession (move-to other origin)
                 (scale-by other 2)))))
  (check-exn exn:fail:contract?
             (lambda () (lagged-start #:lag-ratio 1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (lagged-start (move-to dot (vec2 1 0)) #:lag-ratio -1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (lagged-start (move-to dot (vec2 1 0)) #:lag-ratio +inf.0)))
  (check-true
   (lagged-start-animation-request?
    (lagged-start (camera-pan-to (vec2 1 0)) #:lag-ratio 1/2)))
  ;; SCENE-AR extends the child grammar with timed leaves/compositions.
  (check-true
   (lagged-start-animation-request?
    (lagged-start
     (timed (move-to dot (vec2 1 0)) #:duration 1)
     #:lag-ratio 1/2)))
  (check-true (timed-animation-request? (timed staggered #:duration 1)))

  ;; For n=3, D=4, r=1/2, every direct child lasts two seconds and starts
  ;; one second after the previous child: [0,2], [1,3], [2,4].
  (define half-lag
    (scene-play
     (scene-add (make-scene) dot)
     staggered
     #:duration 4))
  (check-equal? (visual-position (visual-at half-lag 1 'dot))
                (vec2 2 0))
  (check-equal? (visual-rotation (visual-at half-lag 1 'dot))
                0)
  (check-equal? (visual-scale (visual-at half-lag 1 'dot))
                (vec2 1 1))
  (check-equal? (visual-position (visual-at half-lag 3/2 'dot))
                (vec2 3 0))
  (check-equal? (visual-rotation (visual-at half-lag 3/2 'dot))
                1/2)
  (check-equal? (visual-position (visual-at half-lag 2 'dot))
                (vec2 4 0))
  (check-equal? (visual-rotation (visual-at half-lag 2 'dot))
                1)
  (check-equal? (visual-scale (visual-at half-lag 3 'dot))
                (vec2 3/2 3/2))
  (check-equal? (visual-rotation (visual-at half-lag 4 'dot))
                2)
  (check-equal? (visual-scale (visual-at half-lag 4 'dot))
                (vec2 2 2))
  (check-equal? (scene-duration half-lag) 4)
  (check-equal? (scene-clip-count half-lag) 1)

  ;; r=0 collapses to parallel-group timing.
  (define zero-lag
    (scene-play
     (scene-add (make-scene) dot)
     (lagged-start (move-to dot (vec2 4 0))
                   (rotate-by dot 2)
                   #:lag-ratio 0)
     #:duration 2))
  (check-equal? (visual-position (visual-at zero-lag 1 'dot))
                (vec2 2 0))
  (check-equal? (visual-rotation (visual-at zero-lag 1 'dot))
                1)

  ;; r=1 collapses to equal-slice succession timing. Touching same-component
  ;; leaves are legal and the second relative move compiles from the first end.
  (define unit-lag
    (scene-play
     (scene-add (make-scene) dot)
     (lagged-start (move-to dot (vec2 2 0))
                   (move-to dot (vec2 4 0))
                   #:lag-ratio 1)
     #:duration 4))
  (check-equal? (visual-position (visual-at unit-lag 1 'dot))
                (vec2 1 0))
  (check-equal? (visual-position (visual-at unit-lag 2 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at unit-lag 3 'dot))
                (vec2 3 0))
  (check-equal? (visual-position (visual-at unit-lag 4 'dot))
                (vec2 4 0))

  ;; Positive same-component overlap is rejected after concrete lag expansion.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (lagged-start (move-to dot (vec2 2 0))
                    (move-to dot (vec2 4 0))
                    #:lag-ratio 1/2)
      #:duration 3)))

  ;; Ratios greater than one insert a hold gap while still ending exactly at D.
  ;; Here D=3 and r=2 produce one-second children at starts 0 and 2.
  (define gapped
    (scene-play
     (scene-add (make-scene) dot)
     (lagged-start (move-to dot (vec2 2 0))
                   (move-to dot (vec2 4 0))
                   #:lag-ratio 2)
     #:duration 3))
  (check-equal? (visual-position (visual-at gapped 1 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at gapped 3/2 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at gapped 2 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at gapped 5/2 'dot))
                (vec2 3 0))
  (check-equal? (visual-position (visual-at gapped 3 'dot))
                (vec2 4 0))

  ;; Nested group/sequence children each occupy one lagged child interval.
  ;; With D=3 and r=1/2, the two children last two seconds at starts 0 and 1.
  (define mixed-tree
    (scene-play
     (scene-add (make-scene) dot other)
     (lagged-start
      (animation-group (move-to dot (vec2 4 0))
                       (rotate-by dot 2))
      (succession (move-to other (vec2 0 -2))
                  (scale-by other 2))
      #:lag-ratio 1/2)
     #:duration 3))
  (check-equal? (visual-position (visual-at mixed-tree 1 'dot))
                (vec2 2 0))
  (check-equal? (visual-rotation (visual-at mixed-tree 1 'dot))
                1)
  (check-equal? (visual-position (visual-at mixed-tree 1 'other))
                (vec2 -4 -2))
  (check-equal? (visual-position (visual-at mixed-tree 3/2 'other))
                (vec2 -2 -2))
  (check-equal? (visual-scale (visual-at mixed-tree 5/2 'other))
                (vec2 3/2 3/2))
  (check-equal? (visual-position (visual-at mixed-tree 3 'dot))
                (vec2 4 0))
  (check-equal? (visual-scale (visual-at mixed-tree 3 'other))
                (vec2 2 2))

  ;; A lagged start can itself occupy one succession slice. The outer sequence
  ;; gives it [2,4], then r=0 runs its rotation and scale leaves in parallel.
  (define lagged-in-sequence
    (scene-play
     (scene-add (make-scene) dot other)
     (succession
      (move-to other (vec2 0 -2))
      (lagged-start (rotate-by dot 2)
                    (scale-by dot 2)
                    #:lag-ratio 0))
     #:duration 4))
  (check-equal? (visual-position (visual-at lagged-in-sequence 2 'other))
                (vec2 0 -2))
  (check-equal? (visual-rotation (visual-at lagged-in-sequence 3 'dot))
                1)
  (check-equal? (visual-scale (visual-at lagged-in-sequence 3 'dot))
                (vec2 3/2 3/2))
  (check-equal? (visual-rotation (visual-at lagged-in-sequence 4 'dot))
                2)

  ;; A lagged branch can also share a full interval with another group branch.
  (define lagged-in-group
    (scene-play
     (scene-add (make-scene) dot other)
     (animation-group
      (lagged-start (move-to dot (vec2 4 0))
                    (rotate-by dot 2)
                    #:lag-ratio 1/2)
      (move-to other (vec2 4 -2)))
     #:duration 3))
  (check-equal? (visual-position (visual-at lagged-in-group 1 'dot))
                (vec2 2 0))
  (check-equal? (visual-rotation (visual-at lagged-in-group 1 'dot))
                0)
  (check-equal? (visual-position (visual-at lagged-in-group 1 'other))
                (vec2 -4/3 -2))
  (check-equal? (visual-rotation (visual-at lagged-in-group 2 'dot))
                1)
  (check-equal? (visual-position (visual-at lagged-in-group 3 'dot))
                (vec2 4 0))
  (check-equal? (visual-rotation (visual-at lagged-in-group 3 'dot))
                2)

  ;; Easing is reset on every leaf's own normalized local progress.
  (define (square progress)
    (* progress progress))
  (define eased
    (scene-play
     (scene-add (make-scene) dot other)
     (lagged-start (move-to dot (vec2 4 0))
                   (move-to other (vec2 4 -2))
                   #:lag-ratio 1/2)
     #:duration 3
     #:easing square))
  (check-equal? (visual-position (visual-at eased 1 'dot))
                (vec2 1 0))
  (check-equal? (visual-position (visual-at eased 1 'other))
                (vec2 -4 -2))
  (check-equal? (visual-position (visual-at eased 2 'other))
                (vec2 -2 -2))

  ;; Structural introduction occurs at the first child's start, while a later
  ;; compatible child can begin partway through that fade-in interval.
  (define badge
    (rectangle #:id 'badge
               #:width 2
               #:height 1
               #:center (vec2 -3 0)
               #:fill "gold"
               #:opacity 4/5))
  (define introduced
    (scene-play
     (make-scene)
     (lagged-start (fade-in badge)
                   (move-to 'badge (vec2 3 0))
                   #:lag-ratio 1/2)
     #:duration 3))
  (check-true (scene-state-has? (scene-sample introduced 0) 'badge))
  (check-equal? (visual-opacity (visual-at introduced 0 'badge)) 0)
  (check-equal? (visual-position (visual-at introduced 1 'badge))
                (vec2 -3 0))
  (check-equal? (visual-opacity (visual-at introduced 1 'badge))
                2/5)
  (check-equal? (visual-position (visual-at introduced 2 'badge))
                origin)
  (check-equal? (visual-opacity (visual-at introduced 2 'badge))
                4/5)
  (check-equal? (visual-position (visual-at introduced 3 'badge))
                (vec2 3 0))

  ;; Structural removal may overlap compatible motion if that motion ends before
  ;; the removal endpoint. Here move is [0,2] and fade-out is [1,3].
  (define removable
    (scene-play
     (scene-add (make-scene) badge)
     (lagged-start (move-to badge (vec2 3 0))
                   (fade-out badge)
                   #:lag-ratio 1/2)
     #:duration 3))
  (check-true (scene-state-has? (scene-sample removable 2) 'badge))
  (check-equal? (visual-position (visual-at removable 2 'badge))
                (vec2 3 0))
  (check-equal? (visual-opacity (visual-at removable 2 'badge))
                2/5)
  (check-false (scene-state-has? (scene-sample removable 3) 'badge))

  ;; Reversing those children would remove the target at t=2 while movement
  ;; remains active through t=3, so post-expansion removal validation rejects it.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) badge)
      (lagged-start (fade-out badge)
                    (move-to badge (vec2 3 0))
                    #:lag-ratio 1/2)
      #:duration 3)))

  ;; camera-follow consumes the actual staggered translation schedule, including
  ;; the hold gap generated by a lag ratio greater than one.
  (define follow-camera
    (make-camera #:width 320 #:height 180 #:world-width 12 #:center origin))
  (define followed
    (scene-play
     (scene-add (make-scene #:camera follow-camera) dot)
     (lagged-start (move-to dot (vec2 2 0))
                   (move-to dot (vec2 4 0))
                   #:lag-ratio 2)
     (camera-follow dot)
     #:duration 3))
  (check-equal? (camera-center (scene-camera-at followed 1/2))
                (vec2 1 0))
  (check-equal? (camera-center (scene-camera-at followed 3/2))
                (vec2 2 0))
  (check-equal? (camera-center (scene-camera-at followed 5/2))
                (vec2 3 0))
  (check-equal? (camera-center (scene-camera-at followed 3))
                (vec2 4 0))

  ;; Inexact lag arithmetic still preserves the exact outer semantic endpoint.
  (define inexact-lag
    (scene-play
     (scene-add (make-scene) dot other)
     (lagged-start (move-to dot (vec2 4 0))
                   (move-to other (vec2 4 -2))
                   #:lag-ratio 0.1)
     #:duration 1.0))
  (check-equal? (visual-position (visual-at inexact-lag 1.0 'dot))
                (vec2 4 0))
  (check-equal? (visual-position (visual-at inexact-lag 1.0 'other))
                (vec2 4 -2))

  ;; Default lag-ratio is 1/4. With two children in a five-second clip this
  ;; means four-second children starting at 0 and 1.
  (define default-lag
    (scene-play
     (scene-add (make-scene) dot other)
     (lagged-start (move-to dot (vec2 4 0))
                   (move-to other (vec2 4 -2)))
     #:duration 5))
  (check-equal? (visual-position (visual-at default-lag 1 'dot))
                (vec2 1 0))
  (check-equal? (visual-position (visual-at default-lag 1 'other))
                (vec2 -4 -2))
  (check-equal? (visual-position (visual-at default-lag 3 'other))
                (vec2 0 -2))
  (check-equal? (visual-position (visual-at default-lag 5 'other))
                (vec2 4 -2)))
