#lang racket/base

(require rackunit
         animate
         animate/authoring
         "text-types-tutorial.rkt")

(module+ test
  (check-equal? tutorial-title "Animate text types")
  (check-true (scene-program? text-types-tutorial))
  (check-eq? (make-demo-program) text-types-tutorial)

  (define compiled (compile-scene-program text-types-tutorial))
  (define runs (compiled-scene-program-block-runs compiled))
  (check-equal? (map scene-block-run-id runs)
                '(typography headings explanatory-text technical-text raw-text recap))
  (for ([run (in-list runs)])
    (check-true (< (scene-block-run-start-time run)
                   (scene-block-run-end-time run))))

  (define timeline (make-demo-timeline))
  (check-equal? (timeline-section-names timeline)
                '(typography headings explanatory-text technical-text raw-text recap))

  ;; Each page contains the constructors that it claims to demonstrate.
  (define (block-scene name)
    (compiled-program-block-output-scene compiled name))
  (define (final-visual scene id)
    (scene-visual-at scene id (- (scene-duration scene) 1/1000)))
  (for ([id (in-list '(typography-title typography-subtitle typography-body typography-note))])
    (check-true (visual? (final-visual (block-scene 'typography) id))))
  (for ([id (in-list '(role-title role-subtitle role-section-heading headings-body))])
    (check-true (visual? (final-visual (block-scene 'headings) id))))
  (for ([id (in-list '(role-body role-quotation role-caption role-label label-detail))])
    (check-true (visual? (final-visual (block-scene 'explanatory-text) id))))
  (for ([id (in-list '(role-code role-annotation role-styled role-styled-rich))])
    (check-true (visual? (final-visual (block-scene 'technical-text) id))))
  (for ([id (in-list '(raw-plain raw-paragraph raw-rich))])
    (check-true (visual? (final-visual (block-scene 'raw-text) id)))))
