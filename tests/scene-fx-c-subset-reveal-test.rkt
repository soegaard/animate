#lang racket/base

;;;
;;; FX-C0 Eager Subset Reveal Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define first
    (circle #:id 'first #:radius 1/3 #:center (vec2 -2 0) #:fill "royalblue"))
  (define second
    (circle #:id 'second #:radius 1/3 #:center origin #:fill "seagreen"))
  (define third
    (circle #:id 'third #:radius 1/3 #:center (vec2 2 0) #:fill "tomato"))
  (define targets (list first second third))

  ;; The entry factory is evaluated only once per source target, in source
  ;; order. Reverse affects only the scheduling order.
  (define calls (box '()))
  (define reverse-cumulative
    (reveal-subsets
     targets
     (lambda (target source-index)
       (set-box! calls (append (unbox calls) (list (list (visual-id target) source-index))))
       (enter target))
     #:order 'reverse
     #:lag-ratio 1))
  (check-equal? (unbox calls) '((first 0) (second 1) (third 2)))
  (check-true (lagged-start-animation-request? reverse-cumulative))
  (define reverse-scene
    (scene-play (make-scene) reverse-cumulative #:duration 3))
  (check-true (scene-state-has? (scene-sample reverse-scene 0) 'third))
  (check-false (scene-state-has? (scene-sample reverse-scene 0) 'first))
  (check-true (scene-state-has? (scene-sample reverse-scene 1) 'second))
  (check-equal? (scene-visual-at reverse-scene 'first 3) first)
  (check-equal? (scene-visual-at reverse-scene 'second 3) second)
  (check-equal? (scene-visual-at reverse-scene 'third 3) third)

  ;; In one-at-a-time mode each scheduled entry after the first starts a fade
  ;; of the previous scheduled target. The final scheduled target alone
  ;; remains, with exact structural cleanup at the common leaf boundaries.
  (define one-at-a-time
    (scene-play
     (make-scene)
     (reveal-subsets targets enter #:lag-ratio 1 #:cumulative? #f)
     #:duration 3))
  (check-true (scene-state-has? (scene-sample one-at-a-time 0) 'first))
  (check-true (scene-state-has? (scene-sample one-at-a-time 1) 'first))
  (check-true (scene-state-has? (scene-sample one-at-a-time 1) 'second))
  (check-false (scene-state-has? (scene-sample one-at-a-time 2) 'first))
  (check-true (scene-state-has? (scene-sample one-at-a-time 2) 'second))
  (check-true (scene-state-has? (scene-sample one-at-a-time 2) 'third))
  (check-false (scene-state-has? (scene-sample one-at-a-time 3) 'first))
  (check-false (scene-state-has? (scene-sample one-at-a-time 3) 'second))
  (check-equal? (scene-visual-at one-at-a-time 'third 3) third)

  ;; Reversal also determines the retained final target in one-at-a-time mode.
  (define reverse-one-at-a-time
    (scene-play
     (make-scene)
     (reveal-subsets targets enter #:order 'reverse #:lag-ratio 1 #:cumulative? #f)
     #:duration 3))
  (check-equal? (scene-visual-at reverse-one-at-a-time 'first 3) first)
  (check-false (scene-state-has? (scene-sample reverse-one-at-a-time 3) 'second))
  (check-false (scene-state-has? (scene-sample reverse-one-at-a-time 3) 'third))

  ;; The supplied constructor remains general: existing fade introductions
  ;; work, and every eager-construction diagnostic names reveal-subsets.
  (define faded
    (scene-play
     (make-scene)
     (reveal-subsets (vector first second) fade-in #:lag-ratio 1/2)
     #:duration 3/2))
  (check-equal? (scene-visual-at faded 'first 3/2) first)
  (check-equal? (scene-visual-at faded 'second 3/2) second)
  (check-exn exn:fail:contract?
             (lambda () (reveal-subsets '() enter)))
  (check-exn exn:fail:contract?
             (lambda () (reveal-subsets targets enter #:cumulative? 'yes)))
  (check-exn #rx"reveal-subsets.*source-index: 1"
             (lambda ()
               (reveal-subsets
                targets
                (lambda (_target source-index)
                  (if (= source-index 1)
                      (error 'entry "deliberate failure")
                      (enter first)))))))
