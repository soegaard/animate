#lang racket/base

;;;
;;; Software/OpenGL Frame Conformance Artifact Writer
;;;

;; Usage:
;;   racket tools/render3d-conformance.rkt \
;;     --software software.png --opengl opengl.png --output artifacts/
;;
;; The renderer-independent report is kept in private/3d; this small tool owns
;; all filesystem and bitmap effects. It produces stable review artifacts for a
;; failing real-context job without making PNGs part of the semantic oracle.

(require racket/class
         racket/cmdline
         racket/draw
         racket/file
         racket/path
         "../private/3d/conformance-report3d.rkt")

(define software-path #f)
(define opengl-path #f)
(define output-directory #f)

(command-line
 #:program "render3d-conformance.rkt"
 #:once-each
 [("--software") path "Software-reference PNG." (set! software-path path)]
 [("--opengl") path "OpenGL PNG." (set! opengl-path path)]
 [("--output") path "Directory for diagnostic artifacts." (set! output-directory path)])

(unless (and software-path opengl-path output-directory)
  (raise-arguments-error
   'render3d-conformance
   "--software, --opengl, and --output are all required"
   "software" software-path "opengl" opengl-path "output" output-directory))

(define software (read-bitmap software-path))
(define opengl (read-bitmap opengl-path))
(unless (and (is-a? software bitmap%) (send software ok?))
  (raise-arguments-error 'render3d-conformance "a readable software bitmap"
                         "software" software-path))
(unless (and (is-a? opengl bitmap%) (send opengl ok?))
  (raise-arguments-error 'render3d-conformance "a readable OpenGL bitmap"
                         "opengl" opengl-path))

(define width (send software get-width))
(define height (send software get-height))
(unless (and (= width (send opengl get-width)) (= height (send opengl get-height)))
  (raise-arguments-error
   'render3d-conformance "same-sized source images"
   "software-size" (cons width height)
   "opengl-size" (cons (send opengl get-width) (send opengl get-height))))

(define (bitmap-argb bitmap)
  (define bytes (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height bytes)
  (bytes->immutable-bytes bytes))

(define report
  (argb-conformance-report3d (bitmap-argb software) (bitmap-argb opengl) width height))

(make-directory* output-directory)

(define (write-bitmap! filename bitmap)
  (unless (send bitmap save-file (build-path output-directory filename) 'png)
    (error 'render3d-conformance "could not write ~a" filename)))

(define (write-argb! filename bytes)
  (define bitmap (make-object bitmap% width height #t))
  (send bitmap set-argb-pixels 0 0 width height bytes)
  (write-bitmap! filename bitmap))

;; Keep the histogram in the structured report and render it as a compact PNG
;; too. The horizontal axis is component error 0--255; the bar height is
;; relative to the largest bucket, which makes sparse outliers immediately
;; visible in a CI artifact without altering the numerical oracle.
(define (histogram-argb histogram)
  (define histogram-width 256)
  (define histogram-height 128)
  (define maximum (max 1 (apply max (vector->list histogram))))
  (define bytes (make-bytes (* 4 histogram-width histogram-height) 255))
  (for ([error (in-range histogram-width)])
    (define height
      (inexact->exact
       (ceiling (* histogram-height (/ (vector-ref histogram error) maximum)))))
    (for ([y (in-range (- histogram-height height) histogram-height)])
      (define offset (* 4 (+ error (* y histogram-width))))
      (bytes-set! bytes offset 255)
      (bytes-set! bytes (add1 offset) 34)
      (bytes-set! bytes (+ offset 2) 93)
      (bytes-set! bytes (+ offset 3) 158)))
  (values histogram-width histogram-height (bytes->immutable-bytes bytes)))

(define (write-histogram! histogram)
  (define-values (histogram-width histogram-height bytes)
    (histogram-argb histogram))
  (define bitmap (make-object bitmap% histogram-width histogram-height #t))
  (send bitmap set-argb-pixels 0 0 histogram-width histogram-height bytes)
  (write-bitmap! "component-error-histogram.png" bitmap))

(write-bitmap! "software.png" software)
(write-bitmap! "opengl.png" opengl)
(write-argb! "absolute-difference.png" (conformance-report3d-difference-argb report))
(write-argb! "large-difference-mask.png"
             (conformance-report3d-large-difference-mask-argb report))
(write-argb! "edge-mask.png" (conformance-report3d-edge-mask-argb report))
(write-argb! "interior-mask.png" (conformance-report3d-interior-mask-argb report))
(write-histogram! (hash-ref (conformance-report3d-metrics report) 'histogram))

(call-with-output-file
 (build-path output-directory "metrics.rktd")
 (lambda (output)
   (write
    (hasheq 'width width
            'height height
            'software-source (path->string (simplify-path software-path))
            'opengl-source (path->string (simplify-path opengl-path))
            'metrics (conformance-report3d-metrics report))
    output)
   (newline output))
 #:exists 'truncate/replace)

(displayln (path->string (simplify-path output-directory)))
