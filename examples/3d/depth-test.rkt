#lang racket/base

;;; SCENE-3D-C: Order-independent Opaque Depth Test

(require animate
         animate/3d
         animate/render)

(provide make-depth-test-scene)

(define (triangle id z color)
  (mesh3d #:id id
          #:vertices (vector (vec3 -3/2 -1 z) (vec3 3/2 -1 z) (vec3 0 3/2 z))
          #:triangles (vector (vector 0 1 2))
          #:material (material3d #:color color #:shading 'unlit #:double-sided? #t)))

;; The cyan triangle is declared first yet it remains visible because it is
;; closer to the camera than the larger red triangle.  Reversing `children`
;; yields the same pixels except deliberately equal-depth ties.
(define (make-depth-test-scene #:reverse? [reverse? #f])
  (define children
    (list (triangle 'far -1 "tomato")
          (triangle 'near 1/2 "deepskyblue")))
  (scene-wait
   (scene-add
    (make-scene)
    (view3d (if reverse? (reverse children) children)
            #:id 'depth-world #:width 6 #:height 4
            #:camera (perspective-camera3d #:position (vec3 0 0 8)
                                           #:look-at origin3 #:near 1/10 #:far 30)
            #:render-mode 'opaque)
    (plain-text "Depth test: nearer cyan wins regardless of declaration order"
                #:id 'caption #:center (vec2 0 -13/5)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
   2))

(module+ main
  (render-frames! (make-depth-test-scene) "frames" #:fps 30))
