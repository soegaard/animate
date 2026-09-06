#lang racket/base

;;; SCENE-3D-C Random Access and Cancellation Tests

(require racket/class
         (only-in pict pict->bitmap pict-width pict-height)
         rackunit
         "../3d.rkt"
         "../main.rkt"
         "../private/preview-cancellation.rkt"
         "../private/3d/software-renderer3d.rkt")

(define mesh
  (mesh3d #:id 'face
          #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
          #:triangles (vector (vector 0 1 2))))
(define view
  (view3d (list mesh) #:id 'world #:render-mode 'opaque
          #:camera (perspective-camera3d #:position (vec3 0 0 6) #:look-at origin3)))

(define (argb scene time)
  (define pict-value (scene->pict scene time
                                  #:camera (make-camera #:width 160 #:height 90 #:world-width 10)))
  (define bitmap (pict->bitmap pict-value 'smoothed))
  (define bytes (make-bytes (* 4 (pict-width pict-value) (pict-height pict-value))))
  (send bitmap get-argb-pixels 0 0 (pict-width pict-value) (pict-height pict-value) bytes)
  bytes)

(module+ test
  (define scene (scene-wait (scene-add (make-scene) view) 2))
  (check-equal? (argb scene 0) (argb scene 3/2))
  (define token (make-cancellation-token))
  (cancel! token 'test)
  (check-exn exn:fail:preview-canceled?
             (lambda () (render-view3d-opaque view 32 24 #:cancellation-token token)))
  ;; The ordinary Pict adapter inherits a preview token dynamically, which is
  ;; how in-process preview rendering reaches the software scanline checks.
  (define adapter-token (make-cancellation-token))
  (cancel! adapter-token 'test)
  (check-exn exn:fail:preview-canceled?
             (lambda ()
               (parameterize ([current-software-render-cancellation-token adapter-token])
                 (scene->pict scene 0
                              #:camera (make-camera #:width 160 #:height 90 #:world-width 10))))))
