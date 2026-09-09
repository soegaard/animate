#lang racket/base

;; Keep the public 3D bindings that participate in manual cross references in
;; one focused regression test.  `tools/check-documentation.rkt` verifies the
;; actual Scribble tags; this test makes an omitted declaration or renamed
;; export immediately visible in the ordinary source-tree suite as well.

(require rackunit
         racket/file
         racket/runtime-path)

(define-runtime-path manual "../scribblings/reference/3d-algebra.scrbl")

(define absent (gensym 'absent))
(define (binding module-path name)
  (dynamic-require module-path name (lambda () absent)))

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
  (define source (file->string manual))
  (for ([declaration (in-list '("@defstruct*[surface-mesh3d"
                                "@defproc[(trajectory-segment3d?"
                                "@defproc[(trajectory-segment3d-bounds"))])
    (check-not-false
     (regexp-match? (regexp-quote declaration) source)
     (format "manual declaration missing: ~a" declaration))))
