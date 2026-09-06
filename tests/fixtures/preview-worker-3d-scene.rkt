#lang racket/base

;; A minimal module-backed spatial scene for the subprocess override test.

(require "../../main.rkt"
         "../../3d.rkt")

(provide worker-3d-scene)

(define worker-3d-scene
  (scene-wait
   (scene-add
    (make-scene)
    (view3d
     (list (mesh3d #:id 'triangle
                   #:vertices (vector (vec3 -1 -1 0)
                                      (vec3 1 -1 0)
                                      (vec3 0 1 0))
                   #:triangles (vector (vector 0 1 2))))
     #:id 'world #:width 6 #:height 4 #:render-mode 'opaque
     #:camera (perspective-camera3d #:position (vec3 0 0 6) #:look-at origin3)))
   1))
