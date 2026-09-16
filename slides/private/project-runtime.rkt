#lang racket/base
(require racket/list racket/path racket/runtime-path
         (prefix-in pr: "../../project.rkt")
         (prefix-in c: "../../colors.rkt")
         (prefix-in ty: "../../typography.rkt")
         (only-in "../../private/render-preparation-manifest.rkt" build-render-input-manifest!)
         "data.rkt" "check.rkt" "prepare.rkt" "codec.rkt" "scene-output.rkt")
(provide slides-source-preparer slides-source-builder)
(define-runtime-path runtime-source "project-runtime.rkt")
(define (load-board options)
  (define module (hash-ref options 'module))
  (define binding (hash-ref options 'binding))
  (define board (dynamic-require (string->path module) binding))
  (unless (storyboard-value? board) (slides-error 'source-type (list module binding) "source binding must be an immutable storyboard"))
  board)
(define (check-context context board)
  (define theme (storyboard-value-theme board))
  (unless (and (equal? (c:color-theme-fingerprint (pr:source-build-context-theme context))
                       (c:color-theme-fingerprint (theme-value-colors theme)))
               (equal? (ty:typography-theme-fingerprint (pr:source-build-context-typography context))
                       (ty:typography-theme-fingerprint (theme-value-typography theme))))
    (slides-error 'project-appearance '()
                  "render-spec theme and typography must match the storyboard theme; pass slide-theme-colors and slide-theme-typography")))
(define (slides-source-preparer context options)
  (define board (load-board options))
  (check-context context board)
  (define source-path (string->path (hash-ref options 'module)))
  ;; User-authored relative inputs resolve beside the storyboard module, while
  ;; prepared worker artifacts must be staged under the module-builder asset
  ;; root declared by animate/project.  These roots are intentionally distinct.
  (define source-base (path-only source-path))
  (define preparation-base
    (string->path (pr:source-build-context-asset-base context)))
  (define prepared
    (resolve-storyboard board #:effects? #t #:asset-base source-base))
  (define-values (payload artifacts assets)
    (prepared-storyboard->payload! prepared preparation-base))
  (define user-manifest (build-render-input-manifest! source-path assets))
  (define adapter-manifest (build-render-input-manifest! runtime-source '()))
  (pr:source-preparation
   #:payload payload #:artifacts artifacts
   #:dependencies (remove-duplicates (append (hash-ref user-manifest 'entries) (hash-ref adapter-manifest 'entries)) equal?)
   #:diagnostics (hash 'schema 'animate-slides-source-v1 'preparation-owner 'parent
                       'duration (prepared-storyboard-value-duration prepared)
                       'shots (length (prepared-storyboard-value-shots prepared))
                       'drawing-artifacts (length artifacts))))
(define (slides-source-builder context options payload)
  (define board (load-board options))
  (check-context context board)
  (storyboard->timeline (payload->prepared-storyboard payload board)
                        #:size (list (pr:source-build-context-width context) (pr:source-build-context-height context))))
