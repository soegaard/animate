#lang racket/base

;;;
;;; SCENE-EM Public Module Boundaries
;;;

;; Ensures that intentional module ownership—not legacy re-exports—defines the
;; public surface. These checks load modules but perform no rendering or GUI
;; initialization.

(require rackunit)

(define absent
  (gensym 'absent))

(define (module-binding module-path name)
  (dynamic-require module-path name (lambda () absent)))

(module+ test
  (check-not-eq? (module-binding "../main.rkt" 'make-scene) absent)
  (check-not-eq? (module-binding "../main.rkt" 'math-tex) absent)
  (check-not-eq? (module-binding "../main.rkt" 'relation-visual) absent)
  (check-not-eq? (module-binding "../main.rkt" 'follow-above) absent)
  (check-eq? (module-binding "../main.rkt" 'keep-above) absent)
  (check-eq? (module-binding "../main.rkt" 'render-frames!) absent)
  (check-eq? (module-binding "../main.rkt" 'encode-mp4!) absent)
  (check-eq? (module-binding "../main.rkt" 'render-timeline-section!) absent)
  (check-eq? (module-binding "../main.rkt" 'make-authored-timeline) absent)
  (check-eq? (module-binding "../main.rkt" 'derived-visual) absent)

  (check-not-eq? (module-binding "../authoring.rkt" 'scene-program?) absent)
  (check-not-eq? (module-binding "../authoring.rkt" 'make-authored-timeline) absent)
  (check-not-eq? (module-binding "../preview.rkt" 'open-scene-preview) absent)
  (check-not-eq? (module-binding "../render.rkt" 'render-frames!) absent)
  (check-not-eq? (module-binding "../render.rkt" 'encode-mp4!) absent)
  (check-not-eq? (module-binding "../render.rkt" 'render-timeline-section!) absent)
  (check-eq? (module-binding "../render.rkt" 'current-project-artifact-opener) absent)
  (check-eq? (module-binding "../render.rkt" 'make-scene) absent)
  (check-not-eq? (module-binding "../experimental.rkt" 'derived-visual) absent)
  (check-not-eq? (module-binding "../experimental.rkt" 'derived-context-value-ref) absent))
