#lang racket/base

;;;
;;; SCENE-CE Nested Attention Tests
;;;

;; Tests that renderer-measured temporary attention may address a nested child
;; and that its independent outline is placed in the child's composed world
;; coordinate system.


;;;
;;; Imports
;;;

(require rackunit
         racket/list
         racket/math
         "../main.rkt")


(module+ test
  (define seed
    (circle #:id 'seed
            #:center (vec2 1 0)
            #:radius 1/4
            #:fill "gold"))
  (define branch
    (group (list seed)
           #:id 'branch
           #:center (vec2 1 0)
           #:rotation (/ pi 2)
           #:scale 2))
  (define diagram
    (group (list branch)
           #:id 'diagram
           #:center (vec2 -3 0)
           #:rotation (/ pi 2)
           #:scale 2))
  (define target-path '(diagram branch seed))
  ;; The nested seed is at (-7, 2) after both enclosing transforms.
  (define expected-center (vec2 -7 2))

  (define circumscribed
    (scene-play
     (scene-add (make-scene) diagram)
     (circumscribe target-path #:padding 1/5 #:color "crimson")
     #:duration 1))
  (define circumscribed-middle
    (scene-sample circumscribed 1/2))
  (define circumscribe-outline
    (last (scene-state-visuals-in-drawing-order circumscribed-middle)))
  (check-true (scene-state-has? circumscribed-middle target-path))
  (check-= (vec2-x (visual-position circumscribe-outline))
           (vec2-x expected-center)
           1e-10)
  (check-= (vec2-y (visual-position circumscribe-outline))
           (vec2-y expected-center)
           1e-10)
  (check-equal? (scene-state-count circumscribed-middle) 2)
  (check-equal? (scene-state-count (scene-current-state circumscribed)) 1)

  (define indicated
    (scene-play
     (scene-add (make-scene) diagram)
     (indicate target-path #:padding 1/5 #:color "seagreen")
     #:duration 1))
  (define indicated-middle
    (scene-sample indicated 1/2))
  (define indicate-outline
    (last (scene-state-visuals-in-drawing-order indicated-middle)))
  (check-true (scene-state-has? indicated-middle target-path))
  (check-= (vec2-x (visual-position indicate-outline))
           (vec2-x expected-center)
           1e-10)
  (check-= (vec2-y (visual-position indicate-outline))
           (vec2-y expected-center)
           1e-10)
  (check-equal? (scene-state-count indicated-middle) 2)
  (check-equal? (scene-state-count (scene-current-state indicated)) 1)

  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) diagram)
      (circumscribe 'not-a-visual)
      #:duration 1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) diagram)
      (indicate '(diagram branch missing))
      #:duration 1))))
