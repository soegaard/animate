#lang racket/base

;;; SCENE-3D-V4: direct, stable-ID finite-light animation sampling

(require rackunit
         "../main.rkt"
         "../3d.rkt"
         "../colors.rkt")

(define (within? actual expected [epsilon 1e-10])
  (<= (abs (- actual expected)) epsilon))

(define camera
  (perspective-camera3d #:position (vec3 0 0 8) #:look-at origin3))

(define initial-lights
  (list (ambient-light3d #:id 'fill #:intensity 1/4 #:color "white")
        (directional-light3d (vec3 0 0 -1) #:id 'key #:intensity 1 #:color "red")
        (point-light3d (vec3 -2 1 2) #:id 'lamp #:intensity 1 #:range 10)
        (spot-light3d (vec3 2 2 2) (vec3 -1 -1 -1)
                      #:id 'spot #:intensity 1 #:inner-angle 1/8 #:outer-angle 1/3)))

(define base-view
  (view3d
   (list (cube3d 1 #:id 'cube))
   #:id 'world #:width 6 #:height 4 #:camera camera #:lights initial-lights))

(define base-scene (scene-add (make-scene) base-view))

(define (view-at scene time)
  (scene-visual-at scene 'world time))

(define (light-at scene time id)
  (view3d-light-ref (view-at scene time) id))

(module+ test
  ;; All source fields are captured at clip start. Sampling 3/2, then 1/2,
  ;; then 3/2 again yields the identical result: nothing relies on playback
  ;; history or a mutable frame updater.
  (define intensity-scene
    (scene-play base-scene #:duration 2
                (light3d-intensity-to 'world 'key 3)))
  (define late-first (light-at intensity-scene 3/2 'key))
  (define early (light-at intensity-scene 1/2 'key))
  (define late-second (light-at intensity-scene 3/2 'key))
  (check-equal? (directional-light3d-intensity late-first) 5/2)
  (check-equal? (directional-light3d-intensity early) 3/2)
  (check-equal? late-first late-second)
  (check-equal? (directional-light3d-intensity (light-at intensity-scene 2 'key)) 3)

  ;; The semantic sample records the declared linear-light transition.  An
  ;; explicit rendering context resolves it later, rather than scene sampling
  ;; forcing a numerical color early.
  (define colour-scene
    (scene-play base-scene #:duration 1 (light3d-color-to 'world 'key "blue")))
  (define midpoint-colour (directional-light3d-color (light-at colour-scene 1/2 'key)))
  (check-equal? midpoint-colour (color-mix "red" "blue" 1/2))
  (check-equal? (directional-light3d-color (light-at colour-scene 0 'key))
                (directional-light3d-color (car (cdr initial-lights))))
  (check-equal? (directional-light3d-color (light-at colour-scene 1 'key))
                (rgb-color 0 0 255))

  ;; Finite-light position, aiming, and cone fields all compile from their
  ;; source values without involving renderer implementation state.
  (define finite-scene
    (scene-play
     base-scene #:duration 2
     (animation-group
      (point-light3d-move-by 'world 'lamp (vec3 4 0 0))
      (spot-light3d-move-to 'world 'spot (vec3 0 4 2))
      (spot-light3d-aim-at 'world 'spot (vec3 -2 2 2))
      (spot-light3d-cone-to 'world 'spot 1/4 1/2))))
  (define lamp-mid (light-at finite-scene 1 'lamp))
  (define spot-mid (light-at finite-scene 1 'spot))
  (check-equal? (point-light3d-position lamp-mid) (vec3 0 1 2))
  (check-equal? (spot-light3d-position spot-mid) (vec3 1 3 2))
  (check-true (within? (vec3-length (spot-light3d-direction spot-mid)) 1))
  (check-equal? (spot-light3d-inner-angle spot-mid) 3/16)
  (check-equal? (spot-light3d-outer-angle spot-mid) 5/12)
  (define spot-final (light-at finite-scene 2 'spot))
  (check-equal? (spot-light3d-position spot-final) (vec3 0 4 2))
  (check-equal? (spot-light3d-inner-angle spot-final) 1/4)
  (check-equal? (spot-light3d-outer-angle spot-final) 1/2)

  ;; The vector-lerp singularity at a 180-degree turn uses the deterministic
  ;; rotation fallback, so the middle direction remains normalized and does
  ;; not collapse to the zero vector.
  (define opposite-scene
    (scene-play
     (scene-add
      (make-scene)
      (view3d '() #:id 'opposite
              #:lights (list (spot-light3d origin3 x-axis3 #:id 'spot))))
     #:duration 1
     (spot-light3d-aim-at 'opposite 'spot (vec3 -1 0 0))))
  (define opposite-mid
    (spot-light3d-direction
     (view3d-light-ref (scene-visual-at opposite-scene 'opposite 1/2) 'spot)))
  (check-true (within? (vec3-length opposite-mid) 1))
  (check-true (within? (vec3-dot opposite-mid x-axis3) 0))
  (check-true
   (within?
    (vec3-dot
     (spot-light3d-direction
      (view3d-light-ref (scene-visual-at opposite-scene 'opposite 1) 'spot))
     (vec3 -1 0 0))
    1))

  ;; Every scheduler uses the same immutable compiled requests: delayed leaves
  ;; hold their source, succession captures the endpoint before the next leaf,
  ;; and lagged starts complete both independently addressed components.
  (define timed-scene
    (scene-play
     base-scene #:duration 4
     (timed (light3d-intensity-to 'world 'key 3) #:start 1 #:duration 2)))
  (check-equal? (directional-light3d-intensity (light-at timed-scene 1/2 'key)) 1)
  (check-equal? (directional-light3d-intensity (light-at timed-scene 2 'key)) 2)
  (check-equal? (directional-light3d-intensity (light-at timed-scene 3 'key)) 3)

  (define succession-scene
    (scene-play
     base-scene #:duration 2
     (succession (light3d-intensity-to 'world 'key 3)
                 (light3d-color-to 'world 'key "blue"))))
  (check-equal? (directional-light3d-intensity (light-at succession-scene 1 'key)) 3)
  (check-equal? (directional-light3d-color (light-at succession-scene 1 'key))
                (rgb-color 255 0 0))
  (check-equal? (directional-light3d-color (light-at succession-scene 2 'key))
                (rgb-color 0 0 255))

  (define lagged-scene
    (scene-play
     base-scene #:duration 2
     (lagged-start #:lag-ratio 1/2
                   (light3d-intensity-to 'world 'key 3)
                   (light3d-color-to 'world 'key "blue"))))
  (check-equal? (directional-light3d-intensity (light-at lagged-scene 2 'key)) 3)
  (check-equal? (directional-light3d-color (light-at lagged-scene 2 'key))
                (rgb-color 0 0 255))

  ;; A semantic timing curve changes only the sampled phase, preserving exact
  ;; endpoints and direct seek behaviour for light values.
  (define sped-scene
    (scene-play base-scene #:duration 1
                #:easing (change-speed '((0 1) (1/2 3) (1 3)))
                (light3d-intensity-to 'world 'key 3)))
  (check-equal? (directional-light3d-intensity (light-at sped-scene 1/2 'key)) 9/5)
  (check-equal? (directional-light3d-intensity (light-at sped-scene 1 'key)) 3)

  ;; Light, spatial-object, and camera transitions can run together. They all
  ;; resolve against the same clip-start scene state without target aliasing.
  (define combined-scene
    (scene-play
     base-scene #:duration 2
     (animation-group
      (light3d-intensity-to 'world 'key 3)
      (move3d-to '(world cube) (vec3 2 0 0))
      (camera3d-move-to 'world (vec3 0 0 4)))))
  (define combined-view (view-at combined-scene 1))
  (check-equal? (directional-light3d-intensity (view3d-light-ref combined-view 'key)) 2)
  (check-equal? (spatial-position (view3d-spatial-ref combined-view '(world cube)))
                (vec3 1 0 0))
  (check-equal? (camera3d-position (view3d-camera combined-view)) (vec3 0 0 6))

  ;; Construction validates symbolic targets, and compilation validates the
  ;; selected kind plus component conflicts against the actual clip-start view.
  (check-exn exn:fail? (lambda () (light3d-intensity-to "world" 'key 2)))
  (check-exn exn:fail?
             (lambda () (scene-play base-scene (point-light3d-move-to 'world 'key origin3))))
  (check-exn exn:fail?
             (lambda ()
               (scene-play base-scene
                           (light3d-intensity-to 'world 'key 2)
                           (light3d-intensity-to 'world 'key 3)))))
