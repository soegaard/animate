#lang racket/base
(require rackunit racket/list racket/runtime-path
         "../main.rkt" "../pict.rkt" "../scene.rkt" "../render.rkt"
         "../private/data.rkt" "../private/sample.rkt" "helpers.rkt"
         (only-in pict pict?))
(provide tests)
(define-runtime-path lesson "../examples/math-lesson.rkt")
(define tests
  (test-suite
   "actual TeX and native mathematical phases"
   (test-case "named mathematical endpoints drive the embedded clock"
     (define board (prepare-storyboard! (dynamic-require lesson 'film)))
     (define clip (storyboard-ref board 'subtract-five))
     (define leaf (find-leaf (sample-slide clip 0) '(figure)))
     (define cues (asset-cues (frame-leaf-asset leaf)))
     (for ([name '(subtract-five cancel-five evaluate-rhs)])
       (check-true (hash-has-key? cues (list name 'end))))
     (check-= (frame-leaf-time (find-leaf (sample-slide clip '(subtract end)) '(figure)))
              (hash-ref cues '(subtract-five end)) 1e-8)
     (check-= (frame-leaf-time (find-leaf (sample-slide clip '(cancel end)) '(figure)))
              (hash-ref cues '(cancel-five end)) 1e-8)
     (check-true (pict? (slide->pict clip #:at '(read-result end) #:size '(640 360))))
     (check-true (pict? (storyboard->pict board #:at 'end #:size '(640 360)))))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'math-test "failed")))
