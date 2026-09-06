#lang racket/base

;;;
;;; SCENE-3D-B Wireframe Rendering Tests
;;;

(require racket/class
         (only-in pict pict? pict->bitmap pict-width pict-height)
         rackunit
         "../3d.rkt"
         "../main.rkt"
         "../private/3d/wireframe-renderer.rkt")

(define cube-vertices
  (vector (vec3 -1 -1 -1) (vec3 1 -1 -1)
          (vec3 1 1 -1) (vec3 -1 1 -1)
          (vec3 -1 -1 1) (vec3 1 -1 1)
          (vec3 1 1 1) (vec3 -1 1 1)))

(define cube-edges
  (vector (vector 0 1) (vector 1 2) (vector 2 3) (vector 3 0)
          (vector 4 5) (vector 5 6) (vector 6 7) (vector 7 4)
          (vector 0 4) (vector 1 5) (vector 2 6) (vector 3 7)))

(define (cube id)
  (mesh3d #:id id #:vertices cube-vertices #:edges cube-edges
          #:wireframe-color "navy" #:wireframe-width 2))

(define (pict-argb pict-value)
  (define bitmap (pict->bitmap pict-value 'smoothed))
  (define bytes
    (make-bytes (* 4 (pict-width pict-value) (pict-height pict-value))))
  (send bitmap get-argb-pixels 0 0 (pict-width pict-value) (pict-height pict-value)
        bytes)
  bytes)

(module+ test
  (define camera
    (perspective-camera3d #:position (vec3 4 3 6)
                          #:look-at origin3 #:near 1/10 #:far 30))
  (define view
    (view3d (list (cube 'cube)) #:id 'world #:camera camera
            #:width 6 #:height 4 #:center origin))
  (define title
    (plain-text #:id 'title #:center (vec2 0 3) "wireframe" #:font-size 20))
  (define scene (scene-wait (scene-add (make-scene) view title) 1))
  (check-true (pict? (scene->pict scene 0
                                  #:camera (make-camera #:width 320 #:height 180
                                                        #:world-width 10))))
  ;; A segment crossing the near plane is retained with a clipped endpoint.
  (define near-line
    (mesh3d #:id 'near-line
            #:vertices (vector (vec3 -1 0 79/10) (vec3 1 0 0))
            #:edges (vector (vector 0 1))))
  (define near-view
    (view3d (list near-line) #:id 'near-world #:camera camera))
  (check-equal?
   (length (spatial-tree->wireframe-segments near-view camera 3/2))
   1)
  ;; The same static scene sample is independent of requested frame order.
  (define first (scene->pict scene 0 #:camera (make-camera #:width 320 #:height 180
                                                            #:world-width 10)))
  (define later (scene->pict scene 1/2 #:camera (make-camera #:width 320 #:height 180
                                                              #:world-width 10)))
  (check-equal? (pict-argb first) (pict-argb later)))
