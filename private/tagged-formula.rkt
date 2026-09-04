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
         racket/list
         racket/port
         racket/string
         (only-in pict pict->bitmap pict-height pict-width)
         svg/svg
         "affine-transform.rkt"
         "animation.rkt"
         "formula-part-transition.rkt"
         "formula-parts-visual.rkt"
         "formula-source-map.rkt"
         "formula-source.rkt"
         "formula-style.rkt"
         "formula-string-match.rkt"
         "formula-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "path-geometry.rkt"
         "source-document.rkt"
         "source-selector.rkt"
         "svg-write-paths.rkt"
         "tex-source-scanner.rkt"
         "visual-selection.rkt"
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
         transform-matching-strings
         rewrite-matching-strings
         rewrite-formula)


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
;                  [#:color-map (hash/c symbol? color-spec?)]
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
                        #:color-map [color-map (hash)]
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
  (formula-color-map
   (formula-assembly parts
                     #:id id
                     #:center center
                     #:rotation rotation
                     #:scale scale
                     #:opacity opacity)
   color-map))


;;; Source-Addressable Formula Construction

; math-tex : #:id symbol?
;            [#:center vec2?]
;            [#:rotation finite-real?]
;            [#:scale scale-factor?]
;            [#:opacity opacity?]
;            [#:mode formula-mode?]
;            [#:font-size positive-real?]
;            [#:preamble string?]
;            [#:document-class-options (listof latex-option?)]
;            [#:color-map (hash/c symbol? color-spec?)]
;            [#:source-map (or/c 'none 'declared 'tokens)]
;            [#:parts (listof source-part?)]
;            string? ...
;            -> formula-assembly-visual?
;; Typesets one complete TeX formula. Source selectors, rather than
;; parser-specific fragment syntax, drive source inspection and matching.
;; Use tagged-formula directly when author-chosen local part identities are
;; the appropriate semantic vocabulary.
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
                  #:color-map [color-map (hash)]
                  ;; Source-addressability is ordinary math-tex behavior. An
                  ;; author opts out explicitly with #:source-map 'none when
                  ;; they deliberately require an opaque, one-part formula.
                  #:source-map [source-map 'tokens]
                  #:parts [declared-parts '()]
                  . tex-strings)
  (unless (and (pair? tex-strings)
               (andmap string? tex-strings))
    (raise-argument-error 'math-tex "nonempty list of strings" tex-strings))
  (unless (memq source-map '(none declared tokens))
    (raise-argument-error 'math-tex "(or/c 'none 'declared 'tokens)" source-map))
  (unless (and (list? declared-parts)
               (andmap source-part? declared-parts))
    (raise-argument-error 'math-tex "list of source-part? values" declared-parts))
  (case source-map
    [(none)
     (unless (null? declared-parts)
       (raise-arguments-error
        'math-tex
        "#:parts only when #:source-map is 'declared"
        "source-map" source-map
        "parts" declared-parts))
     (define source (string-join tex-strings " "))
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
            #:color-map color-map
            (list (formula-fragment 'math-tex source)))]
    [(declared)
     (unless (pair? declared-parts)
       (raise-arguments-error
        'math-tex
        "at least one declared source part when #:source-map is 'declared"
        "parts" declared-parts))
     (define document (source-document-from-strings tex-strings))
     (define-values (fragments mapping)
       (declared-source-fragments document declared-parts))
     (formula-assembly-visual-with-source-map
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
             #:color-map color-map
             fragments)
      mapping)]
    [(tokens)
     (unless (null? declared-parts)
       (raise-arguments-error
        'math-tex
        "#:parts is not needed when #:source-map is 'tokens"
        "source-map" source-map
        "parts" declared-parts))
     (define document (source-document-from-strings tex-strings))
     (define-values (fragments mapping)
       (declared-source-fragments document (token-source-parts document)))
     (formula-assembly-visual-with-source-map
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
             #:color-map color-map
             fragments)
      mapping)]))


;;; Declared Source Mapping

;; A declared entry records one stable source-part and the one contiguous span
;; it resolved to. The public source-part name becomes the formula child ID.
(struct declared-source-entry (part span)
  #:transparent)

;; A physical fragment can include adjacent unselected whitespace/comments so
;; no invisible SVG group is ever requested from the tagged-formula compiler.
;; Its `name` is either a source-part name or a deterministic source-gap name.
(struct declared-source-fragment (name span)
  #:transparent)

;; token-source-parts : source-document? -> (listof source-part?)
;; Produces conservative TeX *atoms*, not a full TeX parse and not a proven
;; token-to-glyph map.  Each atom can safely stand inside the existing tagged
;; fragment wrapper: bases retain their scripts, known multi-argument commands
;; retain their groups, and ordinary brace groups stay intact.  This gives
;; useful post-construction source selection without ever splitting syntax such
;; as `x^2` or `\\frac{a}{b}` into invalid TeX fragments.
;;
;; Unknown commands followed by one braced group are kept with that group. An
;; unknown command with several required arguments, category-code changes, or
;; a macro whose expansion crosses a selected boundary remains advanced input;
;; callers can use `#:source-map 'declared` for explicitly chosen spans.
(define (token-source-parts document)
  (define source (source-document-text document))
  (define scan (scan-tex-source source))
  (when (pair? (tex-source-scan-diagnostics scan))
    (raise-arguments-error
     'math-tex
     "balanced TeX source before automatic source atom mapping"
     "diagnostic" (car (tex-source-scan-diagnostics scan))))
  (define tokens (tex-source-scan-tokens scan))
  (define token-count (length tokens))
  (define (token-at index) (list-ref tokens index))
  (define (token-source index)
    (define token (token-at index))
    (substring source
               (tex-source-token-start token)
               (tex-source-token-end token)))
  (define (in-range? index) (< index token-count))
  (define (ignorable? index)
    (memq (tex-source-token-kind (token-at index)) '(whitespace comment)))
  (define (skip-ignorable index)
    (if (and (in-range? index) (ignorable? index))
        (skip-ignorable (add1 index))
        index))
  ;; Returns the token index immediately after a braced group, or #f when the
  ;; next material is not a complete `{ ... }` group.
  (define (group-end index)
    (cond
      [(or (not (in-range? index))
           (not (eq? (tex-source-token-kind (token-at index)) 'open-brace)))
       #f]
      [else
       (let loop ([cursor index] [depth 0])
         (cond
           [(not (in-range? cursor)) #f]
           [else
            (define kind (tex-source-token-kind (token-at cursor)))
            (define next-depth
              (cond [(eq? kind 'open-brace) (add1 depth)]
                    [(eq? kind 'close-brace) (sub1 depth)]
                    [else depth]))
            (cond [(negative? next-depth) #f]
                  [(zero? next-depth) (add1 cursor)]
                  [else (loop (add1 cursor) next-depth)])]))]))
  (define (groups-end index count)
    (let loop ([cursor index] [remaining count])
      (cond
        [(zero? remaining) cursor]
        [else
         (define group (group-end (skip-ignorable cursor)))
         (and group (loop group (sub1 remaining)))])))
  (define (script-tail-end index)
    (let loop ([cursor index])
      (cond
        [(or (not (in-range? cursor))
             (not (eq? (tex-source-token-kind (token-at cursor))
                       'script-marker)))
         cursor]
        [else
         (define argument-start (skip-ignorable (add1 cursor)))
         (cond
           [(not (in-range? argument-start)) cursor]
           [(eq? (tex-source-token-kind (token-at argument-start)) 'open-brace)
            (define group (group-end argument-start))
            (if group (loop group) cursor)]
           [else (loop (add1 argument-start))])])))
  (define (control-end index)
    (define command (token-source index))
    (define after-command (add1 index))
    (define required-groups
      (cond [(member command '("\\frac" "\\dfrac" "\\tfrac")) 2]
            [(member command '("\\sqrt" "\\text" "\\mathrm" "\\mathbf"
                               "\\mathit" "\\operatorname" "\\overline"
                               "\\underline" "\\hat" "\\bar" "\\vec")) 1]
            [else 0]))
    (define with-required-groups
      (and (positive? required-groups)
           (groups-end after-command required-groups)))
    (define initial-end
      (cond [with-required-groups with-required-groups]
            [(positive? required-groups) after-command]
            [else
             ;; This conservative default handles common one-argument macros
             ;; without pretending to know arbitrary macro arities.
             (or (groups-end after-command 1) after-command)]))
    (script-tail-end initial-end))
  (define (atom-end index)
    (define token (token-at index))
    (define end
      (case (tex-source-token-kind token)
        [(ordinary) (add1 index)]
        [(control-word control-symbol) (control-end index)]
        [(open-brace) (or (group-end index) (add1 index))]
        [else (add1 index)]))
    (script-tail-end end))
  (define parts-reversed '())
  (define next-name-index 0)
  (let loop ([cursor 0])
    (define atom-start (skip-ignorable cursor))
    (cond
      [(not (in-range? atom-start)) (reverse parts-reversed)]
      [else
       (define token (token-at atom-start))
       (define atom-end-index (atom-end atom-start))
       ;; A top-level script marker cannot form valid TeX independently.  It
       ;; only arises after malformed source or an unsupported previous atom;
       ;; leave it as an unselected physical gap rather than claiming a map.
       (if (eq? (tex-source-token-kind token) 'script-marker)
           (loop (add1 atom-start))
           (let* ([last-token (token-at (sub1 atom-end-index))]
                  [span (source-span (tex-source-token-start token)
                                     (tex-source-token-end last-token))]
                  [name (string->symbol
                         (format "source-token-~a" next-name-index))])
             (set! next-name-index (add1 next-name-index))
             (set! parts-reversed (cons (source-part name span) parts-reversed))
             (loop atom-end-index)))]))
  (when (null? parts-reversed)
    (raise-arguments-error
     'math-tex
     "at least one safely wrappable TeX source atom"
     "source" source))
  (reverse parts-reversed))

;; declared-source-fragments : source-document? (listof source-part?)
;;                             -> (values (listof formula-fragment?)
;;                                        formula-source-map?)
;; Validates selectors before invoking TeX. Each named declaration must resolve
;; to exactly one safe, contiguous source span; overlaps and nesting are
;; intentionally rejected while formula assemblies remain a flat part list.
(define (declared-source-fragments document parts)
  (define scan (scan-tex-source (source-document-text document)))
  (check-distinct-declared-source-names parts)
  (define entries
    (for/list ([part (in-list parts)])
      (define spans (resolve-source-selector document part))
      (unless (= (length spans) 1)
        (raise-arguments-error
         'math-tex
         "each declared source part to resolve to exactly one contiguous source span"
         "part-name" (source-part-name part)
         "selector" (source-part-selector part)
         "match-count" (length spans)))
      (define span (car spans))
      (define diagnostic (tex-source-span-diagnostic scan span))
      (when diagnostic
        (raise-arguments-error
         'math-tex
         "a declared source span that can safely receive a TeX fragment wrapper"
         "part-name" (source-part-name part)
         "span" span
         "diagnostic" diagnostic))
      (declared-source-entry part span)))
  (define sorted-entries
    (sort entries
          (lambda (left right)
            (< (source-span-start (declared-source-entry-span left))
               (source-span-start (declared-source-entry-span right))))))
  (check-disjoint-declared-source-entries sorted-entries)
  (define physical-fragments
    (partition-declared-source document scan sorted-entries))
  (values
   (for/list ([fragment (in-list physical-fragments)])
     (formula-fragment
      (declared-source-fragment-name fragment)
      (source-document-span-text document
                                 (declared-source-fragment-span fragment))))
   (make-formula-source-map
    document
    (for/list ([entry (in-list sorted-entries)])
      (define part (declared-source-entry-part entry))
      (define span (declared-source-entry-span entry))
      (formula-source-match
       span
       (source-document-span-text document span)
       (source-part-name part)
       (list (list (source-part-name part))))))))

(define (check-distinct-declared-source-names parts)
  (define names (map source-part-name parts))
  (unless (= (length names) (length (remove-duplicates names)))
    (raise-arguments-error
     'math-tex
     "declared source parts with distinct names"
     "part-names" names)))

(define (check-disjoint-declared-source-entries entries)
  (let loop ([previous #f] [remaining entries])
    (cond
      [(null? remaining) (void)]
      [else
       (define current (car remaining))
       (when (and previous
                  (< (source-span-start (declared-source-entry-span current))
                     (source-span-end (declared-source-entry-span previous))))
         (raise-arguments-error
          'math-tex
          "disjoint declared source spans; nested and overlapping declarations are not supported"
          "first-part-name" (source-part-name (declared-source-entry-part previous))
          "first-span" (declared-source-entry-span previous)
          "second-part-name" (source-part-name (declared-source-entry-part current))
          "second-span" (declared-source-entry-span current)))
       (loop current (cdr remaining))])))

;; partition-declared-source : source-document? tex-source-scan?
;;                             (listof declared-source-entry?)
;;                             -> (listof declared-source-fragment?)
(define (partition-declared-source document scan entries)
  (define text-length (source-document-length document))
  (define pieces-reversed '())
  (define (add-piece! name span)
    (unless (= (source-span-start span) (source-span-end span))
      (set! pieces-reversed (cons (cons name span) pieces-reversed))))
  (define cursor 0)
  (for ([entry (in-list entries)])
    (define span (declared-source-entry-span entry))
    (when (< cursor (source-span-start span))
      (add-piece! #f (source-span cursor (source-span-start span))))
    (add-piece! (source-part-name (declared-source-entry-part entry)) span)
    (set! cursor (source-span-end span)))
  (when (< cursor text-length)
    (add-piece! #f (source-span cursor text-length)))
  (define pieces (reverse pieces-reversed))
  (define taken-names (make-hasheq))
  (for ([entry (in-list entries)])
    (hash-set! taken-names (source-part-name (declared-source-entry-part entry)) #t))
  (define next-gap-index 0)
  (define (fresh-gap-name)
    (let loop ()
      (define candidate (string->symbol (format "source-gap-~a" next-gap-index)))
      (set! next-gap-index (add1 next-gap-index))
      (if (hash-has-key? taken-names candidate)
          (loop)
          (begin
            (hash-set! taken-names candidate #t)
            candidate))))
  (define fragments-reversed '())
  (define leading-invisible-start #f)
  (define (append-invisible! span)
    (cond
      [(pair? fragments-reversed)
       (define previous (car fragments-reversed))
       (define previous-span (declared-source-fragment-span previous))
       (unless (= (source-span-end previous-span) (source-span-start span))
         (error 'math-tex "internal error: non-adjacent source fragments"))
       (set! fragments-reversed
             (cons (declared-source-fragment
                    (declared-source-fragment-name previous)
                    (source-span (source-span-start previous-span)
                                 (source-span-end span)))
                   (cdr fragments-reversed)))]
      [else
       (set! leading-invisible-start
             (or leading-invisible-start (source-span-start span)))]))
  (for ([piece (in-list pieces)])
    (define name (car piece))
    (define span (cdr piece))
    (cond
      [(not (tex-source-span-has-visible-source? scan span))
       (append-invisible! span)]
      [else
       (define fragment-name (or name (fresh-gap-name)))
       (define fragment-start (or leading-invisible-start (source-span-start span)))
       (set! fragments-reversed
             (cons (declared-source-fragment
                    fragment-name
                    (source-span fragment-start (source-span-end span)))
                   fragments-reversed))
       (set! leading-invisible-start #f)]))
  ;; All declared spans are scanner-validated as visible, so at least one
  ;; physical fragment exists. A trailing invisible gap was already attached
  ;; to its predecessor during the loop.
  (reverse fragments-reversed))

; glyph-tex : #:id symbol?
;             [#:center vec2?]
;             [#:rotation finite-real?]
;             [#:scale scale-factor?]
;             [#:opacity opacity?]
;             [#:mode formula-mode?]
;             [#:font-size positive-real?]
;             [#:preamble string?]
;             [#:document-class-options (listof latex-option?)]
;             [#:color-map (hash/c symbol? color-spec?)]
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
                   #:color-map [color-map (hash)]
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
  (formula-color-map
   (formula-assembly parts
                     #:id id
                     #:center center
                     #:rotation rotation
                     #:scale scale
                     #:opacity opacity)
   color-map))

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

; transform-matching-strings : formula-assembly-visual?
;                              formula-assembly-visual?
;                              [#:matches (listof string-match?)]
;                              [#:key-map (listof string-match?)]
;                              [#:protect-source (listof source-selector?)]
;                              [#:protect-destination (listof source-selector?)]
;                              [#:copies (listof string-copy?)]
;                              [#:on-ambiguity (or/c 'left-to-right 'error)]
;                              [#:path-arc finite-real?]
;                              [#:mismatch-mode (or/c 'fade 'fade-transform)]
;                              -> transform-formula-parts-request?
;; Plans declared source-map correspondences, then compiles each selected
;; complete formula fragment into the established deterministic part-transition
;; system. Explicit maps outrank automatic source blocks. A future token map
;; will allow several glyph leaves per planned string block; this initial
;; compiler intentionally rejects anything other than whole declared parts.
(define (transform-matching-strings source destination
                                    #:matches [matches '()]
                                    #:key-map [key-map '()]
                                    #:protect-source [protect-source '()]
                                    #:protect-destination [protect-destination '()]
                                    #:copies [copies '()]
                                    #:on-ambiguity [on-ambiguity 'left-to-right]
                                    #:path-arc [path-arc 0]
                                    #:mismatch-mode [mismatch-mode 'fade])
  (define plan
    (plan-matching-strings
     source destination
     #:matches matches
     #:key-map key-map
     #:protect-source protect-source
     #:protect-destination protect-destination
     #:on-ambiguity on-ambiguity))
  (check-string-copy-list 'transform-matching-strings copies)
  (define correspondence
    (string-match-plan->formula-correspondence plan))
  (transform-formula-parts
   correspondence
   #:path-arc path-arc
   #:part-paths (string-match-plan->formula-part-paths plan)
   #:copies (string-copies->formula-part-copies
             source destination correspondence copies path-arc)
   #:mismatch-mode mismatch-mode))

; rewrite-matching-strings : formula-assembly-visual? formula-assembly-visual?
;                            #:anchor source-selector?
;                            [#:stationary (listof source-selector?)]
;                            [#:matches (listof string-match?)]
;                            [#:key-map (listof string-match?)]
;                            [#:protect-source (listof source-selector?)]
;                            [#:protect-destination (listof source-selector?)]
;                            [#:copies (listof string-copy?)]
;                            [#:on-ambiguity (or/c 'left-to-right 'error)]
;                            [#:path-arc finite-real?]
;                            [#:mismatch-mode (or/c 'fade 'fade-transform)]
;                            -> transform-formula-parts-request?
;; A source-addressed counterpart to `rewrite-formula`.  The anchor and every
;; stationary selector are made explicit before automatic matching, then the
;; established scene-compile-time anchoring logic measures the *current*
;; formula layout.  Each selector must resolve to exactly one declared part in
;; both formulas in this first implementation.
(define (rewrite-matching-strings source destination
                                  #:anchor anchor
                                  #:stationary [stationary '()]
                                  #:matches [matches '()]
                                  #:key-map [key-map '()]
                                  #:protect-source [protect-source '()]
                                  #:protect-destination [protect-destination '()]
                                  #:copies [copies '()]
                                  #:on-ambiguity [on-ambiguity 'left-to-right]
                                  #:path-arc [path-arc 0]
                                  #:mismatch-mode [mismatch-mode 'fade])
  (unless (source-selector? anchor)
    (raise-argument-error 'rewrite-matching-strings "source-selector?" anchor))
  (unless (and (list? stationary) (andmap source-selector? stationary))
    (raise-argument-error
     'rewrite-matching-strings
     "list of source-selector? values"
     stationary))
  ;; Explicitly installing these pairs means an occurrence selector determines
  ;; the exact correspondence before any repeated-string heuristic runs.
  (define required-matches
    (append (list (string-match anchor anchor))
            (for/list ([selector (in-list stationary)])
              (string-match selector selector))
            matches))
  (define plan
    (plan-matching-strings
     source destination
     #:matches required-matches
     #:key-map key-map
     #:protect-source protect-source
     #:protect-destination protect-destination
     #:on-ambiguity on-ambiguity))
  (check-string-copy-list 'rewrite-matching-strings copies)
  (define correspondence (string-match-plan->formula-correspondence plan))
  (define anchor-match
    (selector->single-part-match source destination anchor))
  (define stationary-matches
    (for/list ([selector (in-list stationary)])
      (selector->single-part-match source destination selector)))
  (transform-formula-parts/anchored
   correspondence
   anchor-match
   #:path-arc path-arc
   #:part-paths (string-match-plan->formula-part-paths plan)
   #:copies (string-copies->formula-part-copies
             source destination correspondence copies path-arc)
   #:stationary stationary-matches
   #:mismatch-mode mismatch-mode))

(define (string-match-plan->formula-correspondence plan)
  (unless (string-match-plan? plan)
    (raise-argument-error
     'transform-matching-strings
     "string-match-plan?"
     plan))
  (define source (string-match-plan-source plan))
  (define destination (string-match-plan-destination plan))
  (formula-correspondence
   source
   destination
   (append*
    (for/list ([match (in-list (string-match-plan-matches plan))])
      (planned-string-match->formula-part-matches source destination match)))))

(define (string-match-plan->formula-part-paths plan)
  (unless (string-match-plan? plan)
    (raise-argument-error
     'transform-matching-strings
     "string-match-plan?"
     plan))
  (define source (string-match-plan-source plan))
  (define destination (string-match-plan-destination plan))
  (append*
   (for/list ([match (in-list (string-match-plan-matches plan))]
              #:when (planned-string-match-route match))
     (planned-string-match->formula-part-paths source destination match))))

;; planned-string-match->formula-part-matches : formula assembly formula
;;                                               planned-string-match?
;;                                               -> (listof formula-part-match?)
(define (planned-string-match->formula-part-matches source destination match)
  (define source-names
    (selection->declared-part-names
     source (planned-string-match-source-selection match)))
  (define destination-names
    (selection->declared-part-names
     destination (planned-string-match-destination-selection match)))
  (unless (= (length source-names) (length destination-names))
    (raise-arguments-error
     'transform-matching-strings
     "planned source/destination selections with the same declared part count"
     "planned-match" match
     "source-count" (length source-names)
     "destination-count" (length destination-names)))
  (for/list ([source-name (in-list source-names)]
             [destination-name (in-list destination-names)])
    (formula-part-match source-name destination-name)))

(define (planned-string-match->formula-part-paths source destination match)
  (for/list ([part-match
              (in-list
               (planned-string-match->formula-part-matches
                source destination match))])
    (formula-part-path
     (formula-part-match-source-name part-match)
     (formula-part-match-destination-name part-match)
     (planned-string-match-route match))))

(define (selection->declared-part-names formula selection)
  (unless (and (visual-selection? selection)
               (equal? (visual-selection-root selection)
                       (list (visual-id formula))))
    (raise-arguments-error
     'transform-matching-strings
     "a formula-local source selection rooted at the planned formula"
     "formula-id" (visual-id formula)
     "selection" selection))
  (for/list ([path (in-list (visual-selection-paths selection))])
    (unless (and (pair? path) (null? (cdr path)))
      (raise-arguments-error
       'transform-matching-strings
       "a planned selection of complete declared formula fragments"
       "formula-id" (visual-id formula)
       "selection" selection
       "relative-path" path))
    (define name (car path))
    (unless (formula-assembly-visual-has-part? formula name)
      (raise-arguments-error
       'transform-matching-strings
       "a planned formula part present in the target formula"
       "formula-id" (visual-id formula)
       "part-name" name))
    name))

(define (selector->single-part-match source destination selector)
  (define source-names
    (selection->declared-part-names
     source (formula-source-select-one source selector)))
  (define destination-names
    (selection->declared-part-names
     destination (formula-source-select-one destination selector)))
  (unless (and (= (length source-names) 1)
               (= (length destination-names) 1))
    (raise-arguments-error
     'rewrite-matching-strings
     "a selector resolving to one declared source part in each formula"
     "selector" selector
     "source-count" (length source-names)
     "destination-count" (length destination-names)))
  (formula-part-match (car source-names) (car destination-names)))

(define (string-copies->formula-part-copies source destination correspondence
                                             copies path-arc)
  (define unmatched-destinations
    (formula-correspondence-unmatched-destination-names correspondence))
  (define default-route (formula-arc #:angle path-arc))
  (append*
   (for/list ([copy (in-list copies)])
     (define source-names
       (selection->declared-part-names
        source
        (formula-source-select source (string-copy-source-selector copy))))
     (define destination-names
       (selection->declared-part-names
        destination
        (formula-source-select destination
                               (string-copy-destination-selector copy))))
     (unless (= (length source-names) (length destination-names))
       (raise-arguments-error
        'transform-matching-strings
        "copy selectors resolving to the same number of declared formula parts"
        "source-selector" (string-copy-source-selector copy)
        "destination-selector" (string-copy-destination-selector copy)
        "source-count" (length source-names)
        "destination-count" (length destination-names)))
     (for/list ([source-name (in-list source-names)]
                [destination-name (in-list destination-names)])
       (unless (member destination-name unmatched-destinations)
         (raise-arguments-error
          'transform-matching-strings
          "a copied destination part left unmatched by ordinary string matching"
          "destination-name" destination-name
          "copy" copy))
       (formula-part-copy
        source-name
        destination-name
        (or (string-copy-route copy) default-route))))))

(define (check-string-copy-list who copies)
  (unless (and (list? copies) (andmap string-copy? copies))
    (raise-argument-error who "list of string-copy? values" copies)))

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
