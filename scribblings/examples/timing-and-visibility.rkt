#lang racket/base
(require animate)

;; doc: start begin
(define dot
  (circle #:id 'dot #:center (vec2 -3 1) #:radius 1/2
          #:fill "dodgerblue" #:stroke "navy"))
(define tile
  (rectangle #:id 'tile #:center (vec2 -3 -1) #:width 1 #:height 1
             #:fill "gold" #:stroke "sienna"))
(define initial (scene-add (make-scene) dot tile))
;; doc: start end

;; doc: together begin
(define together
  (scene-play initial
              (move-to 'dot (vec2 3 1))
              (move-to 'tile (vec2 3 -1))
              #:duration 2))
;; doc: together end

;; doc: in-order begin
(define first-move
  (scene-play initial (move-to 'dot (vec2 3 1)) #:duration 1))
(define in-order
  (scene-play first-move (move-to 'tile (vec2 3 -1)) #:duration 1))
;; doc: in-order end

;; doc: overlapping begin
(define overlapping
  (scene-play initial
              (timed (move-to 'dot (vec2 3 1)) #:start 0 #:duration 2)
              (timed (move-to 'tile (vec2 3 -1)) #:start 1/2 #:duration 2)
              #:duration 5/2))
;; doc: overlapping end

;; doc: ease begin
(define eased
  (scene-play initial
              (move-to 'dot (vec2 3 1))
              (move-to 'tile (vec2 3 -1))
              #:duration 2 #:easing (smooth)))
;; doc: ease end

;; doc: entrance begin
(define appearing
  (scene-play (make-scene) (fade-in dot) #:duration 1))
;; doc: entrance end

;; doc: invisible begin
(define invisible
  (scene-play (scene-add (make-scene) dot)
              (fade-to 'dot 0) #:duration 1))
;; doc: invisible end

;; doc: removed begin
(define removed
  (scene-play (scene-add (make-scene) dot)
              (fade-out 'dot) #:duration 1))
;; doc: removed end

;; doc: restore begin
(define visible-again
  (scene-play invisible (fade-to 'dot 1) #:duration 1))
(define reintroduced
  (scene-play removed (fade-in dot) #:duration 1))
;; doc: restore end

(provide dot tile initial together first-move in-order overlapping eased
         appearing invisible removed visible-again reintroduced)
