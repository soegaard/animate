#lang racket/base
(require "../experimental.rkt")

;;;
;;; SCENE-BA Derived Group Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  ;; A derived Visual may resolve to a concrete group. Its top-level identity is
  ;; stable while the group's internal child collection follows sampled state.
  (define count (parameter 'count 1))
  (define ticks
    (derived-visual
     (group '() #:id 'ticks)
     (lambda (context template)
       (define n
         (derived-context-value-ref context count))
       (group
        (for/list ([index (in-range (inexact->exact (round n)))])
          (circle #:id (string->symbol (format "tick-~a" index))
                  #:center (vec2 index 0)
                  #:radius 1/10
                  #:fill "blue"))
        #:id (visual-id template)))))
  (define scene
    (scene-play
     (scene-add (scene-set-value (make-scene) count) ticks)
     (value-to count 3)
     #:duration 2))
  (define (resolved-ticks time)
    (scene-state-resolved-ref (scene-sample scene time) 'ticks))
  (check-true (group-visual? (resolved-ticks 0)))
  (check-equal? (map visual-id (group-visual-children (resolved-ticks 0)))
                '(tick-0))
  (check-equal? (map visual-id (group-visual-children (resolved-ticks 1)))
                '(tick-0 tick-1))
  (check-equal? (map visual-id (group-visual-children (resolved-ticks 2)))
                '(tick-0 tick-1 tick-2))

  ;; Derived group children participate in the same resolved nested lookup as
  ;; ordinary group children, while the stored definition remains persistent.
  (check-true
   (derived-visual?
    (scene-state-ref (scene-current-state scene) 'ticks)))
  (check-equal?
   (visual-position
    (scene-state-resolved-ref (scene-sample scene 1) '(ticks tick-1)))
   (vec2 1 0)))
