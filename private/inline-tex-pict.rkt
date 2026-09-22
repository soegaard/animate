#lang racket/base

;;;
;;; Inline TeX Pict Preparation
;;;

;; Converts shared mixed prose/TeX content into one frozen, baseline-aware Pict.
;; Parsing stays in animate/text-content; this adapter is the explicit native
;; preparation boundary used by slides and calculus captions.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/class
         racket/list
         racket/string
         (only-in pict
                  blank
                  colorize
                  pict?
                  pict-ascent
                  pict-descent
                  pict-height
                  pict-width
                  pin-over
                  text)
         (only-in racket/draw color% font%)
         "../text-content.rkt"
         "camera.rkt"
         "formula-visual.rkt"
         "latex-formula-pict-renderer.rkt"
         "pict-renderer.rkt")

;; Exports
(provide prepared-inline-text?
         prepared-inline-text-pict
         prepared-inline-text-width
         prepared-inline-text-height
         prepared-inline-text-ascent
         prepared-inline-text-descent
         prepared-inline-text-line-count
         prepared-inline-text-math-count
         current-inline-tex-preparation-observer
         prepare-inline-text)


;;;
;;; Data Representation
;;;

(struct prepared-inline-text
  (pict width height ascent descent line-count math-count)
  #:transparent)

;; prepared-inline-text represents one frozen native mixed-paragraph layout.
;;  - pict       pict?                         prepared paint and geometry.
;;  - width      nonnegative-real?             logical pixel width.
;;  - height     nonnegative-real?             logical pixel height.
;;  - ascent     nonnegative-real?             first-line baseline distance.
;;  - descent    nonnegative-real?             final-line baseline descent.
;;  - line-count exact-nonnegative-integer?    prepared line count.
;;  - math-count exact-nonnegative-integer?    typeset mathematical run count.

(struct inline-item (pict kind)
  #:transparent)

;; inline-item represents one atomic layout item.
;;  - pict  pict?       already measured native text or TeX.
;;  - kind  symbol?     'word, 'space, or 'display.

(struct inline-line (items width ascent descent display?)
  #:transparent)

;; inline-line represents one baseline-aligned prepared line.
;;  - items    ordered list of inline-item values.
;;  - width    nonnegative-real?  natural item advance.
;;  - ascent   nonnegative-real?  maximum item/strut ascent.
;;  - descent  nonnegative-real?  maximum item/strut descent.
;;  - display? boolean?           line contains one display-math item.

;; current-inline-tex-preparation-observer : (parameter/c procedure?)
;; Lets focused integration tests observe preparation without making a native
;; renderer or a frame sampler responsible for the effect boundary.
(define current-inline-tex-preparation-observer
  (make-parameter
   (lambda (_kind _value) (void))
   (lambda (observer)
     (unless (and (procedure? observer)
                  (procedure-arity-includes? observer 2))
       (raise-argument-error
        'current-inline-tex-preparation-observer
        "a procedure accepting kind and prepared value"
        observer))
     observer)))


;;;
;;; Preparation
;;;

; prepare-inline-text : text-content? font% color% positive-real?
;                       nonnegative-real? positive-real? alignment
;                       [#:formula-renderer pict-renderer?]
;                       [#:preamble string?]
;                       -> prepared-inline-text?
;; Typesets and lays out one mixed paragraph before later frame sampling.
(define (prepare-inline-text content font color font-size width line-spacing alignment
                             #:formula-renderer
                             [formula-renderer default-latex-formula-pict-renderer]
                             #:preamble [preamble "\\usepackage{xcolor}\n\\usepackage{amsmath}"])
  (unless (text-content? content)
    (raise-argument-error 'prepare-inline-text "text-content?" content))
  (unless (is-a? font font%)
    (raise-argument-error 'prepare-inline-text "font%" font))
  (unless (is-a? color color%)
    (raise-argument-error 'prepare-inline-text "color%" color))
  (unless (and (real? font-size) (positive? font-size))
    (raise-argument-error 'prepare-inline-text "positive real font size" font-size))
  (unless (and (real? width) (>= width 0))
    (raise-argument-error 'prepare-inline-text "nonnegative real width" width))
  (unless (and (real? line-spacing) (positive? line-spacing))
    (raise-argument-error 'prepare-inline-text "positive real line spacing" line-spacing))
  (unless (memq alignment '(left center right))
    (raise-argument-error 'prepare-inline-text "'left, 'center, or 'right" alignment))
  (unless (pict-renderer? formula-renderer)
    (raise-argument-error 'prepare-inline-text "pict-renderer?" formula-renderer))
  (unless (string? preamble)
    (raise-argument-error 'prepare-inline-text "string?" preamble))
  ((current-inline-tex-preparation-observer) 'layout content)
  (define strut (text "M" font))
  (define items
    (runs->items content font color font-size width formula-renderer preamble))
  (define lines (items->lines items strut width))
  (define-values (paragraph logical-width logical-height first-ascent final-descent)
    (lines->pict lines strut line-spacing alignment))
  (prepared-inline-text paragraph
                        logical-width
                        logical-height
                        first-ascent
                        final-descent
                        (length lines)
                        (for/sum ([run (in-list (text-content-runs content))])
                          (if (memq (text-run-kind run) '(inline-math display-math)) 1 0))))


;;;
;;; Run Measurement
;;;

; runs->items : text-content? font% color% positive-real? nonnegative-real?
;               pict-renderer? string? -> list?
;; Converts source runs to atomically wrappable Pict items and break markers.
(define (runs->items content font color font-size width formula-renderer preamble)
  (append-map
   (lambda (run)
     (case (text-run-kind run)
       [(text)
        (text-run->items (text-run-content run) font color)]
       [(hard-break) (list 'hard-break)]
       [(inline-math display-math)
        (define math-pict
          (typeset-run run font-size width formula-renderer preamble color))
        (list (inline-item math-pict
                           (if (eq? (text-run-kind run) 'display-math)
                               'display
                               'word)))]
       [else
        (raise-arguments-error
         'prepare-inline-text
         "a recognized normalized text run"
         "run" run)]))
   (text-content-runs content)))

; text-run->items : immutable-string? font% color% -> (listof inline-item?)
;; Preserves each compatible prose token as one shaped Pict rather than letters.
(define (text-run->items source font color)
  (for/list ([piece (in-list (regexp-match* #px"[^[:space:]]+|[[:blank:]]+" source))])
    (inline-item (colorize (text piece font) color)
                 (if (regexp-match? #px"^[[:blank:]]+$" piece) 'space 'word))))

; typeset-run : text-run? positive-real? nonnegative-real? pict-renderer? string?
;               color% -> pict?
;; Uses Animate's configured formula renderer once for one mathematical atom.
(define (typeset-run run font-size width formula-renderer preamble color)
  (define source (text-run-content run))
  ((current-inline-tex-preparation-observer) 'math run)
  (define colored-source (tex-color-source source color))
  (define camera
    (make-camera #:width (max 1 (inexact->exact (ceiling (max width 1))))
                 #:height (max 1 (inexact->exact (ceiling (max width 1))))
                 #:world-width (max width 1)
                 #:background "white"))
  ;; The formula adapter calibrates its local size against a 10-point LaTeX
  ;; document base. At one pixel per world unit, the requested font pixels are
  ;; therefore the semantic formula size directly.
  (define visual
    (latex-formula colored-source
                   #:id 'inline-tex
                   #:mode (if (eq? (text-run-kind run) 'display-math)
                               'display
                               'inline)
                   #:font-size font-size
                   #:preamble preamble
                   #:horizontal-alignment 'center
                   #:vertical-alignment 'center))
  (define picture
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error
             'prepare-inline-text
             "TeX that the configured formula renderer can typeset"
             "source" source
             "original error" (exn-message exception)))])
      (render-visual-with-pict-renderer formula-renderer visual camera)))
  (unless (and (pict? picture)
               (real? (pict-ascent picture))
               (real? (pict-descent picture))
               (>= (pict-ascent picture) 0)
               (>= (pict-descent picture) 0)
               (<= (abs (- (+ (pict-ascent picture) (pict-descent picture))
                           (pict-height picture)))
                   1e-6))
    (raise-arguments-error
     'prepare-inline-text
     "a formula renderer with genuine Pict baseline metrics"
     "source" source
     "ascent" (and (pict? picture) (pict-ascent picture))
     "descent" (and (pict? picture) (pict-descent picture))
     "height" (and (pict? picture) (pict-height picture))))
  picture)

; tex-color-source : immutable-string? color% -> immutable-string?
;; Applies the resolved foreground inside TeX itself.  latex-pict may return a
;; bitmap-backed Pict, for which post-hoc Pict colorization cannot recolor ink.
;; xcolor is part of this adapter's additive preamble.
(define (tex-color-source source color)
  (define (channel value)
    (number->string
     (/ (case value
          [(red) (send color red)]
          [(green) (send color green)]
          [(blue) (send color blue)])
        255.0)))
  (string->immutable-string
   (format "\\begingroup\\color[rgb]{~a,~a,~a} ~a\\endgroup"
           (channel 'red)
           (channel 'green)
           (channel 'blue)
           source)))


;;;
;;; Paragraph Layout
;;;

; items->lines : list? pict? nonnegative-real? -> (listof inline-line?)
;; Wraps atomic prose and math without breaking a TeX body or clipping overflow.
(define (items->lines items strut available-width)
  (define lines '())
  (define current '())
  (define current-width 0)
  (define pending-spaces '())
  (define pending-width 0)
  (define (line-metrics placed)
    (values (max (pict-ascent strut)
                 (apply max 0 (map (lambda (item) (pict-ascent (inline-item-pict item))) placed)))
            (max (pict-descent strut)
                 (apply max 0 (map (lambda (item) (pict-descent (inline-item-pict item))) placed)))))
  (define (finish-line! [force? #f])
    (when (or force? (pair? current) (pair? pending-spaces))
      (define-values (ascent descent) (line-metrics current))
      (set! lines
            (cons (inline-line (reverse current) current-width ascent descent #f)
                  lines))
      (set! current '())
      (set! current-width 0)
      (set! pending-spaces '())
      (set! pending-width 0)))
  (define (add-item! item)
    (define item-width (pict-width (inline-item-pict item)))
    (when (> item-width (+ available-width 1e-6))
      (raise-arguments-error
       'prepare-inline-text
       "an inline or display mathematical fragment that fits its measured line"
       "fragment-width" item-width
       "available-width" available-width))
    (define extra-width (if (null? current) 0 pending-width))
    (when (and (pair? current)
               (> (+ current-width extra-width item-width)
                  (+ available-width 1e-6)))
      (finish-line!)
      (set! extra-width 0))
    (when (pair? current)
      (set! current (append pending-spaces current))
      (set! current-width (+ current-width pending-width)))
    (set! pending-spaces '())
    (set! pending-width 0)
    (set! current (cons item current))
    (set! current-width (+ current-width item-width)))
  (for ([entry (in-list items)])
    (cond [(eq? entry 'hard-break) (finish-line! #t)]
          [(eq? (inline-item-kind entry) 'space)
           (when (pair? current)
             (set! pending-spaces (cons entry pending-spaces))
             (set! pending-width (+ pending-width (pict-width (inline-item-pict entry)))))]
          [(eq? (inline-item-kind entry) 'display)
           (finish-line!)
           (define display-width (pict-width (inline-item-pict entry)))
           (when (> display-width (+ available-width 1e-6))
             (raise-arguments-error
              'prepare-inline-text
              "a display mathematical fragment that fits its measured line"
              "fragment-width" display-width
              "available-width" available-width))
           (define-values (ascent descent) (line-metrics (list entry)))
           (set! lines
                 (cons (inline-line (list entry) display-width ascent descent #t)
                       lines))]
          [else (add-item! entry)]))
  ;; A display line has already committed itself.  Force a final empty line
  ;; only for empty input or an author-visible trailing hard break.
  (finish-line!
   (or (null? items)
       (and (pair? items)
            (eq? (last items) 'hard-break))))
  (reverse lines))

; lines->pict : (listof inline-line?) pict? positive-real? alignment
;                -> (values pict? nonnegative-real? nonnegative-real?
;                           nonnegative-real? nonnegative-real?)
;; Positions measured runs around per-line maxima and returns one paragraph Pict.
(define (lines->pict lines strut line-spacing alignment)
  (define effective-lines
    (if (null? lines)
        (list (inline-line '() 0 (pict-ascent strut) (pict-descent strut) #f))
        lines))
  (define logical-width
    (apply max 0 (map inline-line-width effective-lines)))
  (define baseline-font-height (+ (pict-ascent strut) (pict-descent strut)))
  (define advances
    (for/list ([line (in-list effective-lines)])
      (max (+ (inline-line-ascent line) (inline-line-descent line))
           (* baseline-font-height line-spacing))))
  (define logical-height
    (+ (inline-line-ascent (last effective-lines))
       (inline-line-descent (last effective-lines))
       (apply + (drop-right advances 1))))
  (define paragraph
    (for/fold ([base (blank logical-width logical-height
                            (inline-line-ascent (car effective-lines))
                            (inline-line-descent (last effective-lines)))]
               [top 0]
               #:result base)
              ([line (in-list effective-lines)]
               [advance (in-list advances)])
      (define line-pict (line->pict line))
      (define x
        (case alignment
          [(center) (/ (- logical-width (pict-width line-pict)) 2)]
          [(right) (- logical-width (pict-width line-pict))]
          [else 0]))
      (values (pin-over base x top line-pict)
              (+ top advance))))
  (values paragraph logical-width logical-height
          (inline-line-ascent (car effective-lines))
          (inline-line-descent (last effective-lines))))

; line->pict : inline-line? -> pict?
;; Pins each item to one shared baseline while preserving item Pict metrics.
(define (line->pict line)
  (for/fold ([base (blank (inline-line-width line)
                          (+ (inline-line-ascent line)
                             (inline-line-descent line))
                          (inline-line-ascent line)
                          (inline-line-descent line))]
             [cursor 0]
             #:result base)
            ([item (in-list (inline-line-items line))])
    (define picture (inline-item-pict item))
    (values (pin-over base cursor
                      (- (inline-line-ascent line)
                         (pict-ascent picture))
                      picture)
            (+ cursor (pict-width picture)))))
