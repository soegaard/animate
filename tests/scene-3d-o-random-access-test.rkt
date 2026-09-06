#lang racket/base

;;; SCENE-3D-O: retained stroke output is independent of render order

(require rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../private/3d/renderer3d.rkt")

(module+ test
  (define view
    (view3d
     (list
      (polyline3d (list (vec3 -2 -1 0) origin3 (vec3 2 -1 0)) #:id 'curve
                  #:style (stroke3d #:width 3 #:dash '(6 3) #:join 'round))
      (point3d origin3 #:id 'dot #:style (point-style3d #:size 10)))
     #:id 'world #:render-mode 'opaque #:background "white"
     #:camera (perspective-camera3d #:position (vec3 5 3 8) #:look-at origin3)))
  (define renderer (retained-software-renderer3d))
  (define request-a (view3d->render3d-request view 160 90))
  (define request-b (view3d->render3d-request view 240 135))
  (define (pixels request)
    (define preparation (renderer3d-prepare renderer request))
    (renderer3d-render-result-argb-bytes
     (renderer3d-render renderer preparation request)))
  (define a-first (pixels request-a))
  (void (pixels request-b))
  (define a-second (pixels request-a))
  (check-equal? a-first a-second)
  (renderer3d-release renderer))
