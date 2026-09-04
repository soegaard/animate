#lang racket/base

;;;
;;; SCENE-DX General Matching Transform Tests
;;;

(require rackunit
         racket/class
         (only-in pict pict->bitmap)
         "../main.rkt")

(module+ test
  (define camera
    (make-camera #:width 320 #:height 180 #:world-width 12 #:background "white"))
  ;; Child paths stay stable even when the source and destination use different
  ;; top-level identities and different child draw orders.
  (define before
    (group
     (list
      (circle #:id 'dot #:center (vec2 -2 0) #:radius 1/2
              #:fill "gold" #:stroke "darkorange" #:stroke-width 2)
      (rectangle #:id 'card #:center (vec2 2 0) #:width 1 #:height 1
                 #:fill "aliceblue" #:stroke "navy" #:stroke-width 2))
     #:id 'before))
  (define after
    (group
     ;; Reversed drawing order demonstrates that identity is the relative path,
     ;; not list position. The dot and card exchange their world positions.
     (list
      (rectangle #:id 'card #:center (vec2 -2 0) #:width 1 #:height 1
                 #:fill "aliceblue" #:stroke "navy" #:stroke-width 2)
      (circle #:id 'dot #:center (vec2 2 0) #:radius 1/2
              #:fill "gold" #:stroke "darkorange" #:stroke-width 2))
     #:id 'after))
  (define request (transform-matching-visuals before after))
  (check-true (transform-matching-visuals-request? request))
  (define matching-scene
    (scene-play (scene-add (make-scene #:camera camera) before)
                request
                #:duration 2))
  ;; An interior sample retains the original root only as a hidden structural
  ;; endpoint plus its temporary matching overlay; it is still fully renderable.
  (check-equal? (scene-state-count (scene-sample matching-scene 1)) 2)
  (check-not-false
   (pict->bitmap (scene->pict matching-scene 1) 'aligned))
  (check-false (scene-state-has? (scene-current-state matching-scene) 'before))
  (check-equal? (scene-visual-at matching-scene 'after 2) after)

  ;; Explicit pairs override automatic equal-path pairing. Here a red source
  ;; point is deliberately paired to the destination's other red point.
  (define source-pair
    (group
     (list
      (circle #:id 'left #:center (vec2 -2 0) #:radius 1/4 #:fill "crimson")
      (circle #:id 'right #:center (vec2 2 0) #:radius 1/4 #:fill "crimson"))
     #:id 'source-pair))
  (define destination-pair
    (group
     (list
      (circle #:id 'left #:center (vec2 -1 1) #:radius 1/4 #:fill "crimson")
      (circle #:id 'right #:center (vec2 1 1) #:radius 1/4 #:fill "crimson"))
     #:id 'destination-pair))
  (check-not-exn
   (lambda ()
     (scene-play
      (scene-add (make-scene #:camera camera) source-pair)
      (transform-matching-visuals
       source-pair destination-pair
       #:matches (list (visual-match '(left) '(right))
                       (visual-match '(right) '(left))))
      #:duration 1)))

  ;; Unmatched leaves use the documented fade fallback. An author can request
  ;; a moving cross-fade for the residual leaves without claiming a geometric
  ;; correspondence between their distinct semantic types.
  (define unmatched-source
    (group (list (circle #:id 'disc #:radius 1/2 #:fill "gold"))
           #:id 'unmatched-source))
  (define unmatched-destination
    (group (list (plain-text "new" #:id 'label #:center (vec2 1 0)
                             #:font-size 1/2 #:color "navy"))
           #:id 'unmatched-destination))
  (check-not-exn
   (lambda ()
     (scene->pict
      (scene-play
       (scene-add (make-scene #:camera camera) unmatched-source)
       (transform-matching-visuals
        unmatched-source unmatched-destination #:mismatch-mode 'fade-transform)
       #:duration 1)
      1/2)))

  ;; Explicit paths are validated against the composed leaf trees and no leaf
  ;; may be assigned more than once.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene #:camera camera) before)
      (transform-matching-visuals
       before after #:matches (list (visual-match '(missing) '(dot))))
      #:duration 1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene #:camera camera) before)
      (transform-matching-visuals
       before after
       #:matches (list (visual-match '(dot) '(dot))
                       (visual-match '(dot) '(card))))
      #:duration 1))))
