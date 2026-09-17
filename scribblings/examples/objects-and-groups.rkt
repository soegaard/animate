#lang racket/base
(require animate)

;; doc: objects begin
(define dot
  (circle #:id 'dot #:center (vec2 -1 0) #:radius 1/2
          #:fill "dodgerblue" #:stroke "navy"))
(define tile
  (rectangle #:id 'tile #:center (vec2 1 0) #:width 1 #:height 1
             #:fill "gold" #:stroke "sienna"))
;; doc: objects end

;; doc: independent begin
(define separate (scene-add (make-scene) dot tile))
(define one-moves
  (scene-play separate (move-to 'dot (vec2 -1 2)) #:duration 2))
;; doc: independent end

;; doc: group begin
(define pair
  (group (list dot tile) #:id 'pair #:center (vec2 1 0)))
(define grouped (scene-add (make-scene) pair))
;; doc: group end

;; doc: move-group begin
(define group-moves
  (scene-play grouped (move-to 'pair (vec2 -1 0)) #:duration 2))
;; doc: move-group end

;; doc: move-child begin
(define child-moves
  (scene-play grouped (move-to '(pair dot) (vec2 -1 2)) #:duration 2))
;; doc: move-child end

(provide dot tile separate one-moves pair grouped group-moves child-moves)
