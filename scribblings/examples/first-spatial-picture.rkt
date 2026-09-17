;; doc: imports begin
#lang racket/base
(require animate animate/3d)
(provide brick model still picture-at)
;; doc: imports end

;; doc: solid begin
(define brick
  (box3d 5/2 3/2 1
         #:id 'brick
         #:material (material3d #:color "cornflowerblue"
                                #:shading 'flat)))
;; doc: solid end

;; doc: camera begin
(define viewpoint
  (perspective-camera3d #:position (vec3 3 2 5)
                        #:look-at origin3))
;; doc: camera end

;; doc: view begin
(define model
  (view3d (list brick)
          #:id 'model
          #:width 10
          #:height 45/8
          #:camera viewpoint
          #:render-mode 'opaque
          #:background "aliceblue"))
;; doc: view end

;; doc: scene begin
(define still
  (scene-add (make-scene) model))
;; doc: scene end

;; doc: picture begin
(define (picture-at time)
  (scene-state->pict (scene-sample still time)
                     #:camera (scene-camera-at still time)))

;; Call (picture-at 0) in DrRacket to see the picture.
;; doc: picture end
