#lang racket/base
(require rackunit racket/runtime-path
         "../main.rkt" "../pict.rkt" "../scene.rkt" "../render.rkt"
         (only-in "../../main.rkt" scene?)
         (only-in pict pict?)
         "../private/data.rkt" "../private/sample.rkt" "helpers.rkt")
(provide tests)
(define-runtime-path lesson "../examples/geometry-lesson.rkt")
(define tests
  (test-suite
   "native geometry remains an independently timed component"
   (test-case "construction prepares, samples, and lowers to Scene"
     (define p (prepare-storyboard! (dynamic-require lesson 'film)))
     (define clip (storyboard-ref p 'construction))
     (check-true (> (prepared-duration p) 5))
     (check-equal? (frame-leaf-time (find-leaf (sample-slide clip 1) '(figure))) 0)
     (check-true (pict? (slide->pict clip #:at '(result end) #:size '(640 360))))
     (check-true (scene? (storyboard->scene p #:size '(640 360)))))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'geometry-test "failed")))
