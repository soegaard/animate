#lang racket/base

;; Short fixture for native subprocess tests; not a registered example video.
(require "../core.rkt" "../examples/private/library-example.rkt")
(construction subtitle-cli-fixture
  (given [A (point -1 0)] [B (point 1 0)])
  (timing [opening-pause 0] [read-delay 1/10] [action-duration 1/5] [step-pause 1/10])
  (step "Join A to B." [AB (segment A B)])
  (step "AB is the given segment."))
(module+ main
  (run-library-example "subtitle-cli-fixture"
   (lambda (aspect mode)
     (construction->timeline subtitle-cli-fixture #:aspect aspect
                              #:theme (if (eq? mode 'dark)
                                          default-dark-geometry-theme
                                          default-light-geometry-theme)))))
