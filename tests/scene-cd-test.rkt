#lang racket/base

;;;
;;; SCENE-CD Live Attachment Tests
;;;

;; Tests world-space following through a transformed nested group and live
;; frame-space callout leaders addressed by the same explicit Visual path.


;;;
;;; Imports
;;;

(require rackunit
         racket/math
         "../main.rkt")


(define (check-vec2~= actual expected [epsilon 1e-10])
  (check-= (vec2-x actual) (vec2-x expected) epsilon)
  (check-= (vec2-y actual) (vec2-y expected) epsilon))


(module+ test
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20))

  ;; The child is local to a scaled, rotated, and translated parent.
  (define satellite
    (circle #:id 'satellite
            #:center (vec2 1 0)
            #:radius 1/4
            #:fill "gold"))
  (define system
    (group (list satellite)
           #:id 'system
           #:center (vec2 2 -1)
           #:rotation (/ pi 2)
           #:scale 2))
  (define badge
    (follow-anchor
     (circle #:id 'badge
             #:center origin
             #:radius 1/5
             #:fill "crimson")
     '(system satellite)
     #:offset (vec2 0 1)))

  (define initial
    (scene-add (make-scene #:camera test-camera) system badge))

  ;; satellite is at (2, 1) after its parent transform; the attached badge is
  ;; one world unit above it rather than one unit above the child's local point.
  (check-vec2~=
   (visual-position (scene-visual-at initial 'badge 0))
   (vec2 2 2))

  ;; The relationship is recomputed from the sampled parent transform.
  (define moved
    (scene-play initial
                (move-to system (vec2 4 -1))
                #:duration 1))
  (check-vec2~=
   (visual-position (scene-visual-at moved 'badge 1))
   (vec2 4 2))

  ;; Callouts accept the same nested address and preserve it instead of
  ;; truncating it to the top-level group identity.
  (define note
    (callout
     (rectangle #:id 'note
                #:center (vec2 6 3)
                #:width 3
                #:height 1
                #:fill "white"
                #:stroke "navy"
                #:stroke-width 2)
     '(system satellite)
     #:camera test-camera
     #:connector-stroke "navy"
     #:connector-width 2))
  (check-equal? (callout-visual-target note) '(system satellite))
  (check-not-exn
   (lambda ()
     (scene-state->pict
      (scene-current-state
       (scene-add initial note))
      #:camera test-camera)))

  (define overlay
    (fixed-in-frame
     (plain-text "fixed" #:id 'fixed)
     #:camera test-camera))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (follow-anchor overlay '(system satellite))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (follow-anchor satellite '(system satellite) #:offset 'not-a-point)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-state->pict
      (scene-current-state
       (scene-add
        initial
        (callout (rectangle #:id 'bad-note #:width 1 #:height 1)
                 '(system not-present)
                 #:camera test-camera)))
      #:camera test-camera))))
