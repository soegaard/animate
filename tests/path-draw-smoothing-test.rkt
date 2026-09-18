#lang racket/base

;; Regression for continuous path geometry inheriting pixel-aligned DC modes.
(require racket/class
         (only-in rackunit test-case check-equal?)
         (only-in pict pict->bitmap)
         (only-in "../main.rkt"
                  axes axis-range function-graph make-scene scene-add scene->pict))

(define (pixels bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define result (make-bytes (* width height 4)))
  (send bitmap get-argb-pixels 0 0 width height result)
  result)

(define coordinate-model
  (axes #:id 'coordinates
        #:x-range (axis-range -3 3 1)
        #:y-range (axis-range -2 2 1)
        #:x-length 7
        #:y-length 9/2
        #:stroke "navy"))

(define curve
  (function-graph coordinate-model
                  (lambda (x) (- (/ (* x x) 4) 1))
                  #:id 'curve
                  #:sample-count 81
                  #:stroke "crimson"
                  #:stroke-width 3))

(module+ test
  (test-case "path renderer selects smoothed drawing inside its delayed Pict"
    ;; The model axes are intentionally not in this Scene. The assertion is about
    ;; the curve renderer itself, independent of axes pixel alignment.
    (define picture
      (scene->pict (scene-add (make-scene) curve) 0))
    (define expected
      (pixels (pict->bitmap picture 'smoothed)))
    (for ([mode '(aligned unsmoothed smoothed)])
      (check-equal? (pixels (pict->bitmap picture mode)) expected))))
