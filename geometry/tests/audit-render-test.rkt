#lang racket/base

;; These tests need the real containing Animate checkout and pict/draw. They
;; are deliberately separate from the base-only checks used in the build.
(require rackunit racket/class racket/list racket/runtime-path
         (prefix-in a: "../../main.rkt") (prefix-in colors: "../../colors.rkt")
         "../main.rkt")
(define-runtime-path examples "../examples")
(define (build name mode)
  ((dynamic-require (build-path examples (string-append name ".rkt")) 'make-demo-timeline) #:theme-mode mode))
(define (inside-angle? p angle)
  (define vertex (angle-spec-b angle))
  (define u (point- (angle-spec-a angle) vertex))
  (define v (point- (angle-spec-c angle) vertex))
  (define d (point- p vertex))
  (define sign (if (positive? (cross u v)) 1 -1))
  (and (> (* sign (cross u d)) 0) (> (* sign (cross d v)) 0)))
(module+ test
  (for ([mode '(light dark)])
    (test-case (format "native measured alpha labels stay inside their angles: ~a" mode)
      (define t (build "copy-angle" mode))
      (define env (geometry-realization-values (geometry-timeline-realization t)))
      (define plan (geometry-timeline->annotation-plan t #:width 1280))
      (check-equal? (hash-ref (annotation-plan-marker-counts plan) 'source-mark)
                    (hash-ref (annotation-plan-marker-counts plan) 'target-mark))
      (for ([id '(source-mark target-mark)])
        (check-true (inside-angle? (hash-ref (annotation-plan-labels plan) id)
                                   (angle-marker-angle (hash-ref env id))))))
    (for ([name '("copy-angle" "tangent-at-point" "circumcenter" "orthocenter")])
      (test-case (format "native rendering of audited ending: ~a / ~a" name mode)
        (define t (build name mode))
        (define scene (geometry-timeline->scene t #:width 640 #:height 360))
        (define index (sub1 (a:scene-frame-count scene #:fps 1)))
        (define image (a:scene-frame->bitmap scene index #:fps 1
                        #:theme (if (eq? mode 'light) colors:animate-light-theme colors:animate-dark-theme)))
        (check-equal? (send image get-width) 640)
        (check-equal? (send image get-height) 360)))))
