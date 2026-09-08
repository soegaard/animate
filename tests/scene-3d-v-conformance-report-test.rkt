#lang racket/base

;;; SCENE-3D-V correction: coverage-aware immutable conformance metrics.

(require rackunit
         "../private/3d/conformance-report3d.rkt")

(define (opaque-black-image width height)
  (define bytes (make-bytes (* 4 width height) 0))
  (for ([offset (in-range 0 (bytes-length bytes) 4)])
    (bytes-set! bytes offset 255))
  (bytes->immutable-bytes bytes))

(module+ test
  (define expected (opaque-black-image 2 2))
  (define actual (bytes-copy expected))
  ;; One RGB disagreement and one alpha-only disagreement exercise the two
  ;; dimensions that a global maximum cannot distinguish.
  (bytes-set! actual 1 40)
  (bytes-set! actual 12 235)
  (define report (argb-conformance-report3d expected actual 2 2))
  (define metrics (conformance-report3d-metrics report))
  (check-equal? (hash-ref metrics 'pixel-count) 4)
  (check-equal? (hash-ref metrics 'component-count) 16)
  (check-equal? (hash-ref metrics 'different-pixel-count) 2)
  (check-equal? (hash-ref metrics 'different-component-count) 2)
  (check-equal? (hash-ref metrics 'large-difference-components) 0)
  (check-equal? (hash-ref metrics 'alpha-only-different-pixel-count) 1)
  (check-equal? (+ (hash-ref metrics 'alpha-only-edge-pixel-count)
                   (hash-ref metrics 'alpha-only-interior-pixel-count))
                1)
  (check-equal? (hash-ref metrics 'maximum-component-error) 40)
  (check-equal? (hash-ref metrics 'mean-absolute-error) 15/4)
  (check-equal? (hash-ref metrics 'difference-bounds) '#(0 0 1 1))
  (check-equal? (vector-ref (hash-ref metrics 'histogram) 20) 1)
  (check-equal? (vector-ref (hash-ref metrics 'histogram) 40) 1)
  (check-true (immutable? (conformance-report3d-difference-argb report)))
  (check-true (immutable? (conformance-report3d-edge-mask-argb report)))
  (check-true (immutable? (conformance-report3d-interior-mask-argb report)))
  (check-exn exn:fail:contract?
             (lambda () (argb-conformance-report3d expected actual 0 2)))
  (check-exn exn:fail:contract?
             (lambda () (argb-conformance-report3d expected expected 3 2))))
