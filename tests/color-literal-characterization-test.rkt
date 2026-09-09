#lang racket/base

;;;
;;; Literal Color Characterization Tests
;;;

;; Locks down the pure, headless literal-color contract before tokens and
;; themes are introduced.

(require rackunit
         racket/runtime-path
         "../private/color-style.rkt"
         "../private/interpolation.rkt")

(define-runtime-path color-style-module "../private/color-style.rkt")

(module+ test
  ;; The core color module has no Pict, drawing, GUI, filesystem, or process
  ;; dependency. This test itself runs under headless `raco test`.
  (check-not-exn (lambda () (dynamic-require color-style-module #f)))

  ;; Exact literal parsing, including the four supported hexadecimal widths.
  (check-equal? (color-spec->rgba-color " #0f8 ")
                (rgba-color #x00 #xFF #x88 1))
  (check-equal? (color-spec->rgba-color "#0f8c")
                (rgba-color #x00 #xFF #x88 4/5))
  (check-equal? (color-spec->rgba-color "#123456")
                (rgba-color #x12 #x34 #x56 1))
  (check-equal? (color-spec->rgba-color "#12345680")
                (rgba-color #x12 #x34 #x56 128/255))
  (check-equal? (color-spec->rgba-color " Light-Steel_Blue ")
                (rgba-color 176 196 222 1))
  ;; Animate's literal table follows X11/Racket names rather than CSS green.
  (check-equal? (color-spec->rgba-color "green")
                (rgba-color 0 255 0 1))
  (check-equal? (color-spec->rgba-color "transparent")
                (rgba-color 0 0 0 0))

  ;; Fractional semantic channels are valid; invalid channels never normalize
  ;; silently into a color.
  (check-equal? (rgba-color 1/2 2.5 254.75 1/3)
                (rgba-color 1/2 2.5 254.75 1/3))
  (for ([invalid (in-list (list -1 256 +inf.0 -inf.0 +nan.0))])
    (check-exn exn:fail:contract?
               (lambda () (rgba-color invalid 0 0 1))))
  (for ([invalid (in-list (list -1/10 11/10 +inf.0 -inf.0 +nan.0))])
    (check-exn exn:fail:contract?
               (lambda () (rgba-color 0 0 0 invalid))))
  (check-false (color-spec? #f))
  (check-false (color-spec? "not-a-supported-literal"))
  (check-exn exn:fail:contract?
             (lambda () (color-spec->rgba-color "#12")))

  ;; Numerical color interpolation keeps the caller's exact endpoint object
  ;; and uses componentwise encoded-sRGB values only at interior progress.
  (define source (rgba-color 10 20 30 1/4))
  (define destination (rgba-color 110 220 250 3/4))
  (check-eq? (rgba-color-lerp source destination 0) source)
  (check-eq? (rgba-color-lerp source destination 1) destination)
  (check-equal? (rgba-color-lerp source destination 1/2)
                (rgba-color 60 120 140 1/2))
  (check-eq? (interpolate-value source destination 0) source)
  (check-eq? (interpolate-value source destination 1) destination)
  (check-exn exn:fail:contract?
             (lambda () (interpolate-value "red" "blue" 1/2))))
