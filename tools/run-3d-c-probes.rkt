#lang racket/base

;;; SCENE-3D-C Opaque-render Visual Probes

;; Generates compact visual evidence for clipping, culling, depth, lighting,
;; transforms, projection, and ordinary 2D composition.  Outputs are ignored
;; generated artifacts under rendered-examples/3d-c/.

(require racket/class
         (only-in pict pict->bitmap)
         (only-in racket/file make-directory*)
         (only-in racket/math pi)
         racket/runtime-path
         animate
         animate/3d
         "../examples/3d/opaque-cube.rkt"
         "../examples/3d/depth-test.rkt")

(define-runtime-path repository-root "..")
(define output-directory (build-path repository-root "rendered-examples" "3d-c"))

(define perspective-camera
  (perspective-camera3d #:position (vec3 4 3 7) #:look-at origin3
                        #:near 1/10 #:far 30 #:vertical-field-of-view (/ pi 5)))

(define (save-scene! name scene)
  (define bitmap
    (pict->bitmap
     (scene->pict scene 0
                  #:camera (make-camera #:width 640 #:height 360 #:world-width 12))
     'smoothed))
  (define output (build-path output-directory name))
  (unless (send bitmap save-file output 'png)
    (error 'run-3d-c-probes "could not write ~a" output))
  (printf "wrote ~a\n" output))

(define (caption text)
  (plain-text text #:id 'caption #:center (vec2 0 13/4)
              #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))

(define (one-view view text)
  (scene-wait (scene-add (make-scene) view (caption text)) 1))

(define (face id vertices material)
  (mesh3d #:id id #:vertices vertices #:triangles (vector (vector 0 1 2))
          #:material material))

(module+ main
  (make-directory* output-directory)
  (save-scene!
   "opaque-cube-lighting.png"
   (make-demo-scene))
  (save-scene! "depth-order.png" (make-depth-test-scene))
  (save-scene! "depth-order-reversed.png" (make-depth-test-scene #:reverse? #t))
  (define clipping-camera
    (perspective-camera3d #:position origin3 #:rotation identity-rotation3
                          #:near 1 #:far 5 #:vertical-field-of-view (/ pi 3)))
  (save-scene!
   "near-crossing.png"
   (one-view
    (view3d
     (list (face 'crossing
                 (vector (vec3 -1 -1 -1/4) (vec3 1 -1 -2) (vec3 0 1 -2))
                 (material3d #:color "gold" #:shading 'unlit #:double-sided? #t)))
     #:id 'world #:width 6 #:height 4 #:camera clipping-camera #:render-mode 'opaque)
    "Triangle clipped by the near plane"))
  (save-scene!
   "far-clipping.png"
   (one-view
    (view3d
     (list (face 'far-crossing
                 (vector (vec3 -1 -1 -2) (vec3 1 -1 -6) (vec3 0 1 -2))
                 (material3d #:color "orchid" #:shading 'unlit #:double-sided? #t)))
     #:id 'world #:width 6 #:height 4 #:camera clipping-camera #:render-mode 'opaque)
    "Triangle clipped by the far plane"))
  (save-scene!
   "frustum-sides.png"
   (one-view
    (view3d
     (list (face 'side-crossing
                 (vector (vec3 -8 -1 -3) (vec3 1 -1 -3) (vec3 0 2 -3))
                 (material3d #:color "seagreen" #:shading 'unlit #:double-sided? #t)))
     #:id 'world #:width 6 #:height 4 #:camera clipping-camera #:render-mode 'opaque)
    "Triangle clipped by the side planes"))
  (save-scene!
   "backface-culling.png"
   (one-view
    (view3d
     (list (face 'front (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
                 (material3d #:color "royalblue" #:shading 'unlit))
           (face 'back (vector (vec3 -1 -1 -1/10) (vec3 0 1 -1/10) (vec3 1 -1 -1/10))
                 (material3d #:color "tomato" #:shading 'unlit)))
     #:id 'world #:width 6 #:height 4 #:camera clipping-camera #:render-mode 'opaque)
    "The rear clockwise face is culled"))
  (save-scene!
   "double-sided.png"
   (one-view
    (view3d
     (list (face 'back
                 (vector (vec3 -1 -1 0) (vec3 0 1 0) (vec3 1 -1 0))
                 (material3d #:color "tomato" #:shading 'unlit #:double-sided? #t)))
     #:id 'world #:width 6 #:height 4 #:camera clipping-camera #:render-mode 'opaque)
    "A double-sided clockwise face remains visible"))
  (save-scene!
   "nested-nonuniform.png"
   (one-view
    (view3d
     (list
      (group3d
       (list (make-opaque-cube
              'cube #:color "cornflowerblue"
              #:transform (make-transform3 #:rotation (axis-angle y-axis3 (/ pi 6)))))
       #:id 'outer
       #:transform (make-transform3 #:translation (vec3 1/2 0 0)
                                    #:scale (vec3 3/2 3/4 5/4))))
     #:id 'world #:width 6 #:height 4 #:camera perspective-camera #:render-mode 'opaque)
    "Nested nonuniform scale uses inverse-transpose face normals"))
  (save-scene!
   "orthographic-opaque.png"
   (one-view
    (view3d (list (make-opaque-cube 'cube #:color "darkorange"))
            #:id 'world #:width 6 #:height 4 #:render-mode 'opaque
            #:camera (orthographic-camera3d #:position (vec3 4 3 7) #:look-at origin3
                                            #:near 1/10 #:far 30 #:vertical-size 5))
    "Opaque orthographic projection"))
  (save-scene!
   "outer-opacity.png"
   (scene-wait
    (scene-add
     (make-scene)
     (rounded-rectangle #:id 'backdrop #:center origin #:width 7 #:height 5/2
                        #:fill "midnightblue" #:stroke-width 0)
     (view3d (list (make-opaque-cube 'cube #:color "gold"))
             #:id 'world #:width 6 #:height 4 #:camera perspective-camera
             #:render-mode 'opaque #:opacity 3/5)
     (caption "Ordinary outer view opacity composes after opaque depth rendering"))
    1)))
