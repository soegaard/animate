#lang racket/base

;; Artifact generation remains usable without a GL context.  The real-context
;; lane supplies its two renderer snapshots; this test locks down the complete
;; evidence set and the machine-readable metadata shape.

(require rackunit
         racket/file
         racket/path
         "../private/3d/conformance-artifacts3d.rkt")

(define (opaque-black width height)
  (define pixels (make-bytes (* 4 width height) 0))
  (for ([offset (in-range 0 (bytes-length pixels) 4)])
    (bytes-set! pixels offset 255))
  (bytes->immutable-bytes pixels))

(module+ test
  (define directory (make-temporary-file "animate-conformance-artifacts-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define expected (opaque-black 2 2))
     (define actual (bytes-copy expected))
     (bytes-set! actual 1 255)
     (write-conformance-artifacts3d!
      directory expected actual 2 2
      #:metadata (hasheq 'probe 'line-only 'primitive-types '(line) 'samples 1)
      #:renderer-info (hasheq 'renderer "test" 'requested-samples 1
                             'framebuffer-format 'rgba16f-linear-premultiplied))
     (for ([filename (in-list '("software.png" "opengl.png" "absolute-difference.png"
                                "large-difference-mask.png" "edge-mask.png"
                                "interior-mask.png" "metrics.rktd" "renderer-info.rktd"))])
       (check-true (file-exists? (build-path directory filename))))
     (define metrics
       (call-with-input-file (build-path directory "metrics.rktd") read))
     (check-equal? (hash-ref (hash-ref metrics 'metadata) 'probe) 'line-only)
     (check-equal? (hash-ref (hash-ref metrics 'metrics)
                             'large-difference-pixel-count)
                   1))
   (lambda () (delete-directory/files directory))))
