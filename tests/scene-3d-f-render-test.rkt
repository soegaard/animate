#lang racket/base

;;; SCENE-3D-F Render Integration Tests

(require racket/class
         (only-in racket/draw bitmap%)
         rackunit
         (only-in pict pict->bitmap pict?)
         "../3d.rkt"
         "../main.rkt")

(module+ test
  (define world
    (view3d
     (list (coordinate-plane3d 'xy #:id 'plane #:u-range (list -2 2) #:v-range (list -2 2))
           (grid-plane3d 'xy #:id 'grid #:u-range (list -2 2) #:v-range (list -2 2))
           (axes3d #:id 'axes #:x-range (list -2 2) #:y-range (list -2 2) #:z-range (list -2 2))
           (vector-components3d (vec3 1 1 1) #:id 'components))
     #:id 'world #:width 6 #:height 4 #:render-mode 'opaque
     #:camera (perspective-camera3d #:position (vec3 4 3 6) #:look-at origin3)))
  (define rendered
    (scene->pict (scene-wait (scene-add (make-scene) world) 1) 0
                 #:camera (make-camera #:width 240 #:height 160 #:world-width 8)))
  (check-true (pict? rendered))
  (check-true (is-a? (pict->bitmap rendered) bitmap%)))
