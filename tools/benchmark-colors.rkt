#lang racket/base

;;;
;;; Color Resolution Microbenchmark
;;;

;; Measures only the pure color-resolution boundary.  It is intentionally a
;; review tool rather than a test gate: elapsed time varies by machine.

(require racket/cmdline
         "../colors.rkt")

(define iterations 100000)
(command-line
 #:program "benchmark-colors.rkt"
 #:once-each
 [("--iterations") count "positive number of resolution iterations"
  (define parsed (string->number count))
  (unless (and (exact-positive-integer? parsed))
    (raise-argument-error 'benchmark-colors.rkt "positive integer" count))
  (set! iterations parsed)]
 #:args () (void))

(define work
  (for/list ([index (in-range 32)])
    (color-mix (series-color index) theme-accent 1/2 #:space 'oklab)))

(define (bytes->hex value)
  (apply string-append
         (for/list ([byte (in-bytes value)])
           (define digits (string-upcase (number->string byte 16)))
           (if (= (string-length digits) 1) (string-append "0" digits) digits))))

(define-values (_values cpu-milliseconds real-milliseconds gc-milliseconds)
  (time-apply
   (lambda ()
     (for/fold ([checksum 0]) ([index (in-range iterations)])
       (define color (resolve-color (list-ref work (modulo index (length work)))
                                    animate-light-theme))
       (+ checksum (inexact->exact (round (rgba-color-blue color))))))
   '()))

(write
 `(animate-color-benchmark-v1
   (iterations ,iterations)
   (theme animate-light ,(bytes->hex (color-theme-fingerprint animate-light-theme)))
   (sample-accent ,(rgba-color->hex (resolve-color theme-accent animate-light-theme)))
   (cpu-milliseconds ,cpu-milliseconds)
   (real-milliseconds ,real-milliseconds)
   (gc-milliseconds ,gc-milliseconds)))
(newline)
