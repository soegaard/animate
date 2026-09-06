#lang racket/base

(require rackunit
         "../3d.rkt"
         "../3d/render.rkt")

(module+ test
  (define default (stroke3d))
  (check-equal? (stroke3d-width-mode default) 'screen)
  (check-equal? (stroke3d-cap default) 'round)
  (check-equal? (stroke3d-join default) 'round)
  (check-equal? (stroke3d-dash-space default) 'screen)
  (check-equal? (stroke3d-depth-mode default) 'test)
  (check-true (tube-style3d? (tube-style3d)))
  (check-true
   (stroke3d? (curve3d-style
               (polyline3d (list origin3 (vec3 1 0 0)) #:id 'line))))
  (define compiled
    (compile-view3d
     (view3d (list (line3d origin3 (vec3 1 0 0) #:id 'line)) #:id 'world)))
  (define descriptor (vector-ref (compiled-view3d-strokes compiled) 0))
  (check-equal? (compiled-stroke3d-source-kind descriptor) 'curve)
  (check-true (immutable? (compiled-stroke3d-source-metadata descriptor)))
  ;; Stage O intentionally removed the old ambiguous physical-radius keyword.
  (check-exn exn:fail:contract?
             (lambda ()
               (polyline3d (list origin3 (vec3 1 0 0)) #:id 'old #:radius 1/8)))
  (check-exn exn:fail:contract?
             (lambda () (stroke3d #:dash '(2 0))))
  (check-exn exn:fail:contract?
             (lambda () (stroke3d #:dash '(2 3 4)))))
