#lang racket/base

;; Filesystem-backed evidence for a real-context conformance discrepancy.  The
;; metrics module stays GUI-independent; this module is intentionally the one
;; place that turns its immutable ARGB snapshots into reviewable PNG files.

(require racket/class
         racket/draw
         racket/file
         racket/path
         "conformance-report3d.rkt")

(provide write-conformance-artifacts3d!)

(define (write-conformance-artifacts3d! directory expected actual width height
                                        #:metadata [metadata (hasheq)]
                                        #:renderer-info [renderer-info (hasheq)])
  (unless (path-string? directory)
    (raise-argument-error 'write-conformance-artifacts3d! "path-string?" directory))
  (unless (and (hash? metadata) (immutable? metadata))
    (raise-argument-error 'write-conformance-artifacts3d! "immutable-hash?" metadata))
  (unless (and (hash? renderer-info) (immutable? renderer-info))
    (raise-argument-error 'write-conformance-artifacts3d! "immutable-hash?" renderer-info))
  (define output-directory (simplify-path (path->complete-path directory)))
  (make-directory* output-directory)
  (define report (argb-conformance-report3d expected actual width height))
  (define (write-argb! filename bytes)
    (define bitmap (make-object bitmap% width height #t))
    (send bitmap set-argb-pixels 0 0 width height bytes)
    (unless (send bitmap save-file (build-path output-directory filename) 'png)
      (error 'write-conformance-artifacts3d! "could not write ~a" filename)))
  (write-argb! "software.png" expected)
  (write-argb! "opengl.png" actual)
  (write-argb! "absolute-difference.png" (conformance-report3d-difference-argb report))
  (write-argb! "large-difference-mask.png"
               (conformance-report3d-large-difference-mask-argb report))
  (write-argb! "edge-mask.png" (conformance-report3d-edge-mask-argb report))
  (write-argb! "interior-mask.png" (conformance-report3d-interior-mask-argb report))
  (write-rktd! (build-path output-directory "metrics.rktd")
               (hasheq 'width width
                       'height height
                       'metadata metadata
                       'metrics (conformance-report3d-metrics report)))
  (write-rktd! (build-path output-directory "renderer-info.rktd") renderer-info)
  report)

(define (write-rktd! path value)
  (call-with-output-file path
    (lambda (output)
      (write value output)
      (newline output))
    #:exists 'truncate/replace))
