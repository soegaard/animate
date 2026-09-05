#lang racket/base

;;;
;;; SCENE-DT: Probability and Statistical Diagrams
;;;

(require animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (caption id text at)
  (plain-text text #:id id #:center at #:font-size 1/5 #:font-family 'swiss
              #:font-weight 'bold #:color "midnightblue"))

(define (make-demo-scene)
  (define title (plain-text "SCENE-DT: probability and statistical diagrams"
                            #:id 'title #:center (vec2 0 17/5)
                            #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define explanation (plain-text "Every constituent is an ordinary named Visual for animation."
                                  #:id 'explanation #:center (vec2 0 3)
                                  #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define frequency (bar-chart '(3 7 5 4) #:id 'frequency #:labels '("A" "B" "C" "D")
                               #:center (vec2 -23/10 11/10) #:width 5/2 #:height 11/10))
  (define stacked (stacked-bar-chart '((2 3) (3 2) (1 4)) #:id 'stacked
                                       #:center (vec2 23/10 11/10) #:width 5/2 #:height 11/10))
  (define outcomes (sample-space '((1/4 1/4) (1/4 1/4)) #:id 'outcomes
                                  #:center (vec2 -23/10 -11/10) #:width 2 #:height 1))
  (define tree
    (probability-tree
     (list (probability-branch 'heads "H" 1/2
                               (list (probability-branch 'hh "H" 1/2 '())
                                     (probability-branch 'ht "T" 1/2 '())))
           (probability-branch 'tails "T" 1/2 '()))
     #:id 'tree #:center (vec2 0 -3/5) #:width 2 #:level-gap 3/5 #:node-radius 1/8))
  (define spread (box-plot '(1 2 3 4 5 8 10) #:id 'spread
                           #:center (vec2 12/5 -3/4) #:width 2 #:height 1/2))
  (define uncertainty
    (error-bars (list (error-bar-point 9/5 -19/10 1/4)
                      (error-bar-point 12/5 -17/10 2/5)
                      (error-bar-point 3 -2 1/5))
                #:id 'uncertainty))
  (define initial
    (scene-wait
     (scene-add (make-scene) title explanation frequency stacked outcomes tree spread uncertainty
                (caption 'frequency-label "bar chart" (vec2 -23/10 12/5))
                (caption 'stacked-label "stacked bars" (vec2 23/10 12/5))
                (caption 'outcomes-label "sample space" (vec2 -23/10 -19/10))
                (caption 'tree-label "probability tree" (vec2 0 -13/5))
                (caption 'spread-label "box plot + error bars" (vec2 12/5 -13/5)))
     1))
  (define highlighted
    (scene-play initial
                (flash (bar-chart-bar-path 'frequency 2) #:color "gold")
                (focus-on (stacked-bar-segment-path 'stacked 3 2) #:color "crimson")
                #:duration 2))
  (scene-wait
   (scene-play highlighted
               (wiggle (probability-tree-node-path 'tree 'heads) #:angle 1/12)
               (show-passing-flash '(spread median) #:color "darkred")
               #:duration 2)
   1))

(module+ main
  (run-demo "probability-and-statistics.rkt" make-demo-scene))
