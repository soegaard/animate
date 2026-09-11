#lang racket/base
(require rackunit racket/list
         (prefix-in a: "../../main.rkt") (prefix-in colors: "../../colors.rkt")
         "../main.rkt" "../private/marker-shapes.rkt"
         (prefix-in gallery: "../examples/gallery.rkt"))
(define (child group id)
  (or (findf (lambda (v) (eq? (a:visual-id v) id)) (a:group-visual-children group))
      (error 'test "missing Visual ~a" id)))
(construction sample
  (given [A (point -1 0)] [B (point 1 0)] [M (point 0 0)])
  (layout (label-text square "⊥") (label-side M 'below))
  (timing [read-delay 0.1] [action-duration 0.2] [step-pause 0.1])
  (step [s (segment A B)] [l (line (point 0 -1) (point 0 1))])
  (step "The lines meet at a right angle."
    [square (marker (perpendicular s l #:at M))]
    (show-label square)))
(module+ test
  (test-case "native layout uses Animate's measured font boxes"
    (define t (construction->timeline sample))
    (define p (geometry-timeline->annotation-plan t #:width 320))
    (check-equal? (annotation-plan-metrics p) 'animate-text)
    (check-equal? (hash-ref (annotation-plan-texts p) 'square) "⊥")
    (check-true (point? (hash-ref (annotation-plan-labels p) 'M))))
  (test-case "native text content comes from layout metadata"
    (define t (construction->timeline sample))
    (define v (geometry-timeline->visual t (geometry-timeline-duration t) #:width 320 #:id 'test))
    (check-equal? (a:text-visual-content (child (child v 'square) 'square/label)) "⊥"))
  (test-case "marker labels and revealed paths survive reverse-order scene sampling"
    (define t (construction->timeline sample))
    (define scene (geometry-timeline->scene t #:width 320 #:height 180 #:id 'test))
    (define first (a:scene-visual-at scene 'test 1.5))
    (a:scene-visual-at scene 'test 0.7)
    (a:scene-visual-at scene 'test 0)
    (check-equal? first (a:scene-visual-at scene 'test 1.5)))
  (test-case "light and dark gallery scenes build with measured labels"
    (for ([mode (in-list '(light dark))])
      (define t (gallery:make-demo-timeline #:theme-mode mode))
      (define p (geometry-timeline->annotation-plan t #:width 320))
      (check-true (hash-has-key? (annotation-plan-texts p) 'arc-letter))
      (check-equal? (hash-ref (annotation-plan-texts p) 'crowded-C) "C (intersection)")
      (check-equal? (hash-ref (annotation-plan-labels p) 'crowded-M) (point 0.42 -0.32))
      (check-equal? (hash-ref (annotation-plan-marker-counts p) 'equal-one) 1)
      (check-equal? (hash-ref (annotation-plan-marker-counts p) 'equal-two) 2)
      (check-equal? (hash-ref (annotation-plan-marker-counts p) 'equal-three) 3)))
  (test-case "new annotation paths rasterize under both color themes"
    (define t (construction->timeline sample))
    (define scene (geometry-timeline->scene t #:width 320 #:height 180))
    (for ([theme (in-list (list colors:animate-light-theme colors:animate-dark-theme))])
      (check-not-false (a:scene-frame->bitmap scene 12 #:fps 10 #:theme theme)))))
