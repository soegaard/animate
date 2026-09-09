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

  ;; One-at-a-time presentation has its own explicit crossfade schedule. With
  ;; overlap zero, an exit ends exactly as the following entry begins.
  (define one-at-a-time
    (scene-play
     (make-scene)
     (crossfade-subsets targets enter #:overlap 0)
     #:duration 5))
  (check-true (scene-state-has? (scene-sample one-at-a-time 0) 'first))
  (check-true (scene-state-has? (scene-sample one-at-a-time 1) 'first))
  (check-false (scene-state-has? (scene-sample one-at-a-time 1) 'second))
  (check-false (scene-state-has? (scene-sample one-at-a-time 2) 'first))
  (check-true (scene-state-has? (scene-sample one-at-a-time 2) 'second))
  (check-false (scene-state-has? (scene-sample one-at-a-time 2) 'third))
  (check-false (scene-state-has? (scene-sample one-at-a-time 4) 'second))
  (check-true (scene-state-has? (scene-sample one-at-a-time 4) 'third))
  (check-equal? (scene-visual-at one-at-a-time 'third 5) third)

  ;; Reversal also determines the retained final target in one-at-a-time mode.
  (define reverse-one-at-a-time
    (scene-play
     (make-scene)
     (crossfade-subsets targets enter #:order 'reverse #:overlap 0)
     #:duration 5))
  (check-equal? (scene-visual-at reverse-one-at-a-time 'first 5) first)
  (check-false (scene-state-has? (scene-sample reverse-one-at-a-time 5) 'second))
  (check-false (scene-state-has? (scene-sample reverse-one-at-a-time 5) 'third))

  ;; Positive overlap is an intentional handoff, not an accidental lagged
  ;; component collision. Both adjacent targets are present only in the
  ;; documented overlap interval.
  (define overlapping
    (scene-play (make-scene)
                (crossfade-subsets (list first second) enter #:overlap 1/2)
                #:duration 5/2))
  (check-true (scene-state-has? (scene-sample overlapping 7/4) 'first))
  (check-true (scene-state-has? (scene-sample overlapping 7/4) 'second))
  (check-false (scene-state-has? (scene-sample overlapping 2) 'first))
  (check-equal? (scene-visual-at overlapping 'second 5/2) second)

  (define remove-final
    (scene-play (make-scene)
                (crossfade-subsets (list first second) enter
                                    #:remove-final? #t)
                #:duration 7/2))
  (check-false (scene-state-has? (scene-sample remove-final 7/2) 'first))
  (check-false (scene-state-has? (scene-sample remove-final 7/2) 'second))

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
             (lambda () (reveal-subsets targets enter #:cumulative? #f)))
  (check-exn #rx"reveal-subsets.*source-index: 1"
             (lambda ()
               (reveal-subsets
                targets
                (lambda (_target source-index)
                  (if (= source-index 1)
                      (error 'entry "deliberate failure")
                      (enter first)))))))
