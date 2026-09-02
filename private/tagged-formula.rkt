#lang racket/base

;;;
;;; Tagged SVG Formula Model
;;;

;; Compiles one complete TeX formula through latex+dvisvgm, retaining explicit
;; fragment groups in the resulting SVG. Each group becomes a specialised
;; formula Visual at its TeX-determined local position, so the existing formula
;; correspondence and timeline machinery can move unchanged fragments rigidly.

(require racket/class
         racket/file
         racket/port
         racket/string
         (only-in pict pict->bitmap pict-height pict-width)
         svg/svg
         "affine-transform.rkt"
         "animation.rkt"
         "formula-parts-visual.rkt"
         "formula-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "svg-write-paths.rkt"
         "write-in-adapter.rkt"
         "visual-model.rkt")

(provide (struct-out formula-fragment)
         tagged-formula
         math-tex
         tagged-formula-fragment-visual?
         tagged-formula-fragment-visual-svg-source
         transform-matching-formula
         transform-matching-tex)


;;; Fragment Definitions

(struct formula-fragment (name source)
  #:transparent
  #:guard
  (lambda (name source type-name)
    (unless (symbol? name)
      (raise-argument-error type-name "symbol?" name))
    (unless (and (string? source)
                 (positive? (string-length source)))
      (raise-argument-error type-name "nonempty string?" source))
    (values name (string->immutable-string source))))

;; formula-fragment is one author-declared contiguous TeX unit. This model does
;; not attempt to parse arbitrary LaTeX into mathematical tokens.


;;; Renderable Fragment Visuals

;; The parent formula-visual representation preserves compatibility with
;; formula-part and formula-correspondence. It also lets the established formula
;; transition compiler move an unchanged fragment as one rigid object.
(struct tagged-formula-fragment-visual formula-visual (svg-source)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual)
     (formula-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation
      (formula-visual-transform visual)))
   (define (visual-with-position visual position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (copy-tagged-formula-fragment
      visual
      (formula-visual-id visual)
      (affine-transform-with-translation
       (formula-visual-transform visual)
       position)
      (formula-visual-opacity visual)))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (formula-visual-transform visual))
   (define (visual-with-transform visual transform)
     (unless (affine-transform? transform)
       (raise-argument-error
        'visual-with-transform
        "affine-transform?"
        transform))
     (copy-tagged-formula-fragment
      visual
      (formula-visual-id visual)
      transform
      (formula-visual-opacity visual)))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (formula-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (unless (opacity? opacity)
       (raise-argument-error
        'visual-with-opacity
        "finite real in [0, 1]"
        opacity))
     (copy-tagged-formula-fragment
      visual
      (formula-visual-id visual)
      (formula-visual-transform visual)
      opacity))]
  #:methods gen:formula-identity-visual
  [(define (generic-formula-visual-with-id visual id)
     (unless (symbol? id)
       (raise-argument-error 'formula-visual-with-id "symbol?" id))
     (copy-tagged-formula-fragment
      visual
      id
      (formula-visual-transform visual)
      (formula-visual-opacity visual)))]
  #:methods gen:write-path-source
  [(define (write-path-source->visual visual)
     (tagged-formula-fragment->write-proxy visual))])

(define (copy-tagged-formula-fragment visual id transform opacity)
  (tagged-formula-fragment-visual
   id
   transform
   opacity
   (formula-visual-source visual)
   (formula-visual-mode visual)
   (formula-visual-font-size visual)
   (formula-visual-preamble visual)
   (formula-visual-document-class-options visual)
   (formula-visual-preview-options visual)
   (formula-visual-horizontal-alignment visual)
   (formula-visual-vertical-alignment visual)
   (tagged-formula-fragment-visual-svg-source visual)))

;; tagged-formula-fragment->write-proxy : tagged-formula-fragment-visual?
;;                                            -> group-visual?
;; Expands dvisvgm's reusable glyph paths once when a write animation is
;; compiled.  The source fragment remains the exact endpoint; this proxy only
;; exists for animated outline/fill sampling, so no TeX process runs per frame.
(define (tagged-formula-fragment->write-proxy visual)
  (define world-per-pict-unit
    (/ (formula-visual-font-size visual)
       (formula-visual-document-font-points visual)))
  (define local-glyphs
    (svg-string->write-path-visuals
     (tagged-formula-fragment-visual-svg-source visual)
     (formula-visual-id visual)
     world-per-pict-unit))
  ;; A group has uniform scale by design, while individual formula fragments
  ;; may use nonuniform scale.  Keep the wrapper neutral and carry the complete
  ;; fragment transform on each generated glyph path instead.
  (group
   (for/list ([glyph (in-list local-glyphs)])
     (visual-with-transform glyph (visual-transform visual)))
   #:id (formula-visual-id visual)
   #:opacity (formula-visual-opacity visual)))


;;; Public Construction

; tagged-formula : #:id symbol?
;                  [#:center vec2?]
;                  [#:rotation finite-real?]
;                  [#:scale scale-factor?]
;                  [#:opacity opacity?]
;                  [#:mode formula-mode?]
;                  [#:font-size positive-real?]
;                  [#:preamble string?]
;                  [#:document-class-options (listof latex-option?)]
;                  formula-fragment? ...
;                  -> formula-assembly-visual?
;; Typesets all fragments together once. The returned assembly has the given
;; id; its local part names are the formula-fragment names. The constructor
;; requires the external latex and dvisvgm executables only at construction.
(define (tagged-formula #:id id
                        #:center [center origin]
                        #:rotation [rotation 0]
                        #:scale [scale 1]
                        #:opacity [opacity 1]
                        #:mode [mode 'display]
                        #:font-size [font-size 1]
                        #:preamble [preamble ""]
                        #:document-class-options
                        [document-class-options '()]
                        . fragments)
  (check-fragment-list 'tagged-formula fragments)
  ;; Reuse latex-formula's option and transform validation before starting an
  ;; external compiler process. The resulting base visual snapshots caller data.
  (define base
    (latex-formula
     (apply string-append (map formula-fragment-source fragments))
     #:id id
     #:center center
     #:rotation rotation
     #:scale scale
     #:opacity opacity
     #:mode mode
     #:font-size font-size
     #:preamble preamble
     #:document-class-options document-class-options))
  (define artifact
    (compile-tagged-formula-svg
     'tagged-formula
     fragments
     (formula-visual-mode base)
     (formula-visual-preamble base)
     (formula-visual-document-class-options base)))
  (define full-pict (svg-string->pict artifact))
  (define full-width (pict-width full-pict))
  (define full-height (pict-height full-pict))
  (unless (and (positive? full-width)
               (positive? full-height))
    (error 'tagged-formula "dvisvgm produced an SVG with nonpositive dimensions"))
  (define values-per-pict-x
    (/ (view-box-width artifact full-width) full-width))
  (define values-per-pict-y
    (/ (view-box-height artifact full-height) full-height))
  (define world-per-pict-unit
    (/ (formula-visual-font-size base)
       (formula-visual-document-font-points base)))
  (define parts
    (for/list ([fragment (in-list fragments)]
               [index (in-naturals)])
      (define isolated
        (svg-with-visible-fragment artifact index))
      (define bounds
        (visible-pict-bounds 'tagged-formula (svg-string->pict isolated)))
      (define left (list-ref bounds 0))
      (define top (list-ref bounds 1))
      (define width (list-ref bounds 2))
      (define height (list-ref bounds 3))
      ;; Preserve the full formula's SVG coordinate scale while tightly framing
      ;; one group. The fragment can then be placed by its measured center.
      (define cropped
        (svg-with-visible-fragment artifact
                                   index
                                   #:view-box
                                   (list (+ (view-box-x artifact)
                                            (* left values-per-pict-x))
                                         (+ (view-box-y artifact)
                                            (* top values-per-pict-y))
                                         (* width values-per-pict-x)
                                         (* height values-per-pict-y))
                                   #:width width
                                   #:height height))
      (define local-center
        (vec2 (* (- (+ left (/ width 2)) (/ full-width 2))
                 world-per-pict-unit)
              (* (- (/ full-height 2) (+ top (/ height 2)))
                 world-per-pict-unit)))
      (formula-part
       (formula-fragment-name fragment)
       (make-tagged-fragment-visual
        base
        (formula-fragment-name fragment)
        (formula-fragment-source fragment)
        local-center
        cropped))))
  (formula-assembly parts
                    #:id id
                    #:center center
                    #:rotation rotation
                    #:scale scale
                    #:opacity opacity))


;;; Manim-Style Formula Convenience

; math-tex : #:id symbol?
;            [#:center vec2?]
;            [#:rotation finite-real?]
;            [#:scale scale-factor?]
;            [#:opacity opacity?]
;            [#:mode formula-mode?]
;            [#:font-size positive-real?]
;            [#:preamble string?]
;            [#:document-class-options (listof latex-option?)]
;            string? ...
;            -> formula-assembly-visual?
;; Typesets a complete TeX formula while using Manim-style `{{ ... }}` groups
;; to declare matchable fragments. Text between those groups is matchable too.
;; This is shorthand for tagged-formula; use tagged-formula directly when
;; repeated terms need stable, author-chosen identities.
(define (math-tex #:id id
                  #:center [center origin]
                  #:rotation [rotation 0]
                  #:scale [scale 1]
                  #:opacity [opacity 1]
                  #:mode [mode 'display]
                  #:font-size [font-size 1]
                  #:preamble [preamble ""]
                  #:document-class-options
                  [document-class-options '()]
                  . tex-strings)
  (unless (and (pair? tex-strings)
               (andmap string? tex-strings))
    (raise-argument-error 'math-tex "nonempty list of strings" tex-strings))
  (define fragments
    (for/list ([source (in-list (math-tex-split (string-join tex-strings " ")))]
               [index (in-naturals)])
      (formula-fragment
       (string->symbol (format "math-tex-part-~a" index))
       source)))
  (unless (pair? fragments)
    (raise-arguments-error
     'math-tex
     "at least one `{{ ... }}` group or ordinary TeX fragment with visible ink"
     "tex-strings" tex-strings))
  (apply tagged-formula
         #:id id
         #:center center
         #:rotation rotation
         #:scale scale
         #:opacity opacity
         #:mode mode
         #:font-size font-size
         #:preamble preamble
         #:document-class-options document-class-options
         fragments))

;; math-tex-split : string? -> (listof nonempty-string?)
;; Splits Manim's double-brace form wherever it occurs. Nested TeX braces and
;; escaped braces are retained inside a group. Whitespace-only pieces cannot
;; be rendered as formula fragments.
(define (math-tex-split source)
  (define length (string-length source))
  (define pieces-reversed '())
  (define output (open-output-string))
  (define (emit-current!)
    (define piece (string-trim (get-output-string output)))
    (unless (string=? piece "")
      (set! pieces-reversed (cons piece pieces-reversed)))
    (set! output (open-output-string)))
  (define (starts-with? index text)
    (and (<= (+ index (string-length text)) length)
         (string=? (substring source index (+ index (string-length text)))
                   text)))
  (let loop ([index 0] [inside-group? #f] [brace-depth 0])
    (cond
      [(= index length)
       (when inside-group?
         (raise-arguments-error
          'math-tex
          "balanced Manim-style `{{ ... }}` groups"
          "source" source))
       (emit-current!)
       (reverse pieces-reversed)]
      [else
       (define character (string-ref source index))
       ;; Treat an escaped brace/backslash as literal TeX input. The two
       ;; characters must stay together so `\\}}` cannot terminate a group.
       (cond
         [(and (char=? character #\\)
               (< (add1 index) length)
               (let ([next (string-ref source (add1 index))])
                 (or (char=? next #\\)
                     (char=? next #\{)
                     (char=? next #\}))))
          (write-char character output)
          (write-char (string-ref source (add1 index)) output)
         (loop (+ index 2) inside-group? brace-depth)]
         [(not inside-group?)
          (if (starts-with? index "{{")
              (begin
                (emit-current!)
                (loop (+ index 2) #t 0))
              (begin
                (write-char character output)
                (loop (add1 index) #f 0)))]
         [(char=? character #\{)
          (write-char character output)
          (loop (add1 index) #t (add1 brace-depth))]
         [(and (char=? character #\})
               (zero? brace-depth)
               (starts-with? index "}}"))
          (emit-current!)
          (loop (+ index 2) #f 0)]
         [(char=? character #\})
          (write-char character output)
          (loop (add1 index) #t (sub1 brace-depth))]
         [else
          (write-char character output)
          (loop (add1 index) #t brace-depth)])])))

; transform-matching-formula : formula-assembly-visual?
;                              formula-assembly-visual?
;                              [#:matches (listof formula-part-match?)]
;                              -> transform-formula-parts-request?
;; Produces a Manim-like transition. Explicit matches take priority; all
;; remaining rendering-equivalent fragments are then paired in source order.
(define (transform-matching-formula source destination #:matches [matches '()])
  (unless (formula-assembly-visual? source)
    (raise-argument-error
     'transform-matching-formula
     "formula-assembly-visual?"
     source))
  (unless (formula-assembly-visual? destination)
    (raise-argument-error
     'transform-matching-formula
     "formula-assembly-visual?"
     destination))
  ;; formula-correspondence validates the explicit one-to-one part map.
  (define explicit
    (formula-correspondence source destination matches))
  (define explicit-source
    (for/hash ([match (in-list matches)])
      (values (formula-part-match-source-name match) #t)))
  (define explicit-destination
    (for/hash ([match (in-list matches)])
      (values (formula-part-match-destination-name match) #t)))
  (define automatic
    (formula-correspondence-auto source destination))
  (define remaining-auto
    (filter
     (lambda (match)
       (and (not (hash-has-key? explicit-source
                                (formula-part-match-source-name match)))
            (not (hash-has-key? explicit-destination
                                (formula-part-match-destination-name match)))))
     (formula-correspondence-matches automatic)))
  (transform-formula-parts
   (formula-correspondence
    source
    destination
    (append (formula-correspondence-matches explicit) remaining-auto))))

; transform-matching-tex : formula-assembly-visual? formula-assembly-visual?
;                          [#:key-map (hash/c string? string?)]
;                          -> transform-formula-parts-request?
;; A Manim-style shorthand for transitions between math-tex formulas. Exact
;; TeX fragments match automatically. `key-map` explicitly pairs every
;; source occurrence of one mapped string with the first available destination
;; occurrence of its mapped string. Key-map pairs take priority over automatic
;; matches; named tagged-formulas remain the precise option when duplicate
;; occurrences need individual control.
(define (transform-matching-tex source destination #:key-map [key-map (hash)])
  (unless (formula-assembly-visual? source)
    (raise-argument-error
     'transform-matching-tex
     "formula-assembly-visual?"
     source))
  (unless (formula-assembly-visual? destination)
    (raise-argument-error
     'transform-matching-tex
     "formula-assembly-visual?"
     destination))
  (check-tex-key-map key-map)
  ;; Key-map pairs are deliberate overrides, analogous to Manim's key_map.
  ;; Match them before exact-text pairing so a caller can redirect a source
  ;; fragment even if an identical target fragment also exists.
  (define-values (mapped-reversed used-source used-destination)
    (for/fold ([matches '()]
               [source-used (hash)]
               [destination-used (hash)])
              ([source-part (in-list (formula-assembly-visual-parts source))])
      (define source-name (formula-part-name source-part))
      (define mapped-source
        (formula-visual-source (formula-part-formula source-part)))
      (define destination-source
        (hash-ref key-map mapped-source #f))
      (define destination-part
        (and destination-source
             (for/first ([candidate
                          (in-list (formula-assembly-visual-parts destination))]
                         #:unless (hash-has-key? destination-used
                                                  (formula-part-name candidate))
                         #:when (string=? destination-source
                                          (formula-visual-source
                                           (formula-part-formula candidate))))
               candidate)))
      (if destination-part
          (values
           (cons (formula-part-match source-name
                                     (formula-part-name destination-part))
                 matches)
           (hash-set source-used source-name #t)
           (hash-set destination-used (formula-part-name destination-part) #t))
          (values matches source-used destination-used))))
  (define automatic
    (formula-correspondence-auto source destination))
  (define automatic-remaining
    (filter
     (lambda (match)
       (and (not (hash-has-key? used-source
                                (formula-part-match-source-name match)))
            (not (hash-has-key? used-destination
                                (formula-part-match-destination-name match)))))
     (formula-correspondence-matches automatic)))
  (transform-formula-parts
   (formula-correspondence
    source
    destination
    (append (reverse mapped-reversed) automatic-remaining))))

(define (check-tex-key-map key-map)
  (unless (hash? key-map)
    (raise-argument-error 'transform-matching-tex "hash?" key-map))
  (for ([(source destination) (in-hash key-map)])
    (unless (string? source)
      (raise-arguments-error
       'transform-matching-tex
       "a hash mapping TeX source strings to TeX source strings"
       "key" source
       "value" destination))
    (unless (string? destination)
      (raise-arguments-error
       'transform-matching-tex
       "a hash mapping TeX source strings to TeX source strings"
       "key" source
       "value" destination))))


;;; SVG Compilation

(define (compile-tagged-formula-svg who fragments mode preamble options)
  (define latex (find-executable-path "latex"))
  (unless latex
    (error who "tagged formulas require a LaTeX installation with the `latex` executable"))
  (define dvisvgm (find-executable-path "dvisvgm"))
  (unless dvisvgm
    (error who "tagged formulas require the `dvisvgm` executable"))
  (define directory
    (make-temporary-file "animate-tagged-formula~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define tex-file (build-path directory "formula.tex"))
     (define dvi-file (build-path directory "formula.dvi"))
     (call-with-output-file
      tex-file
      (lambda (output)
        (display (tagged-formula-document fragments mode preamble options)
                 output))
      #:exists 'truncate/replace)
     (run-external-command
      who
      latex
      (list "-interaction=batchmode"
            "-halt-on-error"
            (string-append "-output-directory=" (path->string directory))
            (path->string tex-file))
      "LaTeX compilation")
     (unless (file-exists? dvi-file)
       (error who "LaTeX completed without producing a DVI file"))
     (run-external-command/output
      who
      dvisvgm
      (list (path->string dvi-file) "-n" "-v" "0" "--stdout")
      "dvisvgm conversion"))
   (lambda ()
     (when (directory-exists? directory)
       (delete-directory/files directory)))))

(define (tagged-formula-document fragments mode preamble options)
  (define option-text
    (string-join
     (cons "preview"
           (for/list ([option (in-list options)])
             (if (symbol? option) (symbol->string option) option)))
     ","))
  (string-append
   "\\documentclass[" option-text "]{standalone}\n"
   preamble "\n"
   "\\begin{document}\n"
   (case mode
     [(inline) "\\("]
     [(display) "\\(\\displaystyle "]
     [(display-environment) "\\["]
     [else (error 'tagged-formula "unsupported formula mode: ~e" mode)])
   (apply
    string-append
    (for/list ([fragment (in-list fragments)]
               [index (in-naturals)])
      (string-append
       "\\special{dvisvgm:raw <g id=\"animate-fragment-"
       (number->string index)
       "\">}"
       (formula-fragment-source fragment)
       "\\special{dvisvgm:raw </g>}")))
   (case mode
     [(inline display) "\\)\n"]
     [(display-environment) "\\]\n"])
   "\\end{document}\n"))

(define (run-external-command who executable arguments phase)
  (run-external-command/output who executable arguments phase)
  (void))

(define (run-external-command/output who executable arguments phase)
  (define-values (process stdout stdin stderr)
    (apply subprocess #f #f #f executable arguments))
  (close-output-port stdin)
  ;; Drain both pipes concurrently. A TeX error can otherwise fill stderr while
  ;; dvisvgm is writing SVG to stdout, leaving either child process blocked.
  (define stdout-result (box #f))
  (define stderr-result (box #f))
  (define stdout-reader
    (thread
     (lambda ()
       (set-box! stdout-result (port->string stdout)))))
  (define stderr-reader
    (thread
     (lambda ()
       (set-box! stderr-result (port->string stderr)))))
  (subprocess-wait process)
  (thread-wait stdout-reader)
  (thread-wait stderr-reader)
  (define stdout-text (unbox stdout-result))
  (define stderr-text (unbox stderr-result))
  (unless (zero? (subprocess-status process))
    (error who
           "~a failed\n~a\n~a"
           phase
           stdout-text
           stderr-text))
  stdout-text)


;;; SVG Fragment Isolation and Measurement

(define (svg-with-visible-fragment source index
                                   #:view-box [view-box #f]
                                   #:width [width #f]
                                   #:height [height #f])
  (define selected-id
    (string-append "animate-fragment-" (number->string index)))
  (define source-pict (svg-string->pict source))
  (define actual-view-box
    (or view-box
        (list (view-box-x source)
              (view-box-y source)
              (view-box-width source (pict-width source-pict))
              (view-box-height source (pict-height source-pict)))))
  (define actual-width (or width (pict-width source-pict)))
  (define actual-height (or height (pict-height source-pict)))
  (define root
    (string-append
     "<svg xmlns=\"http://www.w3.org/2000/svg\" "
     "xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\""
     (number->string actual-width)
     "\" height=\""
     (number->string actual-height)
     "\" viewBox=\""
     (string-join (map number->string actual-view-box) " ")
     "\">\n<style>g[id^=\"animate-fragment-\"]{opacity:0}#"
     selected-id
     "{opacity:1}</style>"))
  (regexp-replace #px"<svg\\b[^>]*>" source root))

(define (visible-pict-bounds who source)
  (define bitmap (pict->bitmap source))
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define pixels (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height pixels)
  (define-values (left top right bottom)
    (for*/fold ([left width]
                [top height]
                [right -1]
                [bottom -1])
               ([y (in-range height)]
                [x (in-range width)])
      (if (positive? (bytes-ref pixels (* 4 (+ x (* y width)))))
          (values (min left x)
                  (min top y)
                  (max right x)
                  (max bottom y))
          (values left top right bottom))))
  (when (= right -1)
    (error who "a tagged formula fragment has no visible ink"))
  ;; One pixel of padding keeps antialiased edge pixels inside the cropped SVG.
  (define padded-left (max 0 (sub1 left)))
  (define padded-top (max 0 (sub1 top)))
  (define padded-right (min width (+ right 2)))
  (define padded-bottom (min height (+ bottom 2)))
  (list padded-left
        padded-top
        (- padded-right padded-left)
        (- padded-bottom padded-top)))

(define (view-box-values source fallback-width fallback-height)
  (define matched
    (regexp-match #px"viewBox\\s*=\\s*['\"]([^'\"]+)['\"]" source))
  (if matched
      (let ([values
             (for/list ([token
                         (in-list
                          (regexp-match*
                           #px"[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?"
                           (cadr matched)))])
               (string->number token))])
        (if (= (length values) 4)
            values
            (list 0 0 fallback-width fallback-height)))
      (list 0 0 fallback-width fallback-height)))

(define (view-box-x source)
  (list-ref (view-box-values source 1 1) 0))

(define (view-box-y source)
  (list-ref (view-box-values source 1 1) 1))

(define (view-box-width source fallback)
  (list-ref (view-box-values source fallback 1) 2))

(define (view-box-height source fallback)
  (list-ref (view-box-values source 1 fallback) 3))


;;; Construction Helpers

(define (make-tagged-fragment-visual base name source center svg-source)
  (define ordinary
    (latex-formula
     source
     #:id name
     #:center center
     #:mode (formula-visual-mode base)
     #:font-size (formula-visual-font-size base)
     #:preamble (formula-visual-preamble base)
     #:document-class-options
     (formula-visual-document-class-options base)))
  (tagged-formula-fragment-visual
   (formula-visual-id ordinary)
   (formula-visual-transform ordinary)
   (formula-visual-opacity ordinary)
   (formula-visual-source ordinary)
   (formula-visual-mode ordinary)
   (formula-visual-font-size ordinary)
   (formula-visual-preamble ordinary)
   (formula-visual-document-class-options ordinary)
   (formula-visual-preview-options ordinary)
   (formula-visual-horizontal-alignment ordinary)
   (formula-visual-vertical-alignment ordinary)
   (string->immutable-string svg-source)))

(define (check-fragment-list who fragments)
  (unless (and (pair? fragments)
               (andmap formula-fragment? fragments))
    (raise-argument-error who "nonempty list of formula-fragment values" fragments))
  (define seen (make-hash))
  (for ([fragment (in-list fragments)])
    (define name (formula-fragment-name fragment))
    (when (hash-has-key? seen name)
      (raise-arguments-error
       who
       "formula fragment names must be unique"
       "duplicate fragment name"
       name))
    (hash-set! seen name #t)))
