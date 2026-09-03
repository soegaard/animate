#lang racket/base

;;;
;;; SCENE-DL Serializable Rate-Function Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define (check-close actual expected)
    (check-= actual expected 1e-10))

  ;; Built-ins are transparent callable values, so the old procedure-shaped
  ;; animation API remains valid while the easing declaration is inspectable.
  (check-true (rate-function? linear))
  (check-true (procedure? linear))
  (check-equal? (linear 3/8) 3/8)
  (check-equal? (rate-function-name linear) 'linear)
  (check-equal? (rate-function-parameters linear) '())

  (define slow-middle (smooth #:inflection 10))
  (check-true (rate-function? slow-middle))
  (check-true (procedure? slow-middle))
  (check-equal? (rate-function-name slow-middle) 'smooth)
  (check-equal? (rate-function-parameters slow-middle) '(10))
  (check-equal? (rate-function->datum slow-middle) '(smooth 10))
  (check-equal? (slow-middle 0) 0)
  (check-equal? (slow-middle 1) 1)
  (check-close (slow-middle 1/2) 1/2)
  (check-true (< (slow-middle 1/4) 1/4))
  (check-true (> (slow-middle 3/4) 3/4))

  (define cubic (smoothstep))
  (check-equal? (cubic 0) 0)
  (check-equal? (cubic 1) 1)
  (check-equal? (cubic 1/2) 1/2)

  (define into (rush-into))
  (define from (rush-from))
  (check-equal? (into 0) 0)
  (check-equal? (into 1) 1)
  (check-equal? (from 0) 0)
  (check-equal? (from 1) 1)
  (check-true (< (into 1/2) 1/2))
  (check-true (> (from 1/2) 1/2))

  (define out-and-back (there-and-back))
  (check-equal? (out-and-back 0) 0)
  (check-equal? (out-and-back 1/2) 1)
  (check-equal? (out-and-back 1) 0)
  (define paused (there-and-back-with-pause #:pause-ratio 1/3))
  (check-equal? (paused 0) 0)
  (check-equal? (paused 1/3) 1)
  (check-equal? (paused 1/2) 1)
  (check-equal? (paused 1) 0)

  (check-exn exn:fail:contract? (lambda () (smooth #:inflection 0)))
  (check-exn exn:fail:contract?
             (lambda () (there-and-back-with-pause #:pause-ratio 1)))
  (check-exn exn:fail:contract?
             (lambda () (rate-function-apply slow-middle +nan.0)))

  ;; A semantic rate function works in the existing local timing interface.
  (define dot
    (circle #:id 'dot #:radius 1/3 #:center origin #:fill "royalblue"))
  (define smoothed-scene
    (scene-play
     (scene-add (make-scene) dot)
     (timed (move-to 'dot (vec2 4 0))
            #:duration 1 #:easing slow-middle)
     #:duration 1))
  (define smoothed-dot
    (scene-visual-at smoothed-scene 'dot 1/4))
  (check-close (vec2-x (visual-position smoothed-dot))
               (* 4 (slow-middle 1/4)))
  (check-not-false (scene-frame->bitmap smoothed-scene 1 #:fps 4))

  ;; The automatic section cache accepts the semantic value, but still rejects
  ;; a caller closure whose implementation cannot be represented safely.
  (define canonical-timeline
    (make-authored-timeline
     smoothed-scene
     #:sections (list (section 'motion 0 1))))
  (define canonical-key
    (automatic-section-cache-key
     canonical-timeline
     (timeline-section canonical-timeline 'motion)
     #:fps 2 #:camera #f #:renderers '() #:asset-files '()))
  (check-true (string? canonical-key))

  (define custom-timeline
    (make-authored-timeline
     (scene-play (scene-add (make-scene) dot)
                 (move-to 'dot (vec2 4 0))
                 #:duration 1
                 #:easing (lambda (progress) (* progress progress)))
     #:sections (list (section 'motion 0 1))))
  (check-false
   (automatic-section-cache-key
    custom-timeline
    (timeline-section custom-timeline 'motion)
    #:fps 2 #:camera #f #:renderers '() #:asset-files '())))
