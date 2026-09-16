#lang racket/base

;;;
;;; Fresh-process Mathematical Preparation Contracts
;;;
;; Starts real Racket processes to check portable reconstruction against synthetic
;; native geometry. Actual raster/process-renderer probes remain a separate test.

;;;
;;; Imports and Exports
;;;
;; Imports
(require (for-syntax racket/base)
         (only-in racket/file make-temporary-file delete-directory/files)
         (only-in racket/runtime-path define-runtime-path)
         (only-in racket/system system*))

;;;
;;; Explicit Contract Execution
;;;
; fixture-path : path?
;;   Locates the inert-on-require child fixture used by both producer and consumer.
(define-runtime-path fixture-path "tests/composite-process-fixture.rkt")

; gallery-fixture-path : path?
;;   Locates the full-gallery producer/consumer contract with real staged files.
(define-runtime-path gallery-fixture-path "tests/gallery-process-fixture.rkt")

; run-fresh-process-contracts! : -> void?
;;   Round-trips four lessons and both gallery themes through twelve real processes and cleans only owned test data.
(define (run-fresh-process-contracts!)
  (define racket-executable
    (or (find-executable-path (find-system-path 'exec-file))
        (raise-user-error 'run-process-contracts "cannot resolve the current Racket executable")))
  (define directory (make-temporary-file "math-move-contracts-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (for ([lesson (in-list '("linear-concrete" "linear-general"
                               "quadratic-concrete" "quadratic-general"))])
        (define file (build-path directory (string-append lesson ".rktd")))
        (for ([mode (in-list '("encode" "decode"))])
          (unless (system* racket-executable fixture-path mode lesson file)
            (raise-user-error 'run-process-contracts "~a failed for ~a" mode lesson))))
      (for ([theme (in-list '("light" "dark"))])
        (define root (build-path directory (string-append "gallery " theme " Ω")))
        (for ([mode (in-list '("encode" "decode"))])
          (unless (system* racket-executable gallery-fixture-path mode theme root)
            (raise-user-error 'run-process-contracts "gallery ~a failed for ~a" mode theme))))
      (displayln "6 fresh-process contracts passed (12 Racket processes; synthetic geometry, not native rasterization)."))
    (lambda () (delete-directory/files directory))))

(module+ main (run-fresh-process-contracts!))
