#lang racket/base
(require "../experimental.rkt")

;;;
;;; SCENE-BN Dynamically Derived Plot Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define plot-axes
    (axes #:id 'axes
          #:x-range (axis-range -1 1 1)
          #:y-range (axis-range -4 4 1)
          #:x-length 2
          #:y-length 8
          #:x-tip? #f
          #:y-tip? #f))
  (define amplitude
    (parameter 'amplitude 1))
  ;; The field reads its parameter from the context supplied for each sampled
  ;; scene state. Its persistent template is never animated or mutated.
  (define dynamic-line
    (derived-function-graph
     plot-axes
     (lambda (context x)
       (* (derived-context-value-ref context amplitude) x))
     #:id 'dynamic-line
     #:sample-count 3
     #:stroke "purple"))
  (check-true (derived-visual? dynamic-line))
  (define animated
    (scene-play
     (scene-add
      (scene-set-value (make-scene) amplitude)
      dynamic-line)
     (value-to amplitude 3)
     #:duration 2))
  (define (graph-points time)
    (path-geometry-subpath-points
     (path-visual-path
      (scene-visual-at animated 'dynamic-line time))))
  (check-equal?
   (graph-points 0)
   (list (list (vec2 -1 -1) (vec2 0 0) (vec2 1 1))))
  (check-equal?
   (graph-points 1)
   (list (list (vec2 -1 -2) (vec2 0 0) (vec2 1 2))))
  (check-equal?
   (graph-points 2)
   (list (list (vec2 -1 -3) (vec2 0 0) (vec2 1 3))))
  ;; The ordinary function-graph validation remains in force at construction.
  (check-exn exn:fail:contract?
             (lambda ()
               (derived-function-graph plot-axes (lambda (_context _x) 0)
                                       #:id 'bad #:sample-count 1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (derived-function-graph plot-axes (lambda (_context) 0)
                                       #:id 'bad))))
