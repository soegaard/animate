#lang racket/base

;;;
;;; SCENE-A Model Tests
;;;

;; Tests pure geometry, Visual, scene-state, animation, and timeline behavior.
;;
;; This module intentionally imports no pict, bitmap, filesystem, or process
;; adapter.


;;;
;;; Imports
;;;

(require rackunit
         "../private/animation.rkt"
         "../private/camera.rkt"
         "../private/geometry.rkt"
         "../private/scene-state.rkt"
         "../private/scene.rkt"
         "../private/visual-model.rkt")


(module+ test
  (struct invalid-id-visual (position)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual)
       42)
     (define (visual-position visual)
       (invalid-id-visual-position visual))
     (define (visual-with-position visual position)
       (invalid-id-visual position))])

  ;; invalid-id-visual is a deliberately invalid Visual test double.
  ;;  - position  vec2?  reference position returned by the Visual protocol.

  ; moving-circle : circle-visual?
  ;;   Gives the canonical Visual used by the timeline tests.
  (define moving-circle
    (circle #:id 'moving-circle
            #:center (vec2 -3 0)
            #:radius 3/4))

  ; demo : scene?
  ;;   Gives the canonical one-second move followed by a half-second wait.
  (define demo
    (scene-wait
     (scene-play
      (scene-add (make-scene) moving-circle)
      (move-to moving-circle (vec2 3 0))
      #:duration 1)
     1/2))

  ; position-at : nonnegative-real? -> vec2?
  ;;   Returns the moving circle's reference position at time.
  (define (position-at time)
    (visual-position
     (scene-state-ref (scene-sample demo time)
                      'moving-circle)))

  ; origin-x : real?
  ; origin-y : real?
  ;;   Give the pixel coordinates of the world origin.
  (define-values (origin-x origin-y)
    (camera-world->pixel default-camera origin))
  (check-equal? origin-x 640)
  (check-equal? origin-y 360)

  ;; Visual identities must be explicit and deterministic.
  (check-exn exn:fail:contract?
             (lambda ()
               (circle)))
  (check-eq? (visual-id moving-circle) 'moving-circle)
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-state-add empty-scene-state
                      (invalid-id-visual origin))))

  ;; Drawing order is stored explicitly from back to front.

  ; back-circle : circle-visual?
  ;;   Gives the Visual placed behind front-circle.
  (define back-circle
    (circle #:id 'back
            #:center (vec2 -1 0)
            #:radius 1/2))
  ; front-circle : circle-visual?
  ;;   Gives the Visual placed in front of back-circle.
  (define front-circle
    (circle #:id 'front
            #:center (vec2 1 0)
            #:radius 1/2))
  ; ordered-state : scene-state?
  ;;   Gives a state with back-to-front order (back front).
  (define ordered-state
    (scene-current-state
     (scene-add (make-scene) back-circle front-circle)))
  (check-equal? (scene-state-drawing-order ordered-state)
                '(back front))
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order ordered-state))
   '(back front))

  ;; Duplicate identities are rejected instead of being replaced implicitly.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-add (make-scene)
                back-circle
                (circle #:id 'back
                        #:center origin
                        #:radius 1))))

  ;; Scene-state updates are immutable and preserve drawing order.

  ; state-with-back : scene-state?
  ;;   Gives the one-Visual state used to test immutable updates.
  (define state-with-back
    (scene-state-add empty-scene-state back-circle))
  ; moved-back-circle : circle-visual?
  ;;   Gives back-circle at a replacement position.
  (define moved-back-circle
    (visual-with-position back-circle (vec2 -2 1)))
  ; state-with-moved-back : scene-state?
  ;;   Gives state-with-back with its Visual position replaced.
  (define state-with-moved-back
    (scene-state-update state-with-back
                        back-circle
                        moved-back-circle))
  (check-equal? (scene-state-count empty-scene-state) 0)
  (check-equal? (scene-state-count state-with-back) 1)
  (check-equal?
   (visual-position (scene-state-ref state-with-back 'back))
   (vec2 -1 0))
  (check-equal?
   (visual-position (scene-state-ref state-with-moved-back 'back))
   (vec2 -2 1))
  (check-equal? (scene-state-drawing-order state-with-moved-back)
                '(back))
  (check-equal?
   (scene-state-remove state-with-moved-back 'back)
   empty-scene-state)

  ;; A play clip must contain at least one animation request.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play (make-scene))))

  ;; Timeline duration, clip count, and exact samples are stable.
  (check-equal? (scene-duration demo) 3/2)
  (check-equal? (scene-clip-count demo) 2)
  (check-equal? (position-at 0) (vec2 -3 0))
  (check-equal? (position-at 1/4) (vec2 -3/2 0))
  (check-equal? (position-at 1/2) origin)
  (check-equal? (position-at 3/4) (vec2 3/2 0))
  (check-equal? (position-at 1) (vec2 3 0))
  (check-equal? (position-at 5/4) (vec2 3 0))
  (check-equal? (position-at 3/2) (vec2 3 0))

  ;; Sampling outside the closed timeline interval is rejected.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-sample demo -1/30)))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-sample demo 46/30)))

  ;; Stable identity is preserved at starts, midpoints, boundaries, and end.
  (for ([time (in-list '(0 1/4 1/2 3/4 1 5/4 3/2))])
    (check-eq?
     (visual-id
      (scene-state-ref (scene-sample demo time)
                       'moving-circle))
     'moving-circle))

  ;; One play clip may update distinct visuals concurrently.

  ; left-circle : circle-visual?
  ;;   Gives the left Visual in the simultaneous-movement test.
  (define left-circle
    (circle #:id 'left
            #:center (vec2 -2 -1)
            #:radius 1/4))
  ; right-circle : circle-visual?
  ;;   Gives the right Visual in the simultaneous-movement test.
  (define right-circle
    (circle #:id 'right
            #:center (vec2 2 1)
            #:radius 1/4))
  ; simultaneous : scene?
  ;;   Gives a clip that moves two distinct Visuals concurrently.
  (define simultaneous
    (scene-play
     (scene-add (make-scene) left-circle right-circle)
     (move-to left-circle (vec2 0 -1))
     (move-to right-circle (vec2 0 1))
     #:duration 2))
  ; simultaneous-midpoint : scene-state?
  ;;   Gives the simultaneous scene state at half duration.
  (define simultaneous-midpoint
    (scene-sample simultaneous 1))
  (check-equal?
   (visual-position
    (scene-state-ref simultaneous-midpoint 'left))
   (vec2 -1 -1))
  (check-equal?
   (visual-position
    (scene-state-ref simultaneous-midpoint 'right))
   (vec2 1 1))

  ;; Simultaneous requests may not target the same visual twice.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) left-circle)
      (move-to left-circle origin)
      (move-to 'left (vec2 1 0)))))

  ;; Semantic coordinates reject infinities and NaNs before rendering.
  (check-exn exn:fail:contract?
             (lambda ()
               (vec2 +inf.0 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (vec2 +nan.0 0))))
