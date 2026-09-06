#lang racket/base

;;; SCENE-3D-I Projected Label Occlusion Tests

(require rackunit
         "../3d.rkt"
         "../main.rkt"
         "../private/3d/projected-label.rkt")

(module+ test
  (define outer-camera (make-camera #:width 800 #:height 450 #:world-width 10))
  (define world
    (view3d (list (cube3d 2 #:id 'cube))
            #:id 'world #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 5)
                                           #:look-at origin3)))
  (define (label mode)
    (projected-label (plain-text "O" #:id (string->symbol (format "~a-label" mode)))
                     #:view 'world #:target origin3 #:occlusion mode))
  (check-equal? (visual-opacity (resolve-projected-label (label 'hide) world outer-camera)) 0)
  (check-equal? (visual-opacity (resolve-projected-label (label 'fade) world outer-camera)) 1/4)
  (check-equal? (visual-opacity (resolve-projected-label (label 'always-visible)
                                                        world outer-camera))
                1))
