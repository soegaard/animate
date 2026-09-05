#lang racket/base

;;;
;;; SCENE-DV: Layout Finishing
;;;

(require animate "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define title (plain-text "SCENE-DV: deterministic layout finishing" #:id 'title #:center (vec2 0 17/5)
                            #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define explanation (plain-text "Baselines, frame fitting, collision avoidance, and distribution use measured boxes."
                                  #:id 'explanation #:center (vec2 0 3) #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define labels
    (align-baselines
     (list (plain-text "x" #:id 'x #:center (vec2 -5/2 3/2) #:font-size 3/5 #:vertical-alignment 'baseline #:color "navy")
           (plain-text " + " #:id 'plus #:center (vec2 -3/2 1) #:font-size 2/5 #:vertical-alignment 'baseline #:color "navy")
           (plain-text "y²" #:id 'y #:center (vec2 -1/2 2) #:font-size 3/4 #:vertical-alignment 'baseline #:color "navy"))))
  (define cards
    (avoid-overlap
     (list (rounded-rectangle #:id 'card-1 #:center origin #:width 7/5 #:height 4/5 #:corner-radius 1/5 #:fill "aliceblue" #:stroke "steelblue")
           (rounded-rectangle #:id 'card-2 #:center origin #:width 7/5 #:height 4/5 #:corner-radius 1/5 #:fill "lavender" #:stroke "mediumpurple")
           (rounded-rectangle #:id 'card-3 #:center origin #:width 7/5 #:height 4/5 #:corner-radius 1/5 #:fill "honeydew" #:stroke "seagreen"))
     #:gap 1/4))
  (define dots
    (distribute-within
     (list (circle #:id 'dot-1 #:center (vec2 0 -1) #:radius 1/7 #:fill "coral")
           (circle #:id 'dot-2 #:center (vec2 0 -1) #:radius 1/7 #:fill "coral")
           (circle #:id 'dot-3 #:center (vec2 0 -1) #:radius 1/7 #:fill "coral")
           (circle #:id 'dot-4 #:center (vec2 0 -1) #:radius 1/7 #:fill "coral")) -5/2 5/2))
  (define offscreen (keep-inside-frame (circle #:id 'fitted #:center (vec2 9 -2) #:radius 2/5 #:fill "gold" #:stroke "goldenrod") #:margin 1/4))
  (define initial (scene-wait (apply scene-add (append (list (make-scene) title explanation offscreen) labels cards dots)) 1))
  (scene-wait (scene-play initial (wiggle 'card-2 #:angle 1/16) (flash 'fitted #:color "gold") #:duration 2) 1))

(module+ main (run-demo "layout-finishing.rkt" make-demo-scene))
