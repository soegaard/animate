#lang racket/base

;; Keep the public 3D bindings that participate in manual cross references in
;; one focused regression test.  `tools/check-documentation.rkt` verifies the
;; actual Scribble tags; this test makes an omitted declaration or renamed
;; export immediately visible in the ordinary source-tree suite as well.

(require rackunit
         racket/file
         racket/list
         racket/path
         racket/runtime-path
         racket/string)

(define-runtime-path reference-root "../scribblings/reference")

(define absent (gensym 'absent))
(define (binding module-path name)
  (dynamic-require module-path name (lambda () absent)))

;; Public 3D contracts are split across focused reference chapters.  Scan that
;; source set rather than requiring the navigation-map chapter to duplicate
;; declarations solely for a formatting-sensitive source-text assertion.
(define (reference-source-text directory)
  (string-join
   (for/list ([path (in-directory directory)]
              #:when (and (file-exists? path)
                          (equal? (filename-extension path) #"scrbl")))
     (file->string path))
   "\n"))

(module+ test
  (for ([name (in-list '(surface-mesh3d surface-mesh3d?
                         surface-mesh3d-mesh
                         surface-mesh3d-vertex-provenance
                         surface-mesh3d-triangle-provenance
                         surface-mesh3d-topology-key
                         surface-mesh3d-diagnostics
                         trajectory-segment3d?
                         trajectory-segment3d-bounds))])
    (check-not-eq? (binding "../3d.rkt" name) absent))
  (define source (reference-source-text reference-root))
  (for ([entry (in-list
                (list (cons 'surface-mesh3d
                            #px"@defstruct\\*\\[surface-mesh3d(?:[[:space:]\\[]|$)")
                      (cons 'trajectory-segment3d?
                            #px"@defproc\\[\\(trajectory-segment3d\\?(?:[[:space:]\\[]|$)")
                      (cons 'trajectory-segment3d-bounds
                            #px"@defproc\\[\\(trajectory-segment3d-bounds(?:[[:space:]\\[]|$)")))])
    (check-not-false
     (regexp-match? (cdr entry) source)
     (format "public 3D binding lacks a reference declaration: ~a" (car entry)))))
