#lang racket/base

;;;
;;; Prepared Mathematical SVG Artifacts
;;;
;; Stages immutable typeset SVGs beneath a declared source asset root so the
;; generic preparation manifest can verify and pin them for worker builders.


;;;
;;; Imports and Exports
;;;

;; Imports
(require file/sha1
         (only-in racket/file make-directory* make-temporary-file)
         racket/list
         racket/path
         "prepared-plan-model.rkt"
         "typeset-model.rkt")

;; Exports
(provide math-preparation-artifact-directory
         stage-prepared-svg-artifacts!
         staged-svg-artifact-descriptors)


;;;
;;; Artifact Staging
;;;

; math-preparation-artifact-directory : path-string? -> path?
;;   Names the owned content-addressed SVG mirror below one module asset base.
(define (math-preparation-artifact-directory asset-base)
  (unless (path-string? asset-base)
    (raise-argument-error
     'math-preparation-artifact-directory "path-string?" asset-base))
  (build-path (path->complete-path asset-base)
              ".animate-math-preparation-artifacts-v1"))

; svg-digest! : path-string? -> string?
;;   Computes the immutable content identity of one completed SVG artifact.
(define (svg-digest! path)
  (call-with-input-file path sha1))

; atomic-copy-svg! : path-string? path-string? -> void?
;;   Publishes one verified immutable SVG copy without exposing a partial artifact.
(define (atomic-copy-svg! source destination)
  (when (and (file-exists? destination)
             (equal? (svg-digest! source) (svg-digest! destination)))
    (void))
  (unless (and (file-exists? destination)
               (equal? (svg-digest! source) (svg-digest! destination)))
    (define temporary
      (make-temporary-file "math-preparation-~a.svg" #f (path-only destination)))
    (dynamic-wind
      void
      (lambda ()
        (copy-file source temporary #t)
        (rename-file-or-directory temporary destination #t))
      (lambda ()
        (when (file-exists? temporary)
          (delete-file temporary)))))
  (unless (equal? (svg-digest! source) (svg-digest! destination))
    (raise-arguments-error
     'stage-prepared-svg-artifacts!
     "a staged SVG with the source artifact digest"
     "source" source
     "destination" destination)))

; stage-prepared-svg-artifacts! : prepared-math-plan? path-string? -> immutable-hash?
;;   Copies each unique parent-prepared SVG once and returns source-to-staged paths.
(define (stage-prepared-svg-artifacts! prepared asset-base)
  (unless (prepared-math-plan? prepared)
    (raise-argument-error
     'stage-prepared-svg-artifacts! "prepared-math-plan?" prepared))
  (define directory (math-preparation-artifact-directory asset-base))
  (make-directory* directory)
  (define original-assets
    (sort
     (remove-duplicates
      (append-map
       (lambda (layout)
         (map prepared-token-asset (prepared-layout-tokens layout)))
       (hash-values (prepared-math-plan-layouts prepared))))
     string<?))
  (for/hash ([source (in-list original-assets)])
    (unless (file-exists? source)
      (raise-arguments-error
       'stage-prepared-svg-artifacts! "an existing parent-prepared SVG" "asset" source))
    (define destination
      (build-path directory (string-append (svg-digest! source) ".svg")))
    (atomic-copy-svg! source destination)
    (values source (path->string (path->complete-path destination)))) )

; staged-svg-artifact-descriptors : immutable-hash? -> (listof immutable-hash?)
;;   Describes every staged SVG for generic manifest integrity validation.
(define (staged-svg-artifact-descriptors staged-assets)
  (unless (and (immutable? staged-assets) (hash? staged-assets))
    (raise-argument-error
     'staged-svg-artifact-descriptors "immutable hash?" staged-assets))
  (for/list ([path (in-list (sort (remove-duplicates (hash-values staged-assets)) string<?))])
    (hasheq 'path path 'role 'math-prepared-svg)))
