#lang racket/base

;;;
;;; Color Animation Expression Tests
;;;

(require rackunit
         "../colors.rkt"
         "../main.rkt"
         "../private/interpolation.rkt"
         "../private/visual-model.rkt")

(module+ test
  (define dot (circle #:id 'dot #:radius 1 #:fill aqua-c #:stroke red-c))
  (define animated
    (scene-play (scene-add (make-scene) dot)
                (fill-color-to dot pure-red)
                (stroke-color-to dot pure-blue)
                #:duration 1))
  (define middle (scene-visual-at animated 'dot 1/2))
  (check-true (color-expression? (visual-fill-color middle)))
  (check-true (color-expression? (visual-stroke-color middle)))
  ;; Unannotated string scene values remain labels, not colors.
  (check-false (interpolable? "red"))
  (check-exn exn:fail:contract?
             (lambda () (interpolate-value "red" "blue" 1/2))))
