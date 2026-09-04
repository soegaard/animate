#lang racket/base

;;;
;;; SCENE-EC: Semantic vector paints
;;;

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (caption id content center)
  (plain-text content #:id id #:center center
              #:font-size 1/4 #:font-family 'swiss #:font-weight 'bold
              #:color "darkslategray"))

(define (make-demo-scene)
  (define warm-sweep
    (linear-gradient
     (vec2 -2 -1) (vec2 2 1)
     (list (paint-stop 0 "tomato")
           (paint-stop 1 "gold"))))
  (define cool-sweep
    (linear-gradient
     (vec2 -2 1) (vec2 2 -1)
     (list (paint-stop 0 "deepskyblue")
           (paint-stop 1 "mediumpurple"))))
  (define glow
    (radial-gradient
     origin 3/2
     (list (paint-stop 0 "white")
           (paint-stop 1 "mediumslateblue"))))
  (define checker
    (checker-pattern "aliceblue" "lightsteelblue" #:cell-size 1/3))

  (define title
    (plain-text "SCENE-EC: semantic vector paints"
                #:id 'title #:center (vec2 0 18/5)
                #:font-size 2/5 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Paint descriptions stay semantic while gradients move and change."
                #:id 'explanation #:center (vec2 0 3)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))

  ;; The left rectangle is a native rectangle Visual, not a pre-rendered image.
  ;; Its gradient endpoints are in its local coordinate system.
  (define sweep
    (rectangle #:id 'sweep #:center (vec2 -3 1/4)
               #:width 3 #:height 2 #:fill warm-sweep
               #:stroke "midnightblue" #:stroke-width 3))
  (define sweep-label
    (caption 'sweep-label "linear-gradient" (vec2 -3 -17/10)))

  ;; Vector clipping from SCENE-DY operates after the gradient brush is set.
  ;; Moving the clipped wrapper moves the content and its circular mask together.
  (define clipped-glow
    (clip-to
     (rectangle #:id 'glow-content #:width 3 #:height 3
                #:fill glow #:stroke #f)
     (path-visual-path
      (ellipse #:id 'glow-mask #:width 5/2 #:height 5/2 #:fill #f))
     #:id 'glow))
  (define glow-outline
    (ellipse #:id 'glow-outline #:width 5/2 #:height 5/2
             #:fill #f #:stroke "midnightblue" #:stroke-width 3))
  (define glow-label
    (caption 'glow-label "clipped radial-gradient" (vec2 0 -17/10)))

  ;; A path-backed star demonstrates the same pattern brush on non-primitive
  ;; geometry. It also makes the repeating cells easy to see.
  (define patterned-star
    (star #:id 'patterned-star #:center (vec2 16/5 1/4)
          #:points 6 #:outer-radius 11/10 #:inner-radius 1/2
          #:fill checker #:stroke "steelblue" #:stroke-width 3))
  (define star-label
    (caption 'star-label "checker-pattern" (vec2 16/5 -17/10)))

  (define initial
    (scene-add (make-scene)
               title explanation
               sweep clipped-glow glow-outline patterned-star
               sweep-label glow-label star-label))
  (define animated
    (scene-play
     (scene-wait initial 1)
     (animation-group
      (fill-color-to 'sweep cool-sweep)
      (move-to 'glow (vec2 1/2 1/2))
      (move-to 'glow-outline (vec2 1/2 1/2))
      (move-to 'glow-label (vec2 1/2 -17/10)))
     #:duration 3
     #:easing (smooth)))
  (scene-wait animated 2))

(module+ main
  (run-demo "semantic-paints.rkt" make-demo-scene))
