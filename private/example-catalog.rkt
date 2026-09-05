#lang racket/base

;;;
;;; Executable Example Catalogue
;;;

;; One immutable catalogue declares the canonical examples used by the guide,
;; smoke tests, gallery links, and optional thumbnail generation. It has no
;; renderer or GUI dependency.


;;;
;;; Imports and Exports
;;;

(require racket/list
         racket/string)

(provide (struct-out example-entry)
         canonical-example-catalog
         example-entry-by-id
         example-entry->markdown-link
         example-catalog->readme-section)


;;;
;;; Catalogue Values
;;;

(struct example-entry
  (id title source binding categories requirements thumbnail-time expected-duration)
  #:transparent)

;; example-entry declares one maintained author-facing example.
;;  - id                symbol?                 stable catalogue identifier.
;;  - title             immutable-string?       gallery-facing title.
;;  - source            immutable-string?       repository-relative source path.
;;  - binding           symbol?                  exported scene/program binding.
;;  - categories        (listof symbol?)         topical classification.
;;  - requirements      (listof symbol?)         external-run requirements.
;;  - thumbnail-time    nonnegative-real?        representative scene time.
;;  - expected-duration positive-real?           expected scene duration.

(define canonical-example-catalog
  (list
   (example-entry
    'basic-scene "A moving circle" "examples/parallel-animation-groups.rkt"
    'make-demo-scene '(basics animation) '(core) 1 5)
   (example-entry
    'animation-composition "Composed parallel animation"
    "examples/parallel-animation-groups.rkt" 'make-demo-scene
    '(animation composition) '(core) 2 5)
   (example-entry
    'source-formula "Source-addressed formula matching"
    "examples/transform-matching-strings.rkt" 'make-demo-scene
    '(formula source-selection) '(core latex dvisvgm) 2 6)
   (example-entry
    'formula-derivation "Structured formula derivation"
    "examples/structured-formula-derivation.rkt" 'make-demo-scene
    '(formula derivation) '(core latex dvisvgm) 2 7)
   (example-entry
    'relations "First-class relations"
    "examples/relation-visuals.rkt" 'make-demo-scene
    '(relations geometry) '(core) 2 6)
   (example-entry
    'adaptive-plot "Adaptive function plot"
    "examples/function-graphs.rkt" 'make-demo-scene
    '(plotting adaptive) '(core) 2 6)
   (example-entry
    'ode-flow "Adaptive ODE trajectory"
    "examples/adaptive-ode-trajectory.rkt" 'make-demo-scene
    '(ode flow) '(core) 3 7)
   (example-entry
    'source-block-reload "Source-block hot reload"
    "examples/source-block-hot-reload.rkt" 'hot-reload-demo
    '(authoring preview) '(core gui) 1 4)
   (example-entry
    'preview-inspector "Preview REPL and inspector"
    "examples/source-block-hot-reload.rkt" 'hot-reload-demo
    '(preview repl inspector) '(core gui) 2 4)
   (example-entry
    'authored-media "Authored audio and video"
    "examples/authored-media-assembly.rkt" 'make-demo-scene
    '(rendering audio subtitles) '(core ffmpeg) 1 4)))


;;;
;;; Lookup and Presentation
;;;

; example-entry-by-id : symbol? -> (or/c example-entry? #f)
;;   Finds one canonical example, or #f when its identifier is not registered.
(define (example-entry-by-id id)
  (unless (symbol? id)
    (raise-argument-error 'example-entry-by-id "symbol?" id))
  (findf (lambda (entry) (eq? (example-entry-id entry) id))
         canonical-example-catalog))

; example-entry->markdown-link : example-entry? -> string?
;;   Formats the canonical relative-source link used by generated repositories.
(define (example-entry->markdown-link entry)
  (unless (example-entry? entry)
    (raise-argument-error
     'example-entry->markdown-link "example-entry?" entry))
  (format "[~a](~a)"
          (example-entry-title entry)
          (string-replace (example-entry-source entry) " " "%20")))

; example-catalog->readme-section : [listof example-entry?] -> string?
;;   Produces the canonical Markdown block embedded in README.md. Keeping the
;;   text generation here lets the repository check prove that README links,
;;   requirements, and the executable gallery all describe the same entries.
(define (example-catalog->readme-section [entries canonical-example-catalog])
  (unless (and (list? entries) (andmap example-entry? entries))
    (raise-argument-error
     'example-catalog->readme-section "list of example-entry?" entries))
  (string-append
   "## Canonical examples\n\n"
   (string-join
    (for/list ([entry (in-list entries)])
      (format "- ~a — ~a; requires ~a."
              (example-entry->markdown-link entry)
              (string-join
               (map symbol->string (example-entry-categories entry)) ", ")
              (string-join
               (map symbol->string (example-entry-requirements entry)) ", ")))
    "\n")
   "\n"))
