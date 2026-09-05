#lang racket/base

;;;
;;; FFmpeg Encoder Capability Checks
;;;

;; A doctor report only establishes that an executable exists. Project checking
;; needs the stronger, effectful question: does that installed executable
;; accept this exact video encoder and pixel format? These probes create no
;; output files and retain no mutable process state.

(require racket/port
         racket/string
         racket/system
         "encoder-profile.rkt")

(provide ffmpeg-encoder-available?
         ffmpeg-pixel-format-available?)

(define (ffmpeg-encoder-available? executable codec)
  (and executable
       (let-values ([(status output errors)
                     (ffmpeg-command-result
                      executable
                      "-hide_banner"
                      "-h"
                      (format "encoder=~a" (encoder-codec-name codec)))])
         ;; FFmpeg 8 prints an unknown-encoder diagnostic but (surprisingly)
         ;; exits successfully. Require its canonical help heading as well as
         ;; a zero status; otherwise a typo would pass preflight and fail only
         ;; after frames had been rendered.
         (and (zero? status)
              (string-contains?
               (string-append output "\n" errors)
               (format "Encoder ~a" (encoder-codec-name codec)))))))

(define (ffmpeg-pixel-format-available? executable pixel-format)
  (and executable
       (let-values ([(status output _errors)
                     (ffmpeg-command-result executable "-hide_banner" "-pix_fmts")])
         (and (zero? status)
              (for/or ([line (in-list (string-split output "\n" #:trim? #f))])
                ;; The first token is the I/O/HW flag column; format names are
                ;; later whitespace-separated tokens. Exact token matching
                ;; avoids accepting a similarly named pixel format.
                (member (symbol->string pixel-format)
                        (string-split (string-trim line))))))))

(define (ffmpeg-command-result executable . arguments)
  (with-handlers ([exn:fail? (lambda (_error) (values 1 "" ""))])
    (define-values (process standard-output standard-input standard-error)
      (apply subprocess #f #f #f executable arguments))
    (close-output-port standard-input)
    ;; FFmpeg's probe output is bounded, but drain both ports before waiting so
    ;; a verbose future encoder cannot fill one pipe and deadlock the check.
    (define output-channel (make-channel))
    (define error-channel (make-channel))
    (thread (lambda () (channel-put output-channel (port->string standard-output))))
    (thread (lambda () (channel-put error-channel (port->string standard-error))))
    (subprocess-wait process)
    (define output (channel-get output-channel))
    (define errors (channel-get error-channel))
    (close-input-port standard-output)
    (close-input-port standard-error)
    (values (subprocess-status process) output errors)))
