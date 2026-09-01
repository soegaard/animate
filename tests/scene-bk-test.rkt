#lang racket/base

;;;
;;; SCENE-BK Discontinuity-Aware Function Graph Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define axes-value
    (axes #:id 'axes
          #:x-range (axis-range -1 1 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 2
          #:y-length 2
          #:x-tip? #f
          #:y-tip? #f))

  ;; Adjacent finite samples beyond opposite visible y boundaries are a hidden
  ;; vertical asymptote, not a clipped line through the plot window.
  (define discontinuous
    (sample-function-path
     axes-value
     (lambda (x) (/ 1 x))
     #:x-min -1/2
     #:x-max 1/2
     #:sample-count 2
     #:detect-discontinuities? #t))
  (check-equal? (path-geometry-subpath-points discontinuous) '())

  ;; Callers can deliberately retain the previous clipping behavior, and the
  ;; existing explicit max-jump option still adds independent break control.
  (define connected
    (sample-function-path
     axes-value
     (lambda (x) (/ 1 x))
     #:x-min -1/2
     #:x-max 1/2
     #:sample-count 2
     #:detect-discontinuities? #f))
  (check-equal?
   (path-geometry-subpath-points connected)
   (list (list (vec2 -1/4 -1) (vec2 1/4 1))))
  (check-exn exn:fail:contract?
             (lambda ()
               (sample-function-path axes-value values
                                     #:detect-discontinuities? 'yes))))
