#lang racket/base

;;;
;;; Corrective mapped-delay plan tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define near
    (circle #:id 'near #:radius 1/4 #:center origin #:fill "navy"))
  (define far
    (circle #:id 'far #:radius 1/4 #:center (vec2 2 0) #:fill "tomato"))
  (define initial (scene-add (make-scene) near far))
  (define (move-up reference)
    (define visual (target-ref-value reference))
    (move-to (target-ref-path reference)
             (vec2 (vec2-x (visual-position visual)) 1)))

  ;; Distance is evaluated from frozen local-start world positions, then the
  ;; nearest target begins first. It lowers to one explicit timed envelope, so
  ;; the first request is complete before the distant request begins.
  (define by-distance
    (scene-play
     initial
     (stagger-map (concrete-targets (list near far)) move-up
                  #:delay (distance-delay origin 1))
     #:duration 3))
  (check-equal? (visual-position (scene-visual-at by-distance 'near 1))
                (vec2 0 1))
  (check-equal? (visual-position (scene-visual-at by-distance 'far 1))
                (vec2 2 0))
  (check-equal? (visual-position (scene-visual-at by-distance 'far 3))
                (vec2 2 1))

  ;; A constant delay is a deliberate mapped-group lead-in rather than an
  ;; implicit property of source order.
  (define with-lead-in
    (scene-play
     initial
     (stagger-map (concrete-targets (list near far)) move-up
                  #:delay (constant-delay 1))
     #:duration 2))
  (check-equal? (scene-visual-at with-lead-in 'near 1/2) near)
  (check-equal? (visual-position (scene-visual-at with-lead-in 'near 2))
                (vec2 0 1))

  ;; Index delay is the compatibility plan for lag-ratio scheduling. Its
  ;; values use scheduled indexes, so changing order never mutates source
  ;; indexes held by the factory reference.
  (define seen '())
  (define reversed
    (scene-play
     initial
     (stagger-map
      (concrete-targets (list near far))
      (lambda (reference)
        (set! seen
              (append seen
                      (list (list (target-ref-source-index reference)
                                  (target-ref-scheduled-index reference)))))
        (move-up reference))
      #:order 'reverse
      #:delay (index-delay 1))
     #:duration 2))
  (check-equal? seen '((1 0) (0 1)))
  (check-equal? (visual-position (scene-visual-at reversed 'far 1))
                (vec2 2 1))
  (check-equal? (visual-position (scene-visual-at reversed 'near 1))
                (vec2 0 0))

  ;; Invalid geometry is rejected when the plan is constructed. A position
  ;; driven plan cannot silently invent coordinates for a target with no
  ;; frozen local-start 2D position.
  (check-exn exn:fail:contract? (lambda () (wave-delay origin 1 0)))
  (check-exn exn:fail:contract? (lambda () (distance-delay (vec2 +nan.0 0) 1)))
  (check-exn
   #rx"frozen local-start 2D position"
   (lambda ()
     (scene-play
      (make-scene)
      (stagger-map (concrete-targets '(missing))
                   (lambda (reference) (move-to (target-ref-path reference) origin))
                   #:delay (radial-delay origin 1))))))
