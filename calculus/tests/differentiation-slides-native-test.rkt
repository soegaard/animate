#lang racket/base
;; Requires the real TeX/native dependencies. Missing tools must fail, not skip.
(require rackunit rackunit/text-ui racket/class racket/list racket/math
         (prefix-in p: pict) (prefix-in a: animate)
         animate/slides animate/slides/render animate/slides/pict animate/slides/scene
         "../examples/differential-quotient-x-squared.rkt"
         "../examples/private/differentiation-script.rkt"
         "../examples/private/differentiation-visuals.rkt")
(define (pixels picture)
  (define b (p:pict->bitmap picture))
  (define w (send b get-width)) (define h (send b get-height))
  (define bytes (make-bytes (* 4 w h)))
  (send b get-argb-pixels 0 0 w h bytes)
  bytes)
(define tests
  (test-suite
   "Differentiation slides: real native preparation"
   (test-case "isotropic cameras and invariant point center"
     (define c (make-lens-camera 1 1 40))
     (check-equal? (/ (a:camera-scale c) (a:camera-scale main-graph-camera)) 40)
     (define-values (x y) (a:camera-world->pixel c (a:vec2 1 1)))
     (check-equal? x lens-radius) (check-equal? y lens-radius)
     (check-equal? (a:camera-world-height c) (a:camera-world-width c)))
   (test-case "complete light storyboard prepares without overflow"
     (define board (prepare-differentiate-x-squared!))
     (check-true (prepared-storyboard? board))
     (check-= (prepared-duration board) film-duration 1e-8)
     (define before (pixels (storyboard->pict board #:at 8 #:size '(960 540))))
     (define after (pixels (storyboard->pict board #:at (+ theorem-duration transition-duration 11) #:size '(960 540))))
     (check-not-equal? before after)
     (check-true (> (hash-count (for/hash ([b (in-bytes before)]) (values b #t))) 8))
     ;; Force real rendering of a complete proof panel, not just its descriptor.
     (check-not-equal? before
                      (pixels (storyboard->pict board
                          #:at (+ theorem-duration transition-duration (hash-ref shot-offsets 'dq-del-broek) 2)
                          #:size '(960 540)))))
   (test-case "the theorem has an explicit semantic match"
     (define board (prepare-differentiate-x-squared!))
     (define reports (storyboard-match-report board))
     (check-true (pair? reports))
     (check-true (regexp-match? #rx"replay" (format "~s" reports))))
   (test-case "a circular zoom changes only the lens contents"
     (define assets (prepare-example-assets! lecture-light))
     (define close (state-at-shot-end 'hold-foerste))
     (define open (hash-set close 'zoom 1))
     (define b1 (pixels (graph-picture assets open)))
     (define b2 (pixels (graph-picture assets close)))
     (check-not-equal? b1 b2)
     ;; P=(1,1) projects to (450,450) in the padded 700px canvas.
     (define changed-outside
       (for*/sum ([y (in-range graph-size)] [x (in-range graph-size)]
                  #:when (> (+ (sqr (- x 450)) (sqr (- y 450))) (sqr (+ lens-radius 4))))
         (define i (* 4 (+ x (* graph-size y))))
         (if (equal? (subbytes b1 i (+ i 4)) (subbytes b2 i (+ i 4))) 0 1)))
     (check-equal? changed-outside 0))
   (test-case "dark assets remain independent of later light preparation"
     (define dark (prepare-example-assets! lecture-dark))
     (define s (state-at-shot-end 'hold-andet))
     (define before (pixels (graph-picture dark s)))
     (prepare-example-assets! lecture-light)
     (check-equal? before (pixels (graph-picture dark s)))
     (define board (prepare-differentiate-x-squared! #:theme lecture-dark))
     (check-true (prepared-storyboard? board))
     (check-true (> (bytes-length (pixels (storyboard->pict board #:at 8 #:size '(960 540)))) 0))))
)
(module+ test (define failures (run-tests tests)) (unless (zero? failures) (exit 1)))
