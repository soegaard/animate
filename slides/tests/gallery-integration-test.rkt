#lang racket/base
(require rackunit racket/list
         (only-in pict pict?)
         "../main.rkt" "../gallery.rkt" "../pict.rkt" "../render.rkt" "../scene.rkt"
         (only-in "../../main.rkt" scene-sample scene-state->pict scene-camera-at)
         "../private/data.rkt" "../private/sample.rkt" "helpers.rkt")
(provide tests)
(define tests
  (test-suite
   "real mathematical and geometry gallery components"
   (test-case "math and geometry entries render in light and dark"
     (for* ([id (in-list '(math-derivation geometry-construction))]
            [theme (in-list (list lecture-light lecture-dark))])
       (define b (prepare-storyboard! (make-slide-gallery #:entries (list id) #:theme theme)))
       (check-true (> (prepared-duration b) 1))
       (check-true (pict? (storyboard->pict b #:at 'end #:size '(640 360))))))
   (test-case "combined geometry and algebra works in wide and portrait viewports"
     (for ([fmt (in-list (list widescreen portrait))])
       (define b (prepare-storyboard! (make-slide-gallery #:entries '(math-and-geometry) #:theme lecture-dark #:format fmt)))
       (define size (list (* 40 (slide-format-width fmt)) (* 40 (slide-format-height fmt))))
       (define endpoint (sample-storyboard b 'end))
       (for ([slot (in-list '(left right))])
         (define leaf (find-leaf endpoint (list 'math-and-geometry slot)))
         (check-= (frame-leaf-time leaf) (asset-duration (frame-leaf-asset leaf)) 1e-8))
       (define scn (storyboard->scene b #:size size))
       (define t (/ (prepared-duration b) 2))
       (define direct (pixel-bytes (storyboard->pict b #:at t #:size size)))
       (define native (pixel-bytes (scene-state->pict (scene-sample scn t) #:camera (scene-camera-at scn t))))
       (check-equal? (bytes-length direct) (bytes-length native))
       (check-true (< (/ (for/sum ([a (in-bytes direct)] [c (in-bytes native)]) (abs (- a c)))
                        (bytes-length direct)) 0.05))))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'gallery-integration-test "failed")))
