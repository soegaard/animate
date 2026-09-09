#lang racket/base

;;;
;;; Deterministic Color Probe Tool
;;;

;; Prints review-friendly, evaluator-free data derived from one immutable
;; built-in theme. It creates no image and does not consult a renderer.

(require racket/cmdline
         "../colors.rkt")

(define requested-theme 'animate-light)
(command-line
 #:program "run-color-probes.rkt"
 #:once-each
 [("--theme") name "animate-light or animate-dark"
  (set! requested-theme (string->symbol name))]
 #:args () (void))

(define theme
  (case requested-theme
    [(animate-light) animate-light-theme]
    [(animate-dark) animate-dark-theme]
    [else
     (raise-arguments-error 'run-color-probes.rkt
                             "a built-in theme identifier"
                             "theme" requested-theme)]))

(define (probe-color color)
  (define inspection (inspect-color color theme))
  (list (hash-ref inspection 'authored)
        (hash-ref inspection 'resolved-hex)
        (hash-ref inspection 'effective-alpha)))

(define (bytes->hex value)
  (apply string-append
         (for/list ([byte (in-bytes value)])
           (define digits (string-upcase (number->string byte 16)))
           (if (= (string-length digits) 1) (string-append "0" digits) digits))))

(write
 `(animate-color-probe-v1
   (theme ,(color-theme-id theme)
          ,(bytes->hex (color-theme-fingerprint theme)))
   (palette
    ,@(for/list ([key (in-list (palette-keys (color-theme-palette theme)))])
        (list key (rgba-color->hex (palette-ref (color-theme-palette theme) key)))))
   (roles
    ,@(for/list ([key (in-list (theme-role-keys theme))])
        (list key (probe-color (role-color key)))))
   (series
   ,@(for/list ([index (in-range (length (theme-series theme)))])
        (list index (probe-color (series-color index)))))))
(newline)
