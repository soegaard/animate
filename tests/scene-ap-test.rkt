#lang racket/base

;;;
;;; SCENE-AP Parallel Animation Group Tests
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

  ;; animation-group is a first-class Visual composition. It accepts separate
  ;; children or one list, and sequential/parallel compositions may nest in
  ;; either direction.
  (define parallel-pair
    (animation-group (move-to dot (vec2 4 0))
                     (rotate-by dot 2)))
  (check-true (animation-group-animation-request? parallel-pair))
  (check-true
   (animation-group-animation-request?
    (animation-group
     (list (move-to dot (vec2 1 0))
           (rotate-by dot 1)))))
  (check-true
   (succession-animation-request?
    (succession
     (animation-group (move-to dot (vec2 1 0))
                      (rotate-by dot 1))
     (scale-by dot 2))))
  (check-true
   (animation-group-animation-request?
    (animation-group
     (succession (move-to dot (vec2 1 0))
                 (rotate-by dot 1))
     (scale-by dot 2))))
  (check-exn exn:fail:contract?
             (lambda () (animation-group)))
  (check-exn exn:fail:contract?
             (lambda () (animation-group (camera-pan-to (vec2 1 0)))))
  ;; SCENE-AR extends the child grammar with timed leaves/compositions.
  (check-true
   (animation-group-animation-request?
    (animation-group
     (timed (move-to dot (vec2 1 0)) #:duration 1))))
  (check-true
   (timed-animation-request? (timed parallel-pair #:duration 1)))

  ;; Direct children occupy the same complete enclosing interval. Disjoint
  ;; components on one Visual compose exactly as historical simultaneous play.
  (define parallel-components
    (scene-play
     (scene-add (make-scene) dot)
     parallel-pair
     #:duration 4))
  (check-equal? (visual-position (visual-at parallel-components 0 'dot))
                origin)
  (check-equal? (visual-position (visual-at parallel-components 2 'dot))
                (vec2 2 0))
  (check-equal? (visual-rotation (visual-at parallel-components 2 'dot))
                1)
  (check-equal? (visual-position (visual-at parallel-components 4 'dot))
                (vec2 4 0))
  (check-equal? (visual-rotation (visual-at parallel-components 4 'dot))
                2)
  (check-equal? (scene-duration parallel-components) 4)
  (check-equal? (scene-clip-count parallel-components) 1)

  ;; Overlapping updates to the same target/component remain a conflict after
  ;; group expansion.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (animation-group (move-to dot (vec2 2 0))
                       (move-to dot (vec2 4 0)))
      #:duration 2)))

  ;; A parallel group can be one child of a succession. Both leaves in each
  ;; group receive the sequence slice, and the second group compiles from the
  ;; exact endpoint produced by the first group.
  (define groups-in-sequence
    (scene-play
     (scene-add (make-scene) dot)
     (succession
      (animation-group (move-to dot (vec2 4 0))
                       (rotate-by dot 2))
      (animation-group (move-to dot (vec2 8 0))
                       (scale-by dot 2)))
     #:duration 4))
  (check-equal? (visual-position (visual-at groups-in-sequence 1 'dot))
                (vec2 2 0))
  (check-equal? (visual-rotation (visual-at groups-in-sequence 1 'dot))
                1)
  (check-equal? (visual-position (visual-at groups-in-sequence 2 'dot))
                (vec2 4 0))
  (check-equal? (visual-rotation (visual-at groups-in-sequence 2 'dot))
                2)
  (check-equal? (visual-position (visual-at groups-in-sequence 3 'dot))
                (vec2 6 0))
  (check-equal? (visual-scale (visual-at groups-in-sequence 3 'dot))
                (vec2 3/2 3/2))
  (check-equal? (visual-position (visual-at groups-in-sequence 4 'dot))
                (vec2 8 0))
  (check-equal? (visual-scale (visual-at groups-in-sequence 4 'dot))
                (vec2 2 2))

  ;; A succession can in turn be one branch of a parallel group. The other
  ;; branch spans the whole group interval while the sequence subdivides it.
  (define sequence-in-group
    (scene-play
     (scene-add (make-scene) dot other)
     (animation-group
      (succession (move-to dot (vec2 2 0))
                  (rotate-by dot 2))
      (move-to other (vec2 4 -2)))
     #:duration 4))
  (check-equal? (visual-position (visual-at sequence-in-group 1 'dot))
                (vec2 1 0))
  (check-equal? (visual-position (visual-at sequence-in-group 1 'other))
                (vec2 -2 -2))
  (check-equal? (visual-position (visual-at sequence-in-group 3 'dot))
                (vec2 2 0))
  (check-equal? (visual-rotation (visual-at sequence-in-group 3 'dot))
                1)
  (check-equal? (visual-position (visual-at sequence-in-group 3 'other))
                (vec2 2 -2))

  ;; Nested groups preserve the same interval recursively rather than dividing
  ;; it. The enclosing easing is evaluated independently by every leaf.
  (define (square progress)
    (* progress progress))
  (define nested-group
    (scene-play
     (scene-add (make-scene) dot other)
     (animation-group
      (animation-group (move-to dot (vec2 4 0))
                       (rotate-by dot 4))
      (fade-to other 0))
     #:duration 2
     #:easing square))
  (check-equal? (visual-position (visual-at nested-group 1 'dot))
                (vec2 1 0))
  (check-equal? (visual-rotation (visual-at nested-group 1 'dot))
                1)
  (check-equal? (visual-opacity (visual-at nested-group 1 'other))
                3/4)
  (check-equal? (visual-position (visual-at nested-group 2 'dot))
                (vec2 4 0))
  (check-equal? (visual-opacity (visual-at nested-group 2 'other))
                0)

  ;; Structural introduction shares its prepared start state with compatible
  ;; simultaneous group leaves, just as it did in historical scene-play.
  (define badge
    (rectangle #:id 'badge
               #:width 2
               #:height 1
               #:center (vec2 -3 0)
               #:fill "gold"
               #:opacity 4/5))
  (define introduced-group
    (scene-play
     (make-scene)
     (animation-group (fade-in badge)
                      (move-to 'badge (vec2 3 0)))
     #:duration 2))
  (check-true (scene-state-has? (scene-sample introduced-group 0) 'badge))
  (check-equal? (visual-opacity (visual-at introduced-group 0 'badge)) 0)
  (check-equal? (visual-position (visual-at introduced-group 0 'badge))
                (vec2 -3 0))
  (check-equal? (visual-opacity (visual-at introduced-group 1 'badge))
                2/5)
  (check-equal? (visual-position (visual-at introduced-group 1 'badge))
                origin)
  (check-equal? (visual-opacity (visual-at introduced-group 2 'badge))
                4/5)
  (check-equal? (visual-position (visual-at introduced-group 2 'badge))
                (vec2 3 0))

  ;; Structural completion occurs after all compatible component endpoints at a
  ;; shared group boundary are sampled. The target is then removed exactly once.
  (define removed-group
    (scene-play
     (scene-add (make-scene) badge)
     (animation-group (fade-out badge)
                      (move-to badge (vec2 3 0)))
     #:duration 2))
  (check-true (scene-state-has? (scene-sample removed-group 1) 'badge))
  (check-equal? (visual-position (visual-at removed-group 1 'badge)) origin)
  (check-false (scene-state-has? (scene-sample removed-group 2) 'badge))

  ;; camera-follow remains full-clip but consumes the actual group-sampled
  ;; translation while other parallel components animate independently.
  (define follow-camera
    (make-camera #:width 320 #:height 180 #:world-width 12 #:center origin))
  (define followed-group
    (scene-play
     (scene-add (make-scene #:camera follow-camera) dot)
     (animation-group (move-to dot (vec2 4 0))
                      (rotate-by dot 2))
     (camera-follow dot)
     #:duration 2))
  (check-equal? (camera-center (scene-camera-at followed-group 1/2))
                (vec2 1 0))
  (check-equal? (camera-center (scene-camera-at followed-group 3/2))
                (vec2 3 0))
  (check-equal? (camera-center (scene-camera-at followed-group 2))
                (vec2 4 0))

  ;; The convenient single-list scene-play form accepts an animation group.
  (define list-form
    (scene-play
     (scene-add (make-scene) dot)
     (list (animation-group (move-to dot (vec2 2 0))
                            (rotate-by dot 2)))
     #:duration 2))
  (check-equal? (visual-position (visual-at list-form 1 'dot))
                (vec2 1 0))
  (check-equal? (visual-rotation (visual-at list-form 1 'dot))
                1))
