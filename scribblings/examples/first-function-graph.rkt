#lang racket/base
(require animate)

;; doc: axes begin
(define coordinates
  (axes #:id 'coordinates
        #:x-range (axis-range -3 3 1)
        #:y-range (axis-range -2 2 1)
        #:x-length 7 #:y-length 9/2
        #:stroke "navy"))
;; doc: axes end

;; doc: graph begin
(define curve
  (function-graph coordinates
                  (lambda (x) (- (/ (* x x) 4) 1))
                  #:id 'curve #:sample-count 81
                  #:interpolation 'linear
                  #:stroke "crimson" #:stroke-width 3))
;; doc: graph end

;; doc: draw begin
(define drawing
  (scene-play (scene-add (make-scene) coordinates)
              (create curve) #:duration 2))
(define film (scene-wait drawing 1))
;; doc: draw end

;; doc: move-both begin
(define diagram (group (list coordinates curve) #:id 'diagram))
(define moving-diagram
  (scene-play (scene-add (make-scene) diagram)
              (move-to 'diagram (vec2 2 0)) #:duration 2))
;; doc: move-both end

(provide coordinates curve drawing film diagram moving-diagram)
