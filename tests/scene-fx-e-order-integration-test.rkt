#lang racket/base

;;;
;;; FX-E1 Order-plan Integration Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define first (circle #:id 'first #:radius 1/4 #:center (vec2 -2 0)))
  (define second (circle #:id 'second #:radius 1/4 #:center origin))
  (define third (circle #:id 'third #:radius 1/4 #:center (vec2 2 0)))
  (define targets (list first second third))

  ;; Factories retain source evaluation/index rules even when an immutable
  ;; permutation decides their later schedule.
  (define calls (box '()))
  (define planned
    (stagger-map
     targets
     (lambda (target source-index)
       (set-box! calls (append (unbox calls) (list (list (visual-id target) source-index))))
       (move-to target (vec2 (+ 10 source-index) 0)))
     #:lag-ratio 1
     #:order (permutation-order #(2 0 1))))
  (check-equal? (unbox calls) '((first 0) (second 1) (third 2)))
  (define scene
    (scene-play (apply scene-add (make-scene) targets) planned #:duration 3))
  ;; The third target is scheduled first, then first, then second.
  (check-equal? (visual-position (scene-visual-at scene 'third 1)) (vec2 12 0))
  (check-equal? (visual-position (scene-visual-at scene 'first 2)) (vec2 10 0))
  (check-equal? (visual-position (scene-visual-at scene 'second 3)) (vec2 11 0))

  ;; One-at-a-time subset progressions share precisely the same immutable plan;
  ;; final retention follows scheduled order, not the original collection order.
  (define revealed
    (scene-play
     (make-scene)
     (reveal-subsets targets enter
                     #:order (permutation-order #(1 2 0))
                     #:lag-ratio 1 #:cumulative? #f)
     #:duration 3))
  (check-equal? (scene-visual-at revealed 'first 3) first)
  (check-false (scene-state-has? (scene-sample revealed 3) 'second))
  (check-false (scene-state-has? (scene-sample revealed 3) 'third))

  (check-exn exn:fail:contract?
             (lambda ()
               (stagger-map targets move-to #:order (permutation-order #(0 1))))))
