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
         "formula-part-transition.rkt"
         "formula-parts-visual.rkt"
         "formula-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "path-geometry.rkt"
         "svg-write-paths.rkt"
         "write-in-adapter.rkt"
         "visual-model.rkt")

(provide (struct-out formula-fragment)
         tagged-formula
         math-tex
         glyph-tex
         tagged-formula-fragment-visual?
         tagged-formula-fragment-visual-svg-source
         transform-matching-formula
         transform-matching-glyphs
         rewrite-formula
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
(struct tagged-formula-fragment-visual formula-visual (svg-source glyph-key)
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
  #:methods gen:formula-rendering-key
  [(define (generic-formula-rendering-key visual)
     (define glyph-key
       (tagged-formula-fragment-visual-glyph-key visual))
     (if glyph-key
         (list 'dvisvgm-glyph
               glyph-key
               (formula-visual-mode visual)
               (formula-visual-font-size visual)
               (formula-visual-preamble visual)
               (formula-visual-document-class-options visual)
               (formula-visual-preview-options visual)
               (formula-visual-horizontal-alignment visual)
               (formula-visual-vertical-alignment visual))
         (formula-visual-default-rendering-key visual)))]
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
   (tagged-formula-fragment-visual-svg-source visual)
   (tagged-formula-fragment-visual-glyph-key visual)))

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

; glyph-tex : #:id symbol?
;             [#:center vec2?]
;             [#:rotation finite-real?]
;             [#:scale scale-factor?]
;             [#:opacity opacity?]
;             [#:mode formula-mode?]
;             [#:font-size positive-real?]
;             [#:preamble string?]
;             [#:document-class-options (listof latex-option?)]
;             string? ...
;             -> formula-assembly-visual?
;; Typesets one complete TeX expression and exposes each dvisvgm glyph leaf as
;; a formula part named `glyph-0`, `glyph-1`, and so on.  Glyphs with the same
;; rendered outline automatically match across separate expressions; explicit
;; tags remain the better abstraction when several glyphs form one term.
(define (glyph-tex #:id id
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
    (raise-argument-error 'glyph-tex "nonempty list of strings" tex-strings))
  (define source
    (string-join tex-strings " "))
  ;; Reuse latex-formula's option and transform validation before invoking the
  ;; external compiler. Its source remains the complete user expression; glyph
  ;; matching uses a separate dvisvgm outline key.
  (define base
    (latex-formula
     source
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
     'glyph-tex
     (list (formula-fragment 'glyph-source source))
     (formula-visual-mode base)
     (formula-visual-preamble base)
     (formula-visual-document-class-options base)))
  (define glyph-count
    (svg-glyph-count artifact))
  (unless (positive? glyph-count)
    (error 'glyph-tex "dvisvgm produced no visible glyph leaves"))
  (define full-pict
    (svg-string->pict artifact))
  (define full-width
    (pict-width full-pict))
  (define full-height
    (pict-height full-pict))
  (unless (and (positive? full-width)
               (positive? full-height))
    (error 'glyph-tex "dvisvgm produced an SVG with nonpositive dimensions"))
  (define values-per-pict-x
    (/ (view-box-width artifact full-width) full-width))
  (define values-per-pict-y
    (/ (view-box-height artifact full-height) full-height))
  (define world-per-pict-unit
    (/ (formula-visual-font-size base)
       (formula-visual-document-font-points base)))
  (define parts
    (for/list ([index (in-range glyph-count)])
      (define isolated
        (svg-with-visible-glyph artifact index))
      (define bounds
        (visible-pict-bounds 'glyph-tex (svg-string->pict isolated)))
      (define left (list-ref bounds 0))
      (define top (list-ref bounds 1))
      (define width (list-ref bounds 2))
      (define height (list-ref bounds 3))
      (define cropped
        (svg-with-visible-glyph artifact
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
      (define name
        (string->symbol (format "glyph-~a" index)))
      (formula-part
       name
       (make-tagged-fragment-visual
        base
        name
        source
        local-center
        cropped
        #:glyph-key (svg-glyph-key artifact index)))))
  (formula-assembly parts
                    #:id id
                    #:center center
                    #:rotation rotation
                    #:scale scale
                    #:opacity opacity))

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
;                              [#:path-arc finite-real?]
;                              [#:part-paths (listof formula-part-path?)]
;                              [#:copies (listof formula-part-copy?)]
;                              [#:mismatch-mode (or/c 'fade 'fade-transform)]
;                              -> transform-formula-parts-request?
;; Produces a Manim-like transition. Explicit matches take priority; all
;; remaining rendering-equivalent fragments are then paired in source order.
;; `path-arc` is the default route, with `part-paths` as precise overrides.
;; `copies` preserve a source part while directing transient copies to
;; otherwise unmatched destinations. `mismatch-mode` controls the rest.
(define (transform-matching-formula source destination
                                    #:matches [matches '()]
                                    #:path-arc [path-arc 0]
                                    #:part-paths [part-paths '()]
                                    #:copies [copies '()]
                                    #:mismatch-mode [mismatch-mode 'fade])
  (transform-formula-parts
   (make-matching-formula-correspondence
    'transform-matching-formula source destination matches)
   #:path-arc path-arc
   #:part-paths part-paths
   #:copies copies
   #:mismatch-mode mismatch-mode))

; transform-matching-glyphs : formula-assembly-visual?
;                            formula-assembly-visual?
;                            [#:matches (listof formula-part-match?)]
;                            [#:path-arc finite-real?]
;                            [#:part-paths (listof formula-part-path?)]
;                            [#:copies (listof formula-part-copy?)]
;                            [#:mismatch-mode (or/c 'fade 'fade-transform)]
;                            [#:changed-mode (or/c 'fade 'morph)]
;                            -> transform-formula-parts-request?
;; Produces automatic rendered-glyph matching between two glyph-tex values.
;; Explicit matches remain available for an intentional changed glyph, such as
;; a plus sign becoming a minus sign. `morph` replaces conservative compatible
;; changed-glyph interiors with outline interpolation; it falls back to the
;; normal moving cross-fade when a glyph has several contours or styles differ.
(define (transform-matching-glyphs source destination
                                   #:matches [matches '()]
                                   #:path-arc [path-arc 0]
                                   #:part-paths [part-paths '()]
                                   #:copies [copies '()]
                                   #:mismatch-mode [mismatch-mode 'fade]
                                   #:changed-mode [changed-mode 'fade])
  (check-glyph-assembly 'transform-matching-glyphs source)
  (check-glyph-assembly 'transform-matching-glyphs destination)
  (unless (memq changed-mode '(fade morph))
    (raise-argument-error
     'transform-matching-glyphs
     "(or/c 'fade 'morph)"
     changed-mode))
  (define correspondence
    (make-matching-formula-correspondence
     'transform-matching-glyphs source destination matches))
  (transform-formula-parts
   correspondence
   #:path-arc path-arc
   #:part-paths part-paths
   #:copies copies
   #:mismatch-mode mismatch-mode
   #:outline-morphs
   (if (eq? changed-mode 'morph)
       (glyph-outline-morphs source correspondence)
       '())))

; rewrite-formula : formula-assembly-visual? formula-assembly-visual?
;                   #:anchor (or/c symbol? formula-part-match?)
;                   [#:matches (listof formula-part-match?)]
;                   [#:stationary (listof (or/c symbol? formula-part-match?))]
;                   [#:path-arc finite-real?]
;                   [#:part-paths (listof formula-part-path?)]
;                   [#:copies (listof formula-part-copy?)]
;                   [#:mismatch-mode (or/c 'fade 'fade-transform)]
;                   -> transform-formula-parts-request?
;;   Builds a matching formula rewrite whose named anchor stays at its current
;;   position, even when an earlier rewrite has already repositioned the scene.
;;   `stationary` names additional matched fragments that keep their current
;;   individual transforms instead of being moved by the destination layout.
(define (rewrite-formula source destination
                         #:anchor anchor
                         #:matches [matches '()]
                         #:stationary [stationary '()]
                         #:path-arc [path-arc 0]
                         #:part-paths [part-paths '()]
                         #:copies [copies '()]
                         #:mismatch-mode [mismatch-mode 'fade])
  (define anchor-match
    (rewrite-anchor->match anchor))
  (define stationary-matches
    (rewrite-stationary->matches stationary))
  (define correspondence
    (make-matching-formula-correspondence
     'rewrite-formula
     source
     destination
     (add-rewrite-required-matches
      source destination matches (cons anchor-match stationary-matches))))
  (transform-formula-parts/anchored
   correspondence
   anchor-match
   #:path-arc path-arc
   #:part-paths part-paths
   #:copies copies
   #:stationary stationary-matches
   #:mismatch-mode mismatch-mode))

; make-matching-formula-correspondence : symbol? formula-assembly-visual?
;                                        formula-assembly-visual?
;                                        (listof formula-part-match?)
;                                        -> formula-correspondence?
;;   Combines explicit priority matches with deterministic remaining matches.
(define (make-matching-formula-correspondence who source destination matches)
  (unless (formula-assembly-visual? source)
    (raise-argument-error
     who
     "formula-assembly-visual?"
     source))
  (unless (formula-assembly-visual? destination)
    (raise-argument-error
     who
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
  (formula-correspondence
   source
   destination
   (append (formula-correspondence-matches explicit) remaining-auto)))

; rewrite-anchor->match : (or/c symbol? formula-part-match?) -> formula-part-match?
;;   Interprets a symbol as an identically named source/destination anchor.
(define (rewrite-anchor->match anchor)
  (cond
    [(symbol? anchor) (formula-part-match anchor anchor)]
    [(formula-part-match? anchor) anchor]
    [else
     (raise-argument-error
      'rewrite-formula
      "(or/c symbol? formula-part-match?)"
     anchor)]))

; rewrite-stationary->matches : list? -> (listof formula-part-match?)
;; Converts the convenient same-name stationary shorthand before the full
;; correspondence validates names and one-to-one use against both formulas.
(define (rewrite-stationary->matches stationary)
  (unless (list? stationary)
    (raise-argument-error
     'rewrite-formula
     "(listof (or/c symbol? formula-part-match?))"
     stationary))
  (for/list ([entry (in-list stationary)])
    (cond
      [(symbol? entry) (formula-part-match entry entry)]
      [(formula-part-match? entry) entry]
      [else
       (raise-argument-error
        'rewrite-formula
        "(listof (or/c symbol? formula-part-match?))"
        stationary)])))

; add-rewrite-anchor-match : formula-assembly-visual? formula-assembly-visual?
;                            (listof formula-part-match?) formula-part-match?
;                            -> (listof formula-part-match?)
;;   Makes the anchored pair explicit, rejecting a conflicting caller match.
(define (add-rewrite-required-matches source destination matches required)
  (for/fold ([result matches])
            ([match (in-list required)])
    (add-rewrite-required-match source destination result match)))

; add-rewrite-required-match : formula-assembly-visual? formula-assembly-visual?
;                              (listof formula-part-match?) formula-part-match?
;                              -> (listof formula-part-match?)
;; Makes a required anchored or stationary pair explicit, rejecting conflicts.
(define (add-rewrite-required-match source destination matches anchor)
  ;; This first correspondence validates the list and all named parts before
  ;; inspecting individual match fields below.
  (formula-correspondence source destination matches)
  (define source-name (formula-part-match-source-name anchor))
  (define destination-name (formula-part-match-destination-name anchor))
  (define overlapping
    (for/first ([match (in-list matches)]
                #:when (or (eq? source-name
                                (formula-part-match-source-name match))
                           (eq? destination-name
                                (formula-part-match-destination-name match))))
      match))
  (cond
    [(not overlapping) (append matches (list anchor))]
    [(and (eq? source-name
               (formula-part-match-source-name overlapping))
          (eq? destination-name
               (formula-part-match-destination-name overlapping)))
     matches]
    [else
     (raise-arguments-error
     'rewrite-formula
     "an anchor or stationary part that does not conflict with an explicit match"
     "required-match" anchor
     "match" overlapping)]))

; transform-matching-tex : formula-assembly-visual? formula-assembly-visual?
;                          [#:key-map (hash/c string? string?)]
;                          [#:path-arc finite-real?]
;                          [#:path-map (hash/c (cons/c string? string?) formula-route?)]
;                          [#:mismatch-mode (or/c 'fade 'fade-transform)]
;                          -> transform-formula-parts-request?
;; A Manim-style shorthand for transitions between math-tex formulas. Exact
;; TeX fragments match automatically. `key-map` explicitly pairs every
;; source occurrence of one mapped string with the first available destination
;; occurrence of its mapped string. Key-map pairs take priority over automatic
;; matches. `path-arc` sets the default circular route; `path-map` selects
;; routes by (cons source-TeX destination-TeX). Named tagged-formulas remain
;; the precise option when duplicate occurrences need individual control.
;; `mismatch-mode` can turn remaining unmatched pieces into moving cross-fades.
(define (transform-matching-tex source destination
                                #:key-map [key-map (hash)]
                                #:path-arc [path-arc 0]
                                #:path-map [path-map (hash)]
                                #:mismatch-mode [mismatch-mode 'fade])
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
  (check-tex-path-map path-map)
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
  (define correspondence
    (formula-correspondence
     source
     destination
     (append (reverse mapped-reversed) automatic-remaining)))
  (transform-formula-parts
   correspondence
   #:path-arc path-arc
   #:part-paths (tex-path-map->part-paths correspondence path-map)
   #:mismatch-mode mismatch-mode))

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

(define (check-tex-path-map path-map)
  (unless (hash? path-map)
    (raise-argument-error 'transform-matching-tex "hash?" path-map))
  (for ([(key route) (in-hash path-map)])
    (unless (and (pair? key)
                 (string? (car key))
                 (string? (cdr key)))
      (raise-arguments-error
       'transform-matching-tex
       "a hash mapping (cons TeX-source TeX-source) pairs to formula routes"
       "key" key
       "value" route))
    (unless (formula-route? route)
      (raise-arguments-error
       'transform-matching-tex
       "a hash mapping (cons TeX-source TeX-source) pairs to formula routes"
       "key" key
       "value" route))))

(define (tex-path-map->part-paths correspondence path-map)
  (reverse
   (for/fold ([result '()])
             ([match (in-list (formula-correspondence-matches correspondence))])
     (define source-part
       (formula-assembly-visual-ref
        (formula-correspondence-source correspondence)
        (formula-part-match-source-name match)))
     (define destination-part
       (formula-assembly-visual-ref
        (formula-correspondence-destination correspondence)
        (formula-part-match-destination-name match)))
     (define route
       (hash-ref
        path-map
        (cons (formula-visual-source (formula-part-formula source-part))
              (formula-visual-source (formula-part-formula destination-part)))
        #f))
     (if route
         (cons
          (formula-part-path
           (formula-part-match-source-name match)
           (formula-part-match-destination-name match)
           route)
          result)
         result))))


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

; svg-glyph-count : string? -> exact-nonnegative-integer?
;;   Counts dvisvgm glyph leaves, which are represented by visible <use> tags.
(define (svg-glyph-count source)
  (length (svg-glyph-use-elements source)))

; svg-glyph-key : string? exact-nonnegative-integer? -> immutable-string?
;;   Returns a rendered dvisvgm outline identity for one visible glyph leaf.
;;   dvisvgm numbers font definitions per compilation, so the stable key is the
;; referenced path geometry rather than the local definition id.
(define (svg-glyph-key source index)
  (define uses
    (svg-glyph-use-elements source))
  (check-glyph-index 'svg-glyph-key index uses)
  (define glyph-use
    (list-ref uses index))
  (define href
    (regexp-match
     #px"(?:xlink:)?href\\s*=\\s*['\"]#([^'\"]+)['\"]"
     glyph-use))
  (unless href
    (raise-arguments-error
     'svg-glyph-key
     "a dvisvgm <use> element with a local href"
     "glyph index" index
     "use" glyph-use))
  (define definition-id
    (cadr href))
  (define path-definition
    (for/first ([path-element
                 (in-list (regexp-match* #px"<path\\b[^>]*>" source))]
                #:when (regexp-match
                        (pregexp
                         (string-append
                          "(?:^|[[:space:]])id\\s*=\\s*['\"]"
                          (regexp-quote definition-id)
                          "['\"]"))
                        path-element))
      path-element))
  (unless path-definition
    (raise-arguments-error
     'svg-glyph-key
     "an SVG <path> definition for the glyph href"
     "glyph index" index
     "href" definition-id))
  (define path-data
    (regexp-match #px"(?:^|[[:space:]])d\\s*=\\s*['\"]([^'\"]+)['\"]"
                  path-definition))
  (unless path-data
    (raise-arguments-error
     'svg-glyph-key
     "an SVG glyph path with d data"
     "glyph index" index
     "path" path-definition))
  (string->immutable-string (cadr path-data)))

; svg-with-visible-glyph : string? exact-nonnegative-integer?
;                          [#:view-box (or/c #f (list/c real? real? real? real?))]
;                          [#:width (or/c #f positive-real?)]
;                          [#:height (or/c #f positive-real?)]
;                          -> string?
;;   Returns an SVG that paints just one dvisvgm glyph leaf from one tagged
;; formula. Each <use> receives a deterministic temporary id before CSS hides
;; all but the selected leaf.
(define (svg-with-visible-glyph source index
                                #:view-box [view-box #f]
                                #:width [width #f]
                                #:height [height #f])
  (define uses
    (svg-glyph-use-elements source))
  (check-glyph-index 'svg-with-visible-glyph index uses)
  (define annotated
    (svg-with-glyph-identifiers source))
  (define source-pict
    (svg-string->pict annotated))
  (define actual-view-box
    (or view-box
        (list (view-box-x annotated)
              (view-box-y annotated)
              (view-box-width annotated (pict-width source-pict))
              (view-box-height annotated (pict-height source-pict)))))
  (define actual-width
    (or width (pict-width source-pict)))
  (define actual-height
    (or height (pict-height source-pict)))
  (define root
    (string-append
     "<svg xmlns=\"http://www.w3.org/2000/svg\" "
     "xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\""
     (number->string actual-width)
     "\" height=\""
     (number->string actual-height)
     "\" viewBox=\""
     (string-join (map number->string actual-view-box) " ")
     "\">\n<style>g[id^=\"animate-fragment-\"]{opacity:0}"
     "#animate-fragment-0{opacity:1}"
     "use[id^=\"animate-glyph-\"]{opacity:0}"
     "#animate-glyph-"
     (number->string index)
     "{opacity:1}</style>"))
  (regexp-replace #px"<svg\\b[^>]*>" annotated root))

; svg-glyph-use-elements : string? -> (listof string?)
;;   Extracts dvisvgm <use> tags in their significant painter order.
(define (svg-glyph-use-elements source)
  (regexp-match* #px"<use\\b[^>]*>" source))

; svg-with-glyph-identifiers : string? -> string?
;;   Adds one private selector id to each dvisvgm glyph use element.
(define (svg-with-glyph-identifiers source)
  (define index 0)
  (regexp-replace*
   #px"<use\\b"
   source
   (lambda (matched)
     (define result
       (string-append
        matched
        " id=\"animate-glyph-"
        (number->string index)
        "\""))
     (set! index (add1 index))
     result)))

; check-glyph-index : symbol? exact-nonnegative-integer? list? -> void?
;;   Validates a glyph index against extracted dvisvgm glyph leaves.
(define (check-glyph-index who index uses)
  (unless (and (exact-nonnegative-integer? index)
               (< index (length uses)))
    (raise-arguments-error
     who
     "a glyph index within the dvisvgm SVG"
     "glyph index" index
     "glyph count" (length uses))))

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

; make-tagged-fragment-visual : formula-visual? symbol? string? vec2? string?
;                                      [#:glyph-key (or/c #f string?)]
;                                      -> tagged-formula-fragment-visual?
;;   Combines a semantic TeX endpoint with an already isolated SVG artifact.
(define (make-tagged-fragment-visual base name source center svg-source
                                     #:glyph-key [glyph-key #f])
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
   (string->immutable-string svg-source)
   (and glyph-key (string->immutable-string glyph-key))))

;; glyph-outline-morphs : formula-assembly-visual? formula-correspondence?
;;                        -> (listof formula-part-outline-morph?)
;; Selects only safe dvisvgm changed-glyph pairs.  The glyph must be represented
;; by one painted SVG path made entirely of positive-length closed contours,
;; with unchanged paint.  Compound contours are globally paired and aligned,
;; but never reversed: that preserves the outer/counter traversal established
;; by dvisvgm.  Open strokes, multiple painted paths, or incompatible contour
;; topology deliberately retain the established moving cross-fade.
(define (glyph-outline-morphs source correspondence)
  (define destination
    (formula-correspondence-destination correspondence))
  (for/fold ([morphs '()])
            ([match (in-list (formula-correspondence-matches correspondence))])
    (define source-name (formula-part-match-source-name match))
    (define destination-name (formula-part-match-destination-name match))
    (define source-formula
      (formula-part-formula
       (formula-assembly-visual-ref source source-name)))
    (define destination-formula
      (formula-part-formula
       (formula-assembly-visual-ref destination destination-name)))
    (define morph
      (and (not (equal? (formula-visual-rendering-key source-formula)
                        (formula-visual-rendering-key destination-formula)))
           (compatible-glyph-outline-morph
            source-name destination-name source-formula destination-formula)))
    (if morph
        (append morphs (list morph))
        morphs)))

;; compatible-glyph-outline-morph : symbol? symbol?
;;                                  tagged-formula-fragment-visual?
;;                                  tagged-formula-fragment-visual?
;;                                  -> (or/c formula-part-outline-morph? #f)
;; Converts both cropped glyph SVG fragments to local vector paths, accepts a
;; compatible collection of closed contours, and normalizes the destination to
;; the source's phase.  Any unsupported SVG/path difference deliberately
;; returns #f so callers retain the established cross-fade instead of receiving
;; a fragile animation.
(define (compatible-glyph-outline-morph source-name destination-name
                                        source-formula destination-formula)
  (with-handlers ([exn:fail? (lambda (_exception) #f)])
    (define source-path-visual
      (tagged-glyph->closed-path-visual source-formula))
    (define destination-path-visual
      (tagged-glyph->closed-path-visual destination-formula))
    (and source-path-visual
         destination-path-visual
         (equal? (path-visual-fill source-path-visual)
                 (path-visual-fill destination-path-visual))
         (equal? (path-visual-stroke source-path-visual)
                 (path-visual-stroke destination-path-visual))
         (= (path-visual-stroke-width source-path-visual)
            (path-visual-stroke-width destination-path-visual))
         (let* ([source-path (path-visual-path source-path-visual)]
                [destination-path (path-visual-path destination-path-visual)]
                [aligned-destination
                 (path-geometry-align-compound-for-morph
                  source-path destination-path #:allow-reverse? #f)])
           (and (compound-contour-windings-match?
                 source-path aligned-destination)
                (let ()
                  (define-values (normalized-source normalized-destination)
                    (path-geometry-normalize-for-morph
                     source-path aligned-destination))
                  (and (path-geometry-morph-compatible?
                        normalized-source normalized-destination)
                       (formula-part-outline-morph
                        source-name
                        destination-name
                        normalized-source
                        normalized-destination
                        (path-visual-fill source-path-visual)
                        (path-visual-stroke source-path-visual)
                        (path-visual-stroke-width source-path-visual)))))))))

;; tagged-glyph->closed-path-visual : tagged-formula-fragment-visual?
;;                                     -> (or/c path-visual? #f)
;; Returns one filled dvisvgm path with one or more closed contours.  A glyph
;; may have an outer contour plus a counter, but it must not need independently
;; painted paths or open-stroke geometry: those cases have no safe compact
;; correspondence rule and stay on the cross-fade fallback.
(define (tagged-glyph->closed-path-visual visual)
  (define world-per-pict-unit
    (/ (formula-visual-font-size visual)
       (formula-visual-document-font-points visual)))
  (define paths
    (svg-string->write-path-visuals
     (tagged-formula-fragment-visual-svg-source visual)
     (formula-visual-id visual)
     world-per-pict-unit))
  (and (= (length paths) 1)
       (let* ([path-visual-value (car paths)]
              [subpaths (path-geometry-subpaths
                         (path-visual-path path-visual-value))])
         (and (pair? subpaths)
              (andmap path-subpath-closed? subpaths)
              path-visual-value))))

(define glyph-outline-winding-sample-count 64)

;; compound-contour-windings-match? : path-geometry? path-geometry? -> boolean?
;; Confirms that every aligned destination contour keeps the source's winding.
;; Alignment itself deliberately disallows reversal; this additional check
;; rejects SVG fragments whose authored traversal conventions differ anyway.
(define (compound-contour-windings-match? source destination)
  (for/and ([source-subpath
             (in-list (path-geometry-subpaths source))]
            [destination-subpath
             (in-list (path-geometry-subpaths destination))])
    (define source-winding
      (closed-subpath-winding source-subpath))
    (define destination-winding
      (closed-subpath-winding destination-subpath))
    (and source-winding
         destination-winding
         (= source-winding
            destination-winding))))

;; closed-subpath-winding : path-subpath? -> (or/c -1 1 #f)
;; Uses deterministic arc-length samples to classify a non-self-intersecting
;; closed contour.  Glyph contours with zero signed area are unsuitable for an
;; interior fill morph and are rejected by the conservative caller.
(define (closed-subpath-winding subpath)
  (define loop
    (path-geometry (list subpath)))
  (define samples
    (for/list ([index (in-range glyph-outline-winding-sample-count)])
      (path-geometry-point-at
       loop
       (/ index glyph-outline-winding-sample-count))))
  (define doubled-area
    (for/sum ([point (in-list samples)]
              [next-point
               (in-list (append (cdr samples) (list (car samples))))])
      (- (* (vec2-x point) (vec2-y next-point))
         (* (vec2-y point) (vec2-x next-point)))))
  (cond [(positive? doubled-area) 1]
        [(negative? doubled-area) -1]
        [else #f]))

; check-glyph-assembly : symbol? any/c -> void?
;;   Requires an assembly whose every part was generated by glyph-tex.
(define (check-glyph-assembly who assembly)
  (unless (formula-assembly-visual? assembly)
    (raise-argument-error who "formula-assembly-visual?" assembly))
  (unless
      (andmap
       (lambda (part)
         (define formula
           (formula-part-formula part))
         (and (tagged-formula-fragment-visual? formula)
              (string? (tagged-formula-fragment-visual-glyph-key formula))))
       (formula-assembly-visual-parts assembly))
    (raise-argument-error
     who
     "a formula assembly returned by glyph-tex"
     assembly)))

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
