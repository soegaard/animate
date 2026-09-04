#lang racket/base

;;;
;;; SCENE-DX: General Matching Transforms
;;;

;; Matching uses the relative paths of the named leaves below each top-level
;; diagram. The two composite endpoint roots have distinct identities, but
;; their `input`, `process`, `edge`, and `caption` leaves remain semantically
;; addressable through the transition.

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-DX: transform matching for diagrams"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 2/5 #:font-weight 'bold #:color "navy"))
  (define explanation
    (plain-text "Named leaves move and morph; unmatched material fades."
                #:id 'explanation #:center (vec2 0 14/5)
                #:font-size 1/5 #:color "darkslategray"))
  (define before
    (group
     (list
      (circle #:id 'input #:center (vec2 -2 0) #:radius 2/3
              #:fill "lightsteelblue" #:stroke "navy" #:stroke-width 3)
      (rounded-rectangle #:id 'process #:center (vec2 2 0)
                         #:width 5/3 #:height 4/3 #:corner-radius 1/4
                         #:fill "lemonchiffon" #:stroke "darkorange" #:stroke-width 3)
      (arrow (vec2 -13/10 0) (vec2 11/10 0) #:id 'edge
             #:stroke "slategray" #:stroke-width 3)
      (plain-text "input" #:id 'caption #:center (vec2 -2 -1)
                  #:font-size 1/4 #:color "navy"))
     #:id 'before))
  (define after
    (group
     (list
      ;; The leaf names are intentionally retained while the types and layout
      ;; change: the input becomes a rectangular result card, while the process
      ;; becomes the circular output marker.
      (rectangle #:id 'input #:center (vec2 -2 0) #:width 5/3 #:height 4/3
                 #:fill "lightsteelblue" #:stroke "navy" #:stroke-width 3)
      (circle #:id 'process #:center (vec2 2 0) #:radius 2/3
              #:fill "lemonchiffon" #:stroke "darkorange" #:stroke-width 3)
      (arrow (vec2 -13/10 0) (vec2 11/10 0) #:id 'edge
             #:stroke "purple" #:stroke-width 3 #:start-tip? #t)
      (plain-text "result" #:id 'caption #:center (vec2 2 -1)
                  #:font-size 1/4 #:color "darkorange"))
     #:id 'after))
  (scene-wait
   (scene-play
    (scene-add (make-scene) title explanation before)
    (transform-matching-visuals before after)
    #:duration 3)
   1))

(module+ main
  (run-demo "transform-matching-visuals.rkt" make-demo-scene))
