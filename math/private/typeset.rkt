#lang racket/base

;;;
;;; External Formula Typesetting
;;;
;; Runs complete-formula TeX preparation, SVG ownership extraction, and bounded asset
;; publication outside the mathematical model.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  "typeset-model.rkt"
  "validation.rkt"
  (only-in racket/class send)
  (only-in racket/file make-directory* make-temporary-file)
  racket/list
  (only-in racket/match match-let)
  racket/path
  racket/string
  file/sha1
  "native.rkt"
  "datum.rkt"
  "model.rkt"
  "format.rkt"
  "semantic-svg.rkt")

;; Exports
(provide
  (struct-out prepared-token) (struct-out prepared-layout) typeset-state! token-visual
  token-with-position token-with-id token-scaled default-math-cache-directory
  current-math-typesetter current-math-typeset-observer bitmap-visible-bounds)

;;;
;;; Construction and Operations
;;;
; default-math-cache-directory : path?
;;   Names the adapter-owned content-addressed SVG cache directory.
(define default-math-cache-directory
  (build-path (find-system-path 'pref-dir) "animate-math" "svg-v1"))

; bitmap-visible-bounds : any/c -> (or/c list? #f)
;;   Measures visible raster coverage only for prepared SVG isolation, not semantic
;;   geometry.
(define (bitmap-visible-bounds bitmap)
  (define w (send bitmap get-width))
  (define h (send bitmap get-height))
  (define pixels (make-bytes (* 4 w h)))
  (send bitmap get-argb-pixels 0 0 w h pixels)
  (define left w)
  (define right -1)
  (define top h)
  (define bottom -1)
  (for* ([y (in-range h)] [x (in-range w)])
    (when (positive? (bytes-ref pixels (* 4 (+ x (* y w)))))
      (set! left (min left x))
      (set! right (max right x))
      (set! top (min top y))
      (set! bottom (max bottom y))))
  (and (>= right left) (list left top (+ 1 (- right left)) (+ 1 (- bottom top)))))

; write-asset! : any/c path-string? -> string?
;;   Publishes a content-addressed SVG asset atomically in the adapter cache.
(define (write-asset! source directory)
  (make-directory* directory)
  (define path
    (build-path directory (string-append (sha1 (open-input-string source)) ".svg")))
  (unless (file-exists? path)
    (define temporary (make-temporary-file "math-~a.svg" #f directory))
    (dynamic-wind
      void
      (lambda ()
        (call-with-output-file temporary
          #:exists 'truncate/replace
          (lambda (o) (display source o)))
        (with-handlers ([exn:fail:filesystem? (lambda (e) (unless (file-exists? path) (raise e)))])
          (rename-file-or-directory temporary path #f)))
      (lambda () (when (file-exists? temporary) (delete-file temporary)))))
  (path->string (path->complete-path path)))

;;;
;;; Complete-Formula Typesetting
;;;
; semantic-typeset! : math? positive-real? symbol? string? path-string? ->
;   prepared-layout?
;;   Typesets one marked complete formula and prepares occurrence-owned SVG pieces.
(define (semantic-typeset! state font-size multiplication foreground cache-directory)
  (define source (format-math-source state #:multiplication multiplication))
  (define-values (marked markers) (annotate-math-source source))
  (define tagged
    ((native 'tagged 'tagged-formula)
      #:id 'math-preparation
      #:font-size font-size
      #:preamble "\\usepackage{amsmath,amssymb}"
      ((native 'tagged 'formula-fragment) 'complete-math marked)))
  (define fragment
    ((native 'parts 'formula-part-formula)
      (car ((native 'parts 'formula-assembly-visual-parts) tagged))))
  (define svg ((native 'tagged 'tagged-formula-fragment-visual-svg-source) fragment))
  (define svg-pict ((native 'svg 'svg-string->pict) svg))
  (define width ((native 'pict 'pict-width) svg-pict))
  (define height ((native 'pict 'pict-height) svg-pict))
  (define box (svg-view-box svg))
  (define unit
    (/ font-size ((native 'formula 'formula-visual-document-font-points) fragment)))
  (define ids (svg-marker-ids svg))
  (unless (= (length ids) (length markers))
    (error 'typeset-state!
      "dvisvgm did not retain every semantic marker (~a expected, ~a found)."
      (length markers)
      (length ids)))
  (define tokens
    (filter values
      (for/list ([marker (in-list markers)] [i (in-naturals)])
        (define name (semantic-marker-name marker))
        (define span (semantic-marker-span marker))
        (define isolated (isolate-svg-marker svg name))
        (define pict ((native 'svg 'svg-string->pict) isolated))
        (define bounds (bitmap-visible-bounds ((native 'pict 'pict->bitmap) pict)))
        (and bounds
          (match-let
            ([(list x y w h) bounds])
            (define cropped
              (crop-svg isolated
                (list
                  (+ (car box) (* (/ x width) (caddr box)))
                  (+ (cadr box) (* (/ y height) (cadddr box)))
                  (* (/ w width) (caddr box))
                  (* (/ h height) (cadddr box)))
                w
                h))
            (define role
              (if (eq? (math-source-span-role span) 'expression)
                'structure
                (math-source-span-role span)))
            (prepared-token
              (math-source-span-path span)
              role
              (substring
                (math-source-text source)
                (math-source-span-start span)
                (math-source-span-end span))
              (write-asset!
               (canonicalize-svg-definitions (recolor-svg cropped foreground))
               cache-directory)
              (* unit (- (+ x (/ w 2)) (/ width 2)))
              (* unit (- (/ height 2) (+ y (/ h 2))))
              (* unit w)
              (* unit h)
              (string->symbol (format "prepared-~a" i))))))))
  (when (null? tokens)
    (error 'typeset-state! "The expression produced no visible mathematical parts."))
  (prepared-layout state tokens source '()))

; current-math-typesetter : (parameter/c procedure?)
;;   Selects the preparation-time typesetter, never a per-frame callback.
(define current-math-typesetter
  (make-parameter semantic-typeset!
    (lambda (typesetter) (check-procedure 'current-math-typesetter typesetter 5))))

; default-math-typeset-observer : math? -> void?
;;   Leaves ordinary production preparation silent.  Native integration tests can
;;   set ANIMATE_MATH_TYPESET_EVENT_LOG to observe every process that reaches the
;;   effect boundary without adding a test-only branch to a worker builder.
(define (default-math-typeset-observer state)
  (define event-log (getenv "ANIMATE_MATH_TYPESET_EVENT_LOG"))
  (when event-log
    (call-with-output-file event-log
      #:exists 'append
      (lambda (out)
        (fprintf out "~s ~s\n" (math-id state) (math-revision state)))))
  (void))

; current-math-typeset-observer : (parameter/c (math? . -> . any/c))
;;   Instruments the one complete-formula effect boundary for focused tests.
(define current-math-typeset-observer
  (make-parameter default-math-typeset-observer
    (lambda (observer)
      (check-procedure 'current-math-typeset-observer observer 1))))

;;;
;;; Typesetter Dispatch
;;;
; typeset-state! : math? [#:font-size positive-real?] [#:multiplication symbol?]
;   [#:foreground string?] [#:cache-directory path-string?] -> prepared-layout?
;;   Invokes and validates the explicit construction-time typesetter callback.
(define (typeset-state! state
          #:font-size [font-size 11/20]
          #:multiplication [multiplication 'school]
          #:foreground [foreground "black"]
          #:cache-directory [directory default-math-cache-directory])
  (unless (math? state) (raise-argument-error 'typeset-state! "math?" state))
  (check-positive-real 'typeset-state! font-size)
  (unless (memq multiplication '(school explicit))
    (raise-argument-error 'typeset-state! "multiplication style" multiplication))
  (unless (path-string? directory)
    (raise-argument-error 'typeset-state! "path-string?" directory))
  ((current-math-typeset-observer) state)
  (define prepared
    ((current-math-typesetter) state font-size multiplication foreground directory))
  (unless (prepared-layout? prepared)
    (raise-arguments-error 'typeset-state!
      "typesetter must return a prepared-layout"
      "result"
      prepared))
  (unless (equal? state (prepared-layout-state prepared))
    (raise-arguments-error 'typeset-state!
      "typesetter must preserve the requested mathematical state"
      "result-state"
      (prepared-layout-state prepared)))
  (for ([token (in-list (prepared-layout-tokens prepared))])
    (math-occurrence-at state (prepared-token-path token)))
  prepared)

; token-visual : prepared-token? [#:opacity (real-in 0 1)] -> any/c
;;   Converts one prepared token to a native SVG reference without rerunning TeX.
(define (token-visual token #:opacity [opacity 1])
  ((native 'animate 'svg-image)
    (prepared-token-asset token)
    #:id (prepared-token-id token)
    #:center ((native 'animate 'vec2) (prepared-token-x token) (prepared-token-y token))
    #:opacity opacity
    #:width (prepared-token-width token)
    #:height (prepared-token-height token)))
