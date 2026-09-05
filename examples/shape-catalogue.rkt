#lang racket/base

;;;
;;; SCENE-DJ: Mathematical Shape Catalogue
;;;

;; All catalogue shapes are ordinary path or group Visuals. They therefore use
;; the same renderer, addressing, styles, and animation requests as the older
;; circle/rectangle/arrow primitives.

(require (only-in racket/math pi)
         animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (caption id text center)
  (plain-text text #:id id #:center center #:font-size 3/20
              #:font-family 'swiss #:color "darkslategray"))

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-DJ: mathematical shape catalogue"
                #:id 'title #:center (vec2 0 18/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define note
    (plain-text "path-backed curves, ordinary arrows, and addressable annotation groups"
                #:id 'note #:center (vec2 0 31/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define catalogue
    (group
     (list
      (ellipse #:id 'ellipse #:center (vec2 -24/5 7/5)
               #:width 8/5 #:height 4/5 #:fill "lightsteelblue" #:stroke "navy")
      (caption 'ellipse-label "ellipse" (vec2 -24/5 3/5))
      (annulus #:id 'annulus #:center (vec2 -12/5 7/5)
               #:inner-radius 1/3 #:outer-radius 7/10
               #:fill "palegreen" #:stroke "forestgreen")
      (caption 'annulus-label "annulus" (vec2 -12/5 3/5))
      (sector #:id 'sector #:center (vec2 0 7/5) #:radius 7/10
              #:start-angle 0 #:angle (* 5/4 pi)
              #:fill "moccasin" #:stroke "darkgoldenrod")
      (caption 'sector-label "sector" (vec2 0 3/5))
      (regular-polygon #:id 'polygon #:center (vec2 12/5 7/5)
                       #:sides 6 #:radius 7/10
                       #:fill "thistle" #:stroke "darkviolet")
      (caption 'polygon-label "regular polygon" (vec2 12/5 3/5))
      (star #:id 'star #:center (vec2 24/5 7/5)
            #:points 5 #:outer-radius 4/5 #:inner-radius 7/20
            #:fill "gold" #:stroke "saddlebrown")
      (caption 'star-label "star" (vec2 24/5 3/5))

      (rounded-rectangle #:id 'rounded #:center (vec2 -24/5 -9/5)
                         #:width 8/5 #:height 4/5 #:corner-radius 1/4
                         #:fill "aliceblue" #:stroke "steelblue")
      (caption 'rounded-label "rounded rectangle" (vec2 -24/5 -13/5))
      (arc-between-points (vec2 -31/10 -9/5) (vec2 -17/10 -9/5)
                          #:id 'arc-between #:angle pi
                          #:stroke "crimson" #:stroke-width 3)
      (caption 'arc-between-label "arc between points" (vec2 -12/5 -13/5))
      (curved-arrow (vec2 -1 -9/5) (vec2 1 -9/5)
                    #:id 'curved-arrow #:angle (- (/ pi 2))
                    #:stroke "teal" #:stroke-width 3)
      (caption 'curved-arrow-label "curved arrow" (vec2 0 -13/5))
      (double-arrow (vec2 17/10 -9/5) (vec2 31/10 -9/5)
                    #:id 'double-arrow #:stroke "firebrick" #:stroke-width 3)
      (caption 'double-arrow-label "double arrow" (vec2 12/5 -13/5))
      (labeled-point "P" #:id 'labeled-point #:center (vec2 24/5 -9/5)
                     #:radius 3/20 #:label-offset (vec2 1/4 1/4)
                     #:fill "crimson" #:stroke "firebrick" #:color "firebrick")
      (caption 'labeled-point-label "labeled point" (vec2 24/5 -13/5)))
     #:id 'catalogue))
  (define initial
    (scene-wait (scene-add (make-scene) title note) 1))
  (define revealed
    (scene-play initial (fade-in catalogue) #:duration 3))
  (scene-wait revealed 1))

(module+ main
  (run-demo "shape-catalogue.rkt" make-demo-scene))
