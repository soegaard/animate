#lang racket/base

;; Explicit optional integration tests: real TeX, real geometry, and ordinary
;; native rendering. Nothing here substitutes synthetic domain correspondences.
(require (only-in rackunit test-suite test-case check-equal? check-true check-false check-exn)
         racket/list racket/file
         (only-in pict pict?)
         (only-in "../../math/private/prepare.rkt" current-math-preparation-observer)
         (only-in "../../main.rkt" scene-sample scene-camera-at scene-state->pict)
         "../main.rkt" "../pict.rkt" "../scene.rkt" "../render.rkt" "../gallery.rkt"
         "../private/data.rkt" "../private/sample.rkt" "../private/codec.rkt" "helpers.rkt")
(provide tests)
(define (all-pairs b)
  (append-map (lambda (bridge)
                (append-map match-plan-pairs (prepared-bridge-plan bridge)))
              (prepared-storyboard-value-bridges b)))
(define tests
  (test-suite
   "witnessed math and geometry transitions"
   (test-case "math snapshots share preparation and replay the existing checkpoint choreography"
     (define preparations 0)
     (parameterize ([current-math-preparation-observer (lambda (_) (set! preparations (add1 preparations)))])
       (define b (prepare-storyboard! (make-slide-gallery #:entries '(semantic-math))))
       (check-equal? preparations 1)
       (define p (car (all-pairs b)))
       (check-equal? (match-pair-mode p) 'replay)
       (check-equal? (match-pair-reason p) 'math)
       (check-true (< (match-pair-from-time p) (match-pair-to-time p)))
       (for ([t (in-list '(9 6 5 4 3 2 0 4))])
         (check-true (pict? (storyboard->pict b #:at t #:size '(640 360)))))
       (check-equal? preparations 1)))
   (test-case "math semantic plans survive the existing portable formula-artifact codec"
     (define source (make-slide-gallery #:entries '(semantic-math)))
     (define b (prepare-storyboard! source))
     (define temp (make-temporary-file "slides-semantic-math-~a" 'directory))
     (dynamic-wind void
       (lambda ()
         (define-values (payload artifacts dependencies) (prepared-storyboard->payload! b temp))
         (parameterize ([current-math-preparation-observer (lambda (_) (error 'semantic-domain-test "worker must not typeset"))])
           (define restored (payload->prepared-storyboard payload source))
           (check-equal? (storyboard-match-report b) (storyboard-match-report restored))
           (for ([t (in-list '(9 6 4 2 0))])
             (check-equal? (sample-signature (sample-storyboard b t))
                           (sample-signature (sample-storyboard restored t))))))
       (lambda () (delete-directory/files temp))))
   (test-case "geometry keeps its authored construction timeline and fixed realization"
     (define b (prepare-storyboard! (make-slide-gallery #:entries '(semantic-geometry))))
     (define p (car (all-pairs b)))
     (check-equal? (match-pair-mode p) 'replay)
     (check-equal? (match-pair-reason p) 'geometry)
     ;; The gallery starts after its first reveal so the held source state shows
     ;; A and B instead of an intentionally blank construction viewport.
     (check-true (positive? (match-pair-from-time p)))
     (define a (match-pair-replay p))
     (check-true (positive? (asset-duration a)))
     (for ([t (in-list '(11 8 5 2 0 5))])
       (check-true (pict? (storyboard->pict b #:at t #:size '(640 360))))))
   (test-case "nested math and geometry replay together in light/dark and wide/portrait"
     (for* ([theme (in-list (list lecture-light lecture-dark))]
            [fmt (in-list (list widescreen portrait))])
       (define b (prepare-storyboard! (make-slide-gallery #:entries '(semantic-math-geometry) #:theme theme #:format fmt)))
       (define replays (filter (lambda (p) (eq? (match-pair-mode p) 'replay)) (all-pairs b)))
       (check-equal? (length replays) 2)
       (check-equal? (sort (map match-pair-reason replays) symbol<?) '(geometry math))
       (define size (if (eq? fmt portrait) '(360 640) '(640 360)))
       (define scn (storyboard->scene b #:size size))
       (for ([t (in-list '(11 8 5 2 0 5))])
         (define pic (storyboard->pict b #:at t #:size size))
         (check-true (pict? pic))
         (check-true (pict? (scene-state->pict (scene-sample scn t) #:camera (scene-camera-at scn t))))
         (check-equal? (pixel-bytes pic) (pixel-bytes (storyboard->pict b #:at t #:size size))))))))
(module+ test
  (require (only-in rackunit/text-ui run-tests))
  (unless (zero? (run-tests tests)) (error 'semantic-domain-test "failed")))
