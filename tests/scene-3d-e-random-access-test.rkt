#lang racket/base

;;;
;;; SCENE-3D-E Random-Access Tests
;;;

(require racket/class
         rackunit
         (only-in pict pict->bitmap pict-width pict-height)
         "../3d.rkt"
         "../main.rkt")

(define outer-camera
  (make-camera #:width 240 #:height 135 #:world-width 10))

(define vertex
  (mesh3d #:id 'A
          #:vertices (vector origin3)
          #:transform (make-transform3 #:translation (vec3 -1 0 0))))
(define destination
  (mesh3d #:id 'B
          #:vertices (vector origin3)
          #:transform (make-transform3 #:translation (vec3 1 0 0))))
(define world
  (view3d (list vertex destination
                (arrow-between3d '(A) '(B) #:id 'arrow #:color "tomato"))
          #:id 'world
          #:width 8 #:height 4
          #:camera (perspective-camera3d #:position (vec3 0 0 6)
                                         #:look-at origin3)
          #:render-mode 'opaque))
(define label
  (follow-projected-spatial
   (plain-text "A" #:id 'label #:font-size 1/3)
   #:view 'world #:target '(A) #:offset (vec2 6 6)))
(define animation
  (scene-play
   (scene-add (scene-add (make-scene) world) label)
   (animation-group
    (move3d-to '(world A) (vec3 -2 1 0))
    (camera3d-move-to 'world (vec3 2 1 7)))
   #:duration 2))

(define (frame-bytes time)
  (define rendered (scene->pict animation time #:camera outer-camera))
  (define bitmap (pict->bitmap rendered))
  (define bytes
    (make-bytes (* 4 (inexact->exact (ceiling (pict-width rendered)))
                  (inexact->exact (ceiling (pict-height rendered))))))
  (send bitmap get-argb-pixels 0 0
        (inexact->exact (ceiling (pict-width rendered)))
        (inexact->exact (ceiling (pict-height rendered)))
        bytes)
  bytes)

(module+ test
  ;; Sampling/rendering a middle frame before or after either endpoint must not
  ;; retain relation or projection history. The frame bytes are exact.
  (define baseline (frame-bytes 1))
  (void (frame-bytes 0))
  (void (frame-bytes 2))
  (check-equal? (frame-bytes 1) baseline)
  (void (frame-bytes 3/2))
  (void (frame-bytes 1/4))
  (check-equal? (frame-bytes 1) baseline))
