#lang racket/base

(require rackunit
         racket/file
         "../main.rkt"
         "../3d.rkt"
         "../private/frame-renderer.rkt"
         "../render.rkt")

(module+ test
  (define calls (box 0))
  (define trajectory
    (prepare-ode-trajectory3d
     (lambda (_x _y _z)
       (set-box! calls (add1 (unbox calls)))
       x-axis3)
     origin3 #:time-range (cons 0 1) #:step-size 1 #:checkpoint-every 1))
  (set-box! calls 0)
  (define phase (parameter 'phase 0))
  (define scene
    (scene-play
     (scene-add
      (scene-set-value (make-scene) phase)
      (view3d (list (flow-particle3d trajectory phase #:id 'particle))
              #:id 'world #:width 4 #:height 3 #:render-mode 'opaque
              #:camera (perspective-camera3d #:position (vec3 2 2 5)
                                             #:look-at origin3)))
     (value-to phase 1) #:duration 1))
  (define directory (make-temporary-file "animate-3d-ode-parallel~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define paths (render-frames! scene directory #:fps 2 #:workers 2))
     (check-equal? (length paths) 2)
     ;; The phase values are 0 and 1/2.  Preparation performs one RK4
     ;; remainder (four calls); parallel workers do not call the field.
     (check-equal? (unbox calls) 4)
     ;; The direct one-frame renderer has the same preparation boundary.  It
     ;; does not build one table and then integrate a second time while the
     ;; spatial relation is resolved.
     (set-box! calls 0)
     (scene->pict scene 1/2)
     (check-equal? (unbox calls) 4))
   (lambda () (delete-directory/files directory))))
