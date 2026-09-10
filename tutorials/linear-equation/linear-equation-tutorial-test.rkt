#lang racket/base

;; Structural acceptance test for the API-first linear-equation tutorial.
;; Formula construction deliberately happens inside the test so the ordinary
;; all-examples module-load gate remains free of TeX work.

(require rackunit
         animate
         animate/authoring
         "linear-equation-tutorial.rkt")

(module+ test
  (check-equal? tutorial-title "Solving a Linear Equation")
  (check-true (scene-program? linear-equation-tutorial))
  (check-eq? (make-demo-program) linear-equation-tutorial)

  (define compiled (compile-scene-program linear-equation-tutorial))
  (check-equal? (map scene-block-run-id
                     (compiled-scene-program-block-runs compiled))
                '(problem
                  meaning
                  subtract-five
                  divide-by-three
                  check
                  summary))

  (define timeline (make-demo-timeline))
  (check-true (authored-timeline? timeline))
  (check-equal? (timeline-section-names timeline)
                '(problem
                  meaning
                  subtract-five
                  divide-by-three
                  check
                  summary))

  (define demo-scene (authored-timeline-scene timeline))
  (check-true (scene? demo-scene))
  (check-true (positive? (scene-duration demo-scene)))

  ;; Every tutorial scene is a real, positive-duration authoring section.
  (for ([name (in-list (timeline-section-names timeline))])
    (define entry (timeline-section timeline name))
    (check-true (< (authoring-section-start entry)
                   (authoring-section-end entry))))

  ;; Scene 2 retains the formula from Scene 1 and moves it upward. There is no
  ;; replacement equation that fades in at the new position.
  (define meaning-entry (timeline-section timeline 'meaning))
  (define moved-equation
    (scene-visual-at demo-scene
                     'problem-equation
                     (+ (authoring-section-start meaning-entry) 2/5)))
  (check-true (visual? moved-equation))
  (check-equal? (visual-position moved-equation) (vec2 0 4/5))

  ;; The final scene deliberately leaves the three-line derivation visible.
  (define final-time (- (scene-duration demo-scene) 1/1000))
  (check-true (visual? (scene-visual-at demo-scene 'summary-row-1 final-time)))
  (check-true (visual? (scene-visual-at demo-scene 'summary-row-2 final-time)))
  (check-true (visual? (scene-visual-at demo-scene 'summary-row-3 final-time))))
