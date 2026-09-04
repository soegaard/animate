#lang racket/base

;;;
;;; SCENE-ED: Live Mathematical Annotations
;;;

;; Dynamic endpoint annotations share `line-between`'s endpoint vocabulary.
;; This example deliberately mixes centre references (the two angle marks)
;; with renderer-measured circle anchors (the brace and curved arrow).

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-ED: live mathematical annotations"
                #:id 'title #:center (vec2 0 18/5)
                #:font-size 2/5 #:font-weight 'bold #:color "navy"))
  (define explanation
    (plain-text "Marks follow moving vertices and measured circle edges."
                #:id 'explanation #:center (vec2 0 3)
                #:font-size 1/5 #:color "darkslategray"))
  (define A
    (circle #:id 'A #:center (vec2 -2 -1) #:radius 1/6
            #:fill "aliceblue" #:stroke "navy" #:stroke-width 2))
  (define B
    (circle #:id 'B #:center (vec2 2 -1) #:radius 1/6
            #:fill "aliceblue" #:stroke "navy" #:stroke-width 2))
  (define C
    (circle #:id 'C #:center (vec2 -2 3/2) #:radius 1/6
            #:fill "aliceblue" #:stroke "navy" #:stroke-width 2))
  (define AB
    (segment-between 'A 'B #:id 'AB #:stroke "steelblue" #:stroke-width 4))
  (define BC
    (segment-between 'B 'C #:id 'BC #:stroke "steelblue" #:stroke-width 4))
  (define CA
    (segment-between 'C 'A #:id 'CA #:stroke "steelblue" #:stroke-width 4))
  (define right-mark
    (right-angle-between 'B 'A 'C #:id 'right-mark #:size 2/5
                         #:stroke "crimson" #:stroke-width 3))
  (define angle-mark
    (angle-between 'A 'C 'B #:id 'angle-mark #:radius 1/2
                   #:stroke "darkorange" #:stroke-width 3))
  ;; The brace is measured from the outer lower edges of the endpoint circles,
  ;; so it remains visibly separated from the blue base as those circles move.
  (define base-brace
    (brace-label (anchor-of 'A 'bottom #:offset (vec2 0 -1/12))
                 (anchor-of 'B 'bottom #:offset (vec2 0 -1/12))
                 "base" #:id 'base-brace #:offset -1/12 #:gap 1/6
                 #:font-size 1/4 #:color "darkgreen"
                 #:stroke "darkgreen" #:stroke-width 3))
  ;; This arc uses a pair of renderer-measured anchors. Its shaft and tangent
  ;; tip are rebuilt from the same resolved endpoints at every frame.
  (define relation-arrow
    (curved-arrow-between (anchor-of 'C 'right #:offset (vec2 0 1/12))
                          (anchor-of 'B 'top #:offset (vec2 0 1/12))
                          #:id 'relation-arrow #:angle -1
                          #:stroke "purple" #:stroke-width 3))
  (define initial
    (scene-add (make-scene)
               ;; The annotations sit behind the geometry they explain.
               right-mark angle-mark base-brace relation-arrow
               AB BC CA A B C title explanation))
  (scene-wait
   (scene-play initial
               ;; AB stays horizontal and AC stays vertical, making the
               ;; red marker an honest right-angle indicator throughout.
               (move-to 'A (vec2 -3 -1/4))
               (move-to 'B (vec2 3 -1/4))
               (move-to 'C (vec2 -3 2))
               #:duration 3)
   1))

(module+ main
  (run-demo "live-mathematical-annotations.rkt" make-demo-scene))
