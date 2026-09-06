#lang racket/base

;;;
;;; SCENE-3D-D Camera Animation Tests
;;;

(require (only-in racket/math pi)
         rackunit
         "../3d.rkt"
         "../main.rkt"
         (only-in "../private/3d/camera3d-animation.rkt"
                  camera3d-orbit-sample))

(define triangle
  (mesh3d #:id 'cube
          #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
          #:triangles (vector (vector 0 1 2))))

(define source-camera
  (perspective-camera3d #:position (vec3 0 0 6) #:look-at origin3
                        #:vertical-field-of-view (/ pi 3)))

(define source-view
  (view3d (list triangle) #:id 'world #:width 8 #:height 4
          #:camera source-camera #:render-mode 'opaque))

(define (camera-at scene time)
  (view3d-camera (scene-state-ref (scene-sample scene time) 'world)))

(module+ test
  (define moved
    (scene-play (scene-add (make-scene) source-view)
                (camera3d-move-to 'world (vec3 3 2 7))
                #:duration 2))
  (check-equal? (camera-at moved 0) source-camera)
  (check-equal? (camera3d-position (camera-at moved 2)) (vec3 3 2 7))
  (check-equal? (camera3d-position (camera-at moved 1)) (vec3 3/2 1 13/2))

  (define orbit
    (scene-play (scene-add (make-scene) source-view)
                (camera3d-orbit-by 'world #:azimuth (/ pi 2) #:elevation (/ pi 8))
                #:duration 2))
  (check-equal? (camera-at orbit 0) source-camera)
  (check-equal?
   (camera-at orbit 2)
   (camera3d-orbit-sample source-camera origin3 (/ pi 2) (/ pi 8) 1))
  ;; The camera's immutable quaternion is recomputed as a look-at pose from
  ;; each sampled orbit position.  Endpoint quaternion interpolation alone
  ;; could point away from the orbit centre halfway through a half-turn.
  (define halfway-orbit-camera (camera-at orbit 1))
  (check-true
   (< (vec3-distance
       (camera3d-forward halfway-orbit-camera)
       (vec3-normalize
        (vec3- origin3 (camera3d-position halfway-orbit-camera))))
      1e-10))

  (define narrowed
    (scene-play (scene-add (make-scene) source-view)
                (camera3d-field-of-view-to 'world (/ pi 6))
                #:duration 1))
  (check-equal?
   (perspective-projection3d-vertical-field-of-view
    (camera3d-projection (camera-at narrowed 1)))
   (/ pi 6))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add
                 (make-scene)
                 (view3d (list triangle) #:id 'world
                         #:camera (orthographic-camera3d)))
                (camera3d-field-of-view-to 'world (/ pi 4))
                #:duration 1)))

  (define orthographic
    (orthographic-camera3d #:position (vec3 0 0 6) #:look-at origin3
                           #:vertical-size 8))
  (define orthographic-scene
    (scene-play
     (scene-add (make-scene)
                (view3d (list triangle) #:id 'world #:camera orthographic))
     (camera3d-orthographic-height-to 'world 4)
     #:duration 1))
  (check-equal?
   (orthographic-projection3d-vertical-size
    (camera3d-projection (camera-at orthographic-scene 1)))
   4)

  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) source-view)
                (camera3d-orthographic-height-to 'world 4)
                #:duration 1)))

  (define looked
    (scene-play (scene-add (make-scene) source-view)
                (camera3d-look-at-to 'world (vec3 2 0 0))
                #:duration 1))
  (check-equal? (camera3d-position (camera-at looked 1)) (vec3 0 0 6))
  (check-not-equal? (camera3d-rotation (camera-at looked 1))
                    (camera3d-rotation source-camera))

  (define rolled
    (scene-play (scene-add (make-scene) source-view)
                (camera3d-roll-to 'world (/ pi 4))
                #:duration 1))
  (check-not-equal? (camera3d-up (camera-at rolled 1))
                    (camera3d-up source-camera))

  (define dolly
    (scene-play (scene-add (make-scene) source-view)
                (camera3d-dolly-by 'world 2)
                #:duration 1))
  (check-equal? (camera3d-position (camera-at dolly 1)) (vec3 0 0 4))

  ;; Fitting frames immutable mesh bounds rather than assuming the source
  ;; camera already looks at their centre.
  (define fitted
    (scene-play (scene-add (make-scene) source-view)
                (camera3d-fit 'world #:padding 6/5)
                #:duration 1))
  (for ([point (in-vector (mesh3d-vertices triangle))])
    (check-not-false
     (camera3d-project (camera-at fitted 1) point #:aspect 2)))

  ;; Follow applies the captured offset to the target sampled at this exact
  ;; time. It is not an eased camera move that lags a concurrently moving mesh.
  (define followed
    (scene-play
     (scene-add (make-scene) source-view)
     (animation-group
      (move3d-to '(world cube) (vec3 2 0 0))
      (camera3d-follow 'world '(world cube)))
     #:duration 2))
  (check-equal? (camera3d-position (camera-at followed 1)) (vec3 1 0 6))
  (check-equal? (camera3d-position (camera-at followed 2)) (vec3 2 0 6)))
