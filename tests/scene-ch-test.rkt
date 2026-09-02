#lang racket/base

;;;
;;; SCENE-CH Explanatory Camera Focus Tests
;;;

;; Tests focus framing around a nested subject and an optional world-space
;; context Visual. Both APIs must measure the child's fully composed transform,
;; not its local group coordinates.

(require rackunit
         "../main.rkt")


(module+ test
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center origin))
  (define detail
    (rectangle #:id 'detail
               #:center (vec2 1 0)
               #:width 2
               #:height 1
               #:fill "gold"
               #:stroke #f
               #:stroke-width 0))
  (define diagram
    (group (list detail)
           #:id 'diagram
           #:center (vec2 3 2)
           #:scale 2))
  (define caption
    (circle #:id 'caption
            #:center (vec2 9 2)
            #:radius 1
            #:fill "cornflowerblue"
            #:stroke #f
            #:stroke-width 0))
  (define initial
    (scene-add (make-scene #:camera test-camera) diagram caption))

  ;; The nested rectangle is centered at (5, 2) and spans four world units by
  ;; two. A two-to-one camera needs visible width four to fit it exactly.
  (define nested-fit
    (scene-play
     initial
     (camera-fit-scene initial #:targets (list '(diagram detail)) #:padding 0)
     #:duration 1))
  (check-equal? (camera-center (scene-current-camera nested-fit))
                (vec2 5 2))
  (check-equal? (camera-world-width (scene-current-camera nested-fit)) 4)

  ;; Focus adds only caller-selected explanatory context. The union runs from
  ;; x=3 (the nested detail) through x=10 (the caption). Its seven-unit width
  ;; is already wider than the aspect-corrected four-unit height requirement.
  (define focused
    (scene-play
     initial
     (camera-focus initial
                   '(diagram detail)
                   #:context (list 'caption)
                   #:padding 0)
     #:duration 1))
  (check-equal? (camera-center (scene-current-camera focused))
                (vec2 13/2 2))
  (check-equal? (camera-world-width (scene-current-camera focused)) 7)

  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-focus initial '(diagram missing))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-focus initial 'caption #:context (list 42))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-fit-scene initial #:targets (list '(diagram missing))))))
