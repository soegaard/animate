#lang racket/base

;;;
;;; Animate Palette Swatch Sheet
;;;

;; Writes a deterministic SVG review sheet from the authoritative numerical
;; palette table. It deliberately does not sample or trace a reference image.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/cmdline
         racket/format
         racket/string
         "../colors.rkt")

(provide render-color-palette-sheet!
         write-palette-sheet!)


;;;
;;; Command Line and SVG Output
;;;

;; output-path : path-string?
;;   Names the deterministic SVG artifact written by this tool.
;; svg-escape : string? -> string?
;;   Escapes text placed into an SVG text element.
(define (svg-escape text)
  (regexp-replace*
   #px"[&<>\"]" text
   (lambda (match)
     (case (string-ref match 0)
       [(#\&) "&amp;"]
       [(#\<) "&lt;"]
       [(#\>) "&gt;"]
       [(#\") "&quot;"]))))

;; rgba->hex : rgba-color? -> string?
;;   Formats one reviewed opaque swatch as an uppercase CSS hexadecimal literal.
(define (rgba->hex color)
  (string-append "#"
                 (byte->hex (inexact->exact (round (rgba-color-red color))))
                 (byte->hex (inexact->exact (round (rgba-color-green color))))
                 (byte->hex (inexact->exact (round (rgba-color-blue color))))))

;; byte->hex : byte? -> string?
;;   Formats one byte as two uppercase hexadecimal digits.
(define (byte->hex value)
  (define digits (string-upcase (number->string value 16)))
  (if (= (string-length digits) 1)
      (string-append "0" digits)
      digits))

;; checksum->hex : bytes? -> string?
;;   Formats the deterministic binary palette checksum for SVG review text.
(define (checksum->hex checksum)
  (apply string-append
         (for/list ([value (in-bytes checksum)])
           (byte->hex value))))

;; luminance : rgba-color? -> real?
;;   Computes an encoded-sRGB review hint, not an accessibility score.
(define (luminance color)
  (+ (* 0.2126 (rgba-color-red color))
     (* 0.7152 (rgba-color-green color))
     (* 0.0722 (rgba-color-blue color))))

;; swatch-text-color : rgba-color? -> string?
;;   Chooses a readable black or white label for the static review sheet.
(define (swatch-text-color color)
  (if (> (luminance color) 145) "#111111" "#FFFFFF"))

;; write-palette-sheet! : output-port? -> void?
;;   Emits one complete SVG document from the current built-in palette snapshot.
(define (write-palette-sheet! out)
  (define groups (palette-groups animate-palette))
  (define columns 6)
  (define cell-width 158)
  (define cell-height 92)
  (define left 154)
  (define top 84)
  (define width (+ left (* columns cell-width) 36))
  (define height (+ top (* (length groups) cell-height) 42))
  (fprintf out "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  (fprintf out "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"~a\" height=\"~a\" viewBox=\"0 0 ~a ~a\">\n"
           width height width height)
  (fprintf out "  <rect width=\"100%\" height=\"100%\" fill=\"#FFFFFF\"/>\n")
  (fprintf out "  <text x=\"28\" y=\"36\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"24\" font-weight=\"700\" fill=\"#17202A\">Animate palette v~a</text>\n"
           (color-palette-version animate-palette))
  (fprintf out "  <text x=\"28\" y=\"61\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"12\" fill=\"#59636F\">checksum ~a</text>\n"
           (checksum->hex animate-palette-checksum))
  (for ([group (in-list groups)] [row (in-naturals)])
    (define group-name (symbol->string (car group)))
    (define keys (cadr group))
    (define y (+ top (* row cell-height)))
    (fprintf out "  <text x=\"24\" y=\"~a\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"15\" font-weight=\"700\" fill=\"#252B33\">~a</text>\n"
             (+ y 38) (svg-escape group-name))
    (for ([key (in-list keys)] [column (in-naturals)])
      (define color (palette-ref animate-palette key))
      (define x (+ left (* column cell-width)))
      (define fill (rgba->hex color))
      (define ink (swatch-text-color color))
      (fprintf out "  <rect x=\"~a\" y=\"~a\" width=\"~a\" height=\"70\" rx=\"5\" fill=\"~a\" stroke=\"#20252B\" stroke-width=\"1\"/>\n"
               x y (- cell-width 10) fill)
      (fprintf out "  <text x=\"~a\" y=\"~a\" font-family=\"Menlo,monospace\" font-size=\"13\" font-weight=\"700\" fill=\"~a\">~a</text>\n"
               (+ x 9) (+ y 27) ink (svg-escape (symbol->string key)))
      (fprintf out "  <text x=\"~a\" y=\"~a\" font-family=\"Menlo,monospace\" font-size=\"12\" fill=\"~a\">~a</text>\n"
               (+ x 9) (+ y 49) ink fill)))
  (fprintf out "</svg>\n"))

;; render-color-palette-sheet! : path-string? -> void?
;; Writes a deterministic review artifact at the caller-selected destination.
(define (render-color-palette-sheet! destination)
  (call-with-output-file destination
    (lambda (out) (write-palette-sheet! out))
    #:exists 'truncate/replace))

(module+ main
  (define output-path
    (command-line
     #:program "render-color-palette-sheet.rkt"
     #:args [destination]
     destination))
  (render-color-palette-sheet! output-path))
