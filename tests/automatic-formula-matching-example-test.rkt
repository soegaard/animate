#lang racket/base

(require rackunit
         "../main.rkt"
         "../examples/automatic-formula-matching.rkt")

(define (part-names scene time)
  (formula-assembly-visual-part-names
   (scene-visual-at scene 'equation time)))

(module+ test
  (define demo (make-demo-scene))
  ;; Each one-second hold is followed by a two-second automatic transition.
  (check-equal? (part-names demo 0)
                '(x plus-a two-x plus-b one))
  (check-equal? (part-names demo 3)
                '(one-renamed plus-left two-x-renamed plus-right x-renamed))
  (check-equal? (part-names demo 6)
                '(f equals one-named plus-named-left two-x-named
                    plus-named-right x-named))
  (check-equal? (part-names demo 9)
                '(g equals-renamed x-restored plus-restored-left two-x-restored
                    plus-restored-right one-restored)))
