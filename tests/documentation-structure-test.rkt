#lang racket/base

;;;
;;; SCENE-EM Documentation Structure Tests
;;;

;; The manual entry point must remain a navigable table of contents, not grow
;; back into the monolithic reference it replaced.  Each listed chapter keeps
;; its own Scribble source while `scribblings/animate.scrbl` retains the one
;; registered manual identity.

(require rackunit
         racket/file
         racket/runtime-path)

(define-runtime-path manual-path "../scribblings/animate.scrbl")
(define-runtime-path guide-root "../scribblings/guide")
(define-runtime-path concepts-root "../scribblings/concepts")
(define-runtime-path reference-root "../scribblings/reference")
(define-runtime-path cookbook-root "../scribblings/cookbook")

(define (chapter root name)
  (build-path root name))

(module+ test
  (define manual-text (file->string manual-path))
  (check-true (< (file-size manual-path) 10000)
              "the registered manual should be an entry point, not a monolith")
  (for ([include (in-list
                  '("guide/getting-started.scrbl"
                    "guide/source-programs.scrbl"
                    "guide/interactive-preview.scrbl"
                    "guide/rendering-a-video.scrbl"
                    "guide/project-planning.scrbl"
                    "concepts/immutable-scenes.scrbl"
                    "concepts/formula-source-maps.scrbl"
                    "concepts/relation-phases.scrbl"
                    "reference/module-boundaries.scrbl"
                    "reference/authoring.scrbl"
                    "reference/preview.scrbl"
                    "reference/project.scrbl"
                    "reference/scene.scrbl"
                    "reference/geometry-and-plots.scrbl"
                    "reference/visuals-and-relations.scrbl"
                    "reference/experimental.scrbl"
                    "reference/rendering.scrbl"
                    "cookbook/canonical-examples.scrbl"
                    "cookbook/reference-recipes.scrbl"))])
    (check-true (regexp-match? (regexp (regexp-quote include)) manual-text)))
  (for ([path (in-list
               (list (chapter guide-root "getting-started.scrbl")
                     (chapter guide-root "source-programs.scrbl")
                     (chapter guide-root "interactive-preview.scrbl")
                     (chapter guide-root "rendering-a-video.scrbl")
                     (chapter guide-root "project-planning.scrbl")
                     (chapter concepts-root "immutable-scenes.scrbl")
                     (chapter concepts-root "formula-source-maps.scrbl")
                     (chapter concepts-root "relation-phases.scrbl")
                     (chapter reference-root "module-boundaries.scrbl")
                     (chapter reference-root "authoring.scrbl")
                     (chapter reference-root "preview.scrbl")
                     (chapter reference-root "project.scrbl")
                     (chapter reference-root "scene.scrbl")
                     (chapter reference-root "geometry-and-plots.scrbl")
                     (chapter reference-root "visuals-and-relations.scrbl")
                     (chapter reference-root "experimental.scrbl")
                     (chapter reference-root "rendering.scrbl")
                     (chapter cookbook-root "canonical-examples.scrbl")
                     (chapter cookbook-root "reference-recipes.scrbl")))])
    (check-true (file-exists? path))))
