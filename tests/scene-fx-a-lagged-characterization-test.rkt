#lang racket/base

;;;
;;; FX-A Lagged-Start Characterization Tests
;;;

;; These lock down the composition behavior that stagger-map must reuse rather
;; than reimplement.  In particular, direct child spans are scaled by the
;; existing scheduler and frames may be sampled in any order.

(require rackunit
         "../main.rkt")

(module+ test
  (define left
    (circle #:id 'left #:radius 1/2 #:center (vec2 0 1) #:fill "royalblue"))
  (define right
    (circle #:id 'right #:radius 1/2 #:center (vec2 0 -1) #:fill "seagreen"))

  (check-exn exn:fail:contract?
             (lambda () (lagged-start #:lag-ratio 1/2)))

  ;; The convenient list form is structurally the same ordinary composition as
  ;; separate direct children.
  (define direct
    (lagged-start (move-to left (vec2 4 1))
                  (timed (move-to right (vec2 4 -1)) #:duration 2)
                  #:lag-ratio 1/2))
  (define listed
    (lagged-start (list (move-to left (vec2 4 1))
                        (timed (move-to right (vec2 4 -1)) #:duration 2))
                  #:lag-ratio 1/2))
  (check-equal? listed direct)

  ;; Unequal intrinsic direct spans retain the previous-child lag rule, and
  ;; exact endpoint values are held after arbitrary-order sampling.
  (define scene
    (scene-play
     (scene-add (make-scene) left right)
     direct
     #:duration 4))
  (define ascending
    (for/hash ([time (in-list '(0 1 2 3 4))])
      (values time (scene-sample scene time))))
  (for ([time (in-list '(3 0 4 1 2))])
    (check-equal? (scene-sample scene time)
                  (hash-ref ascending time)))
  (check-equal?
   (visual-position (scene-visual-at scene 'left 4))
   (vec2 4 1))
  (check-equal?
   (visual-position (scene-visual-at scene 'right 4))
   (vec2 4 -1)))
