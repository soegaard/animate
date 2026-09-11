#lang racket/base

;; Keep construction programs and timelines usable in a minimal/headless Racket.
;; The native adapter is loaded only when a scene or a render is requested.
(require racket/runtime-path "../../core.rkt")
(provide make-library-theme library-example->scene run-library-example)
(define-runtime-path adapter "../../animate.rkt")
(define (make-library-theme mode)
  (define parent
    (case mode [(light) default-light-geometry-theme] [(dark) default-dark-geometry-theme]
      [else (raise-argument-error 'make-library-theme "'light or 'dark" mode)]))
  (geometry-theme #:extends parent
    (stroke [width 2.5])
    (point [radius 0.055])
    (label [font-size 0.28])
    (circle (deemphasized (stroke [dash (7 5)])))
    (marker [size 0.18] [radius 0.28] [spacing 0.08])
    (highlighted (stroke [width 4.5]))))
(define (library-example->scene timeline #:width [width 1280] #:height [height 720])
  ((dynamic-require adapter 'geometry-timeline->scene) timeline #:width width #:height height))

(define-runtime-path runner "run-example.rkt")
(define (run-library-example name factory)
  ((dynamic-require runner 'run-geometry-example) name factory))
