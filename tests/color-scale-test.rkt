#lang racket/base

;;;
;;; Color Scale Tests
;;;

(require rackunit
         "../colors.rkt")

(module+ test
  (define scale
    (color-scale #:stops (list (paint-stop 0 aqua-c)
                               (paint-stop 1/2 red-c)
                               (paint-stop 1 yellow-b))
                 #:space 'srgb-linear
                 #:outside 'clamp))
  (check-eq? (color-scale-at scale 0) aqua-c)
  (check-eq? (color-scale-at scale 1) yellow-b)
  (check-eq? (color-scale-at scale -1) aqua-c)
  (check-eq? (color-scale-at scale 2) yellow-b)
  (check-true (color-expression? (color-scale-at scale 1/4)))

  ;; Equal offsets create a deterministic discontinuity: the final stop at
  ;; the position is selected, while a coordinate just before it remains in
  ;; the preceding segment.
  (define stepped
    (color-scale #:stops (list (paint-stop 0 black)
                               (paint-stop 1/2 pure-red)
                               (paint-stop 1/2 pure-blue)
                               (paint-stop 1 white))))
  (check-eq? (color-scale-at stepped 1/2) pure-blue)
  ;; This segment uses only fixed literals, so its independent numerical mix
  ;; is folded without changing the hard-stop behavior.
  (check-true (rgba-color? (color-scale-at stepped 49/100)))
  (define strict
    (color-scale #:stops (list (paint-stop 0 black) (paint-stop 1 white))
                 #:outside 'error))
  (check-exn exn:fail:contract? (lambda () (color-scale-at strict -1/10)))
  (check-exn exn:fail:contract?
             (lambda () (color-scale #:stops (list (paint-stop 1 white)
                                                    (paint-stop 0 black))))))
