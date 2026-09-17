#lang racket/base
(require animate)
(provide disc initial movement animation)

;; doc: object begin
(define disc
  (circle #:id 'moving-circle
          #:center (vec2 -3 0)
          #:radius 3/4
          #:fill "dodgerblue"
          #:stroke "navy"
          #:stroke-width 3))
;; doc: object end

;; doc: scene begin
(define initial
  (scene-add (make-scene) disc))
;; doc: scene end

;; doc: motion begin
(define movement
  (scene-play initial
              (move-to 'moving-circle (vec2 3 0))
              #:duration 1))
;; doc: motion end

;; doc: hold begin
(define animation (scene-wait movement 1/2))
;; doc: hold end
