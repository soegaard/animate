;; doc: imports begin
#lang racket/base
(require (only-in racket/math pi) animate animate/3d
         "first-spatial-picture.rkt")
(provide object-motion camera-motion panel-motion translated-object
         make-lesson lesson)
;; doc: imports end

;; doc: object-motion begin
(define object-motion
  (scene-play still
              (rotate3d-by '(model brick)
                           (axis-angle y-axis3 (/ pi 2)))
              #:duration 2))
;; doc: object-motion end

;; doc: translation begin
(define translated-object
  (scene-play still
              (move3d-to '(model brick) (vec3 1 0 0))
              #:duration 2))
;; doc: translation end

;; doc: camera-motion begin
(define camera-motion
  (scene-play still
              (camera3d-orbit-by 'model #:azimuth (/ pi 2))
              #:duration 2))
;; doc: camera-motion end

;; doc: panel-motion begin
(define panel-motion
  (scene-play still
              (move-to 'model (vec2 2 0))
              #:duration 2))
;; doc: panel-motion end

;; doc: lesson begin
(define (make-lesson initial)
  (define turn
    (scene-play initial
                (rotate3d-by '(model brick)
                             (axis-angle y-axis3 (/ pi 2)))
                #:duration 2))
  (define read-turn (scene-wait turn 1))
  (define orbit
    (scene-play read-turn
                (camera3d-orbit-by 'model #:azimuth (/ pi 2))
                #:duration 2))
  (scene-wait orbit 1))

(define lesson (make-lesson still))
;; doc: lesson end
