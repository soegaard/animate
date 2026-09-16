#lang racket/base

;;;
;;; Gallery Native Contract Model
;;;
;; Extends the existing synthetic native contract with scalar cleanup and records
;; project calls. It deliberately is not the real renderer or process executor.

;;;
;;; Imports and Exports
;;;
(require (submod "native-contract.rkt" support)
         "../private/typeset-model.rkt")
(provide gallery-test-loader fixture-options fixture-context fixture-typesetter
         (all-from-out (submod "native-contract.rkt" support)))

; fixture-options : (listof symbol?) [symbol?] -> immutable-hash?
;;   Supplies a complete transferable source configuration for deterministic tests.
(define (fixture-options ids [theme 'dark])
  (hasheq 'plates ids 'theme theme 'show-api? #t 'width 1280 'height 720 'fps 30 'supersample 1))

; fixture-context : path-string? -> immutable-hash?
;;   Models the generic source context's getters without importing Animate core.
(define (fixture-context root)
  (hasheq 'fixture? #t 'asset-base root 'width 1280 'height 720 'fps 30 'theme 'dark))

; fixture-typesetter : string? -> procedure?
;;   Reuses the established synthetic token geometry with an explicitly owned SVG file.
(define (fixture-typesetter asset)
  (lambda (state size multiplication foreground directory)
    (define layout (synthetic-typesetter state size multiplication foreground directory))
    (struct-copy prepared-layout layout
      [tokens (for/list ([token (in-list (prepared-layout-tokens layout))])
                (struct-copy prepared-token token [asset asset]))])))

; declaration-recorder : symbol? -> procedure?
;;   Models keyword constructors by retaining exact positional and keyword inputs.
(define (declaration-recorder name)
  (make-keyword-procedure
    (lambda (keywords arguments . positional)
      (hasheq 'kind name 'positional positional
              'keywords (for/hash ([key (in-list keywords)] [argument (in-list arguments)])
                          (values key argument))))))

; gallery-test-loader : symbol? symbol? -> any/c
;;   Provides only the actual adapter names used by the gallery; unknown names fail loudly.
(define (gallery-test-loader scope name)
  (case scope
    [(animate)
     (case name
       [(scene-remove-value)
        (lambda (scn id)
          (unless (hash-has-key? (scene-data scn) id) (error 'fixture "unknown scalar ~a" id))
          (struct-copy scene scn [data (hash-remove (scene-data scn) id)]))]
       [(scene-duration) scene-duration]
       [else (loader scope name)])]
    [(colors)
     (case name [(animate-dark-theme) 'dark] [(animate-light-theme) 'light]
       [(color-theme-fingerprint) values]
       [else (error 'fixture "unknown color binding ~a" name)])]
    [(project)
     (case name
       [(source-build-context?) (lambda (ctx) (and (hash? ctx) (hash-ref ctx 'fixture? #f)))]
       [(source-build-context-width) (lambda (ctx) (hash-ref ctx 'width))]
       [(source-build-context-height) (lambda (ctx) (hash-ref ctx 'height))]
       [(source-build-context-fps) (lambda (ctx) (hash-ref ctx 'fps))]
       [(source-build-context-theme) (lambda (ctx) (hash-ref ctx 'theme))]
       [(source-build-context-asset-base) (lambda (ctx) (hash-ref ctx 'asset-base))]
       [(source-preparation)
        (lambda (#:payload payload #:artifacts artifacts #:dependencies dependencies #:diagnostics diagnostics)
          (hasheq 'payload payload 'artifacts artifacts 'dependencies dependencies 'diagnostics diagnostics))]
       [(animate-project module-builder-source render-spec output-spec encoder-spec cache-spec)
        (declaration-recorder name)]
       [else (error 'fixture "unknown project binding ~a" name)])]
    [(preparation-manifest)
     (case name
       [(build-render-input-manifest!)
        (lambda (path assets) (hasheq 'entries (list (hasheq 'path path 'role 'module))))]
       [else (error 'fixture "unknown manifest binding ~a" name)])]
    [(project-execution)
     (case name [(render-project!) (declaration-recorder name)]
       [else (error 'fixture "unknown execution binding ~a" name)])]
    [else (error 'fixture "unknown native scope ~a/~a" scope name)]))
