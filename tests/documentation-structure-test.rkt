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
         racket/path
         racket/runtime-path)

(define-runtime-path manual-path "../scribblings/animate.scrbl")
(define-runtime-path guide-root "../scribblings/guide")
(define-runtime-path concepts-root "../scribblings/concepts")
(define-runtime-path reference-root "../scribblings/reference")
(define-runtime-path cookbook-root "../scribblings/cookbook")

(define (chapter root name)
  (build-path root name))


;; Inspect the include tree, not only the five-part manual entry point.
(define (manual-source-tree-text entry)
  (define seen (make-hash))
  (define (visit path)
    (define key (simplify-path (path->complete-path path)))
    (cond
      [(hash-ref seen key #f) ""]
      [(not (file-exists? key)) ""]
      [else
       (hash-set! seen key #t)
       (define text (file->string key))
       (for/fold ([result text])
                 ([relative (in-list
                             (regexp-match*
                              #px"@include-section\\[\"([^\"\r\n]+)\"\\]"
                              text #:match-select cadr))])
         (string-append result "\n"
                        (visit (build-path (path-only key) relative))))]))
  (visit entry))

(module+ test
  (define manual-text (manual-source-tree-text manual-path))
  (check-true (< (file-size manual-path) 10000)
              "the registered manual should be an entry point, not a monolith")
  (for ([include (in-list
                  '("guide/getting-started.scrbl"
                    "guide/source-programs.scrbl"
                    "guide/interactive-preview.scrbl"
                    "guide/rendering-a-video.scrbl"
                    "guide/project-planning.scrbl"
                    "guide/slides.scrbl"
                    "concepts/immutable-scenes.scrbl"
                    "concepts/formula-source-maps.scrbl"
                    "concepts/relation-phases.scrbl"
                    "concepts/spatial-coordinates.scrbl"
                    "reference/module-boundaries.scrbl"
                    "reference/authoring.scrbl"
                    "reference/preview.scrbl"
                    "reference/project.scrbl"
                    "reference/scene.scrbl"
                    "reference/geometry-and-plots.scrbl"
                    "reference/3d-algebra.scrbl"
                    "reference/visuals-and-relations.scrbl"
                    "reference/experimental.scrbl"
                    "reference/rendering.scrbl"
                    "cookbook/canonical-examples.scrbl"
                    "guide/package-source.scrbl"
                    "reference/coordinate-decorations.scrbl"
                    "reference/markers-scatter-and-areas.scrbl"
                    "reference/statistical-diagrams.scrbl"
                    "cookbook/appearance-and-text-effects.scrbl"
                    "cookbook/camera-views-and-overlays.scrbl"
                    "cookbook/animation-timing-recipes.scrbl"
                    "cookbook/path-motion-recipes.scrbl"
                    "cookbook/path-correspondence-recipes.scrbl"
                    "cookbook/topology-morph-recipes.scrbl"
                    "cookbook/plot-styling-recipes.scrbl"))])
    (check-true (regexp-match? (regexp (regexp-quote include)) manual-text)))
  (for ([path (in-list
               (list (chapter guide-root "getting-started.scrbl")
                     (chapter guide-root "source-programs.scrbl")
                     (chapter guide-root "interactive-preview.scrbl")
                     (chapter guide-root "rendering-a-video.scrbl")
                     (chapter guide-root "project-planning.scrbl")
                     (chapter guide-root "slides.scrbl")
                     (chapter concepts-root "immutable-scenes.scrbl")
                     (chapter concepts-root "formula-source-maps.scrbl")
                     (chapter concepts-root "relation-phases.scrbl")
                     (chapter concepts-root "spatial-coordinates.scrbl")
                     (chapter reference-root "module-boundaries.scrbl")
                     (chapter reference-root "authoring.scrbl")
                     (chapter reference-root "preview.scrbl")
                     (chapter reference-root "project.scrbl")
                     (chapter reference-root "scene.scrbl")
                     (chapter reference-root "geometry-and-plots.scrbl")
                     (chapter reference-root "3d-algebra.scrbl")
                     (chapter reference-root "visuals-and-relations.scrbl")
                     (chapter reference-root "experimental.scrbl")
                     (chapter reference-root "rendering.scrbl")
                     (chapter cookbook-root "canonical-examples.scrbl")
                     (chapter guide-root "package-source.scrbl")
                     (chapter reference-root "coordinate-decorations.scrbl")
                     (chapter reference-root "markers-scatter-and-areas.scrbl")
                     (chapter reference-root "statistical-diagrams.scrbl")
                     (chapter cookbook-root "appearance-and-text-effects.scrbl")
                     (chapter cookbook-root "camera-views-and-overlays.scrbl")
                     (chapter cookbook-root "animation-timing-recipes.scrbl")
                     (chapter cookbook-root "path-motion-recipes.scrbl")
                     (chapter cookbook-root "path-correspondence-recipes.scrbl")
                     (chapter cookbook-root "topology-morph-recipes.scrbl")
                     (chapter cookbook-root "plot-styling-recipes.scrbl")))])
    (check-true (file-exists? path))
    ;; `include-section` turns each included document into a top-level HTML
    ;; page.  A section fragment has an anonymous parent there, which Scribble
    ;; renders as `???` in the table of contents.  Stable titled pages also
    ;; give the generated manual readable, durable URLs.
    (check-true
     (regexp-match? #rx"(?m:^@title\\[#:tag \\\"[^\\\"]+\\\".*\\])"
                    (file->string path))
     (format "included manual chapter needs a tagged @title: ~a" path))))
