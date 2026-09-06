#lang racket/base

;;; SCENE-3D-D Render Integration Tests

(require racket/class
         (only-in racket/math pi)
         (only-in pict pict->bitmap pict-height pict-width)
         rackunit
         "../3d.rkt"
         "../main.rkt")

(define cube-vertices
  (vector (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 1 1 -1) (vec3 -1 1 -1)
          (vec3 -1 -1 1) (vec3 1 -1 1) (vec3 1 1 1) (vec3 -1 1 1)))

(define cube-triangles
  (vector (vector 4 5 6) (vector 4 6 7)
          (vector 0 2 1) (vector 0 3 2)
          (vector 0 4 7) (vector 0 7 3)
          (vector 1 2 6) (vector 1 6 5)
          (vector 3 7 6) (vector 3 6 2)
          (vector 0 1 5) (vector 0 5 4)))

(define rendered-scene
  (scene-play
   (scene-add
    (make-scene)
    (view3d
     (list (mesh3d #:id 'cube #:vertices cube-vertices #:triangles cube-triangles
                   #:material (material3d #:color "cornflowerblue")))
     #:id 'world #:width 6 #:height 4 #:render-mode 'opaque
     #:camera (perspective-camera3d #:position (vec3 4 3 7) #:look-at origin3))
    (plain-text "A = R B" #:id 'formula #:center (vec2 0 3)
                #:font-size 1/3 #:color "navy"))
   (rotate3d-by '(world cube) (axis-angle y-axis3 (* 2 pi)))
   (camera3d-orbit-by 'world #:azimuth (* 2 pi) #:elevation (/ pi 12))
   #:duration 3))

(define test-camera
  (make-camera #:width 240 #:height 135 #:world-width 10 #:background "white"))

(define (argb-at time)
  (define picture (scene->pict rendered-scene time #:camera test-camera))
  (define bitmap (pict->bitmap picture 'smoothed))
  (define result (make-bytes (* 4 (pict-width picture) (pict-height picture))))
  (send bitmap get-argb-pixels 0 0 (pict-width picture) (pict-height picture) result)
  result)

(module+ test
  (check-not-equal? (argb-at 0) (argb-at 1))
  ;; The matrix-like ordinary overlay remains an ordinary 2D Visual rather
  ;; than being projected or rasterized as part of the 3D viewport.
  (check-equal? (visual-position (scene-visual-at rendered-scene 'formula 0))
                (visual-position (scene-visual-at rendered-scene 'formula 3))))
