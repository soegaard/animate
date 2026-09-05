#lang racket/base

;;;
;;; SCENE-EM Documented Binding Tests
;;;

;; The concise guide modules name the current public API directly. This test
;; protects those examples from silently drifting to private or removed names.

(require rackunit)

(define absent
  (gensym 'absent))

(define (public-binding module-path name)
  (dynamic-require module-path name (lambda () absent)))

(module+ test
  (for ([name (in-list '(circle vec2 scene-play scene-add make-scene
                         move-to scene-sample formula-select
                         formula-source-select source-occurrence
                         relation-visual))])
    (check-not-eq? (public-binding "../main.rkt" name) absent))
  (for ([name (in-list '(scene-program? scene-block-spec? make-scene-program))])
    (check-not-eq? (public-binding "../authoring.rkt" name) absent))
  (for ([name (in-list '(open-program-preview preview-available?))])
    (check-not-eq? (public-binding "../preview.rkt" name) absent))
  (for ([name (in-list '(render-frames! encode-mp4!))])
    (check-not-eq? (public-binding "../render.rkt" name) absent))
  (for ([name (in-list '(animate-project? plan-project prepare-project!
                         project-target-section project-plan->datum))])
    (check-not-eq? (public-binding "../project.rkt" name) absent))
  (check-not-eq? (public-binding "../experimental.rkt" 'derived-visual) absent))
