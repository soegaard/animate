#lang racket/base

;;; SCENE-3D-I Transparent Pass Tests

(require rackunit
         "../3d.rkt"
         "../private/color-style.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/software-renderer3d.rkt")

(define (triangle id z color)
  (mesh3d #:id id
          #:vertices (vector (vec3 -1 -1 z) (vec3 1 -1 z) (vec3 0 1 z))
          #:triangles (vector (vector 0 1 2))
          #:material (material3d #:color color #:shading 'unlit)))

(module+ test
  ;; The declared order intentionally puts the transparent face first.  The
  ;; opaque pass must still establish the red depth/color before the blue face
  ;; is blended in front of it.
  (define view
    (view3d
     (list (triangle 'blue 1 (rgba-color 0 0 255 1/2))
           (triangle 'red 0 (rgba-color 255 0 0 1)))
     #:id 'world #:render-mode 'opaque #:transparency-mode 'triangle-sorted
     #:camera (perspective-camera3d #:position (vec3 0 0 5) #:look-at origin3)))
  (define target (software-render-result-target (render-view3d-opaque view 64 48)))
  (define bytes (raster-target3d-color-bytes target))
  (define pixel-index (+ 32 (* 24 64)))
  (define byte-index (* 4 pixel-index))
  (check-equal? (bytes-ref bytes byte-index) 255)
  (check-true (<= 120 (bytes-ref bytes (add1 byte-index)) 136))
  (check-equal? (bytes-ref bytes (+ byte-index 2)) 0)
  (check-true (<= 120 (bytes-ref bytes (+ byte-index 3)) 136))

  ;; Both explicit sort modes are accepted and produce a deterministic frame.
  (check-true
   (software-render-result?
    (render-view3d-opaque
     (view3d (view3d-children view) #:id 'object-order #:render-mode 'opaque
             #:transparency-mode 'object-sorted
             #:camera (view3d-camera view))
     64 48))))
