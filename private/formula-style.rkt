#lang racket/base

;;;
;;; Semantic Formula-Part Styling
;;;

;; Formula selection is structural: tagged, MathTex-style, and glyph formulas
;; already expose stable local part names. This module layers colour/opacity
;; changes over those existing formula Visuals without re-running TeX or
;; changing their semantic fragment geometry.

(require racket/list
         (only-in racket/generic define/generic)
         "affine-transform.rkt"
         "color-style.rkt"
         "formula-parts-visual.rkt"
         "formula-visual.rkt"
         "visual-model.rkt"
         "visual-selection.rkt")

(provide formula-select
         formula-style
         formula-color
         formula-color-map

         ;; Adapter support
         formula-styled-visual?
         formula-styled-visual-base
         formula-styled-visual-color
         formula-visual-with-color)


;;;
;;; Styled Formula Leaves
;;;

;; A styled leaf retains its exact underlying formula Visual. This is important
;; for tagged dvisvgm fragments: their cropped SVG source continues to be the
;; renderer artifact while the wrapper contributes only semantic paint.
(struct formula-styled-visual formula-visual (base color)
  #:transparent
  #:methods gen:visual
  [(define/generic generic-visual-with-position visual-with-position)
   (define (visual-id visual)
     (formula-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation (formula-visual-transform visual)))
   (define (visual-with-position visual position)
     (make-formula-styled-visual
      (generic-visual-with-position (formula-styled-visual-base visual) position)
      (formula-styled-visual-color visual)))]
  #:methods gen:affine-visual
  [(define/generic generic-visual-with-transform visual-with-transform)
   (define (visual-transform visual)
     (formula-visual-transform visual))
   (define (visual-with-transform visual transform)
     (make-formula-styled-visual
      (generic-visual-with-transform (formula-styled-visual-base visual) transform)
      (formula-styled-visual-color visual)))]
  #:methods gen:opacity-visual
  [(define/generic generic-visual-with-opacity visual-with-opacity)
   (define (visual-opacity visual)
     (formula-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (make-formula-styled-visual
      (generic-visual-with-opacity (formula-styled-visual-base visual) opacity)
      (formula-styled-visual-color visual)))]
  #:methods gen:fill-color-visual
  [(define (visual-fill-color visual)
     (formula-styled-visual-color visual))
   (define (visual-with-fill-color visual color)
     (formula-visual-with-color visual color))]
  #:methods gen:formula-identity-visual
  [(define (generic-formula-visual-with-id visual id)
     (make-formula-styled-visual
      (formula-visual-with-id (formula-styled-visual-base visual) id)
      (formula-styled-visual-color visual)))]
  #:methods gen:formula-rendering-key
  [(define (generic-formula-rendering-key visual)
     ;; Paint is part of a fragment's settled appearance. Identically styled
     ;; fragments therefore retain the existing stable moving transition; a
     ;; changed paint deliberately uses the established cross-fade fallback.
     (list 'formula-style
           (formula-visual-rendering-key (formula-styled-visual-base visual))
           (formula-styled-visual-color visual)))]
  #:methods gen:formula-transition-sampling
  [(define (generic-formula-visual-at-transition-progress visual progress)
     (make-formula-styled-visual
      (formula-visual-at-transition-progress
       (formula-styled-visual-base visual)
       progress)
      (formula-styled-visual-color visual)))])

;; formula-visual-with-color : formula-visual? color-spec? -> formula-styled-visual?
;; Wraps a formula leaf in one semantic paint override, preserving the exact
;; underlying formula/SVG subtype and all transform/opacity data.
(define (formula-visual-with-color formula color)
  (unless (formula-visual? formula)
    (raise-argument-error 'formula-visual-with-color "formula-visual?" formula))
  (unless (color-spec? color)
    (raise-argument-error 'formula-visual-with-color "color-spec?" color))
  (make-formula-styled-visual
   (if (formula-styled-visual? formula)
       (formula-styled-visual-base formula)
       formula)
   color))

;; make-formula-styled-visual : formula-visual? color-spec? -> formula-styled-visual?
;; Copies the inherited fields from base so every formula protocol and ordinary
;; formula renderer sees the same semantic placement as the wrapped artifact.
(define (make-formula-styled-visual base color)
  (unless (formula-visual? base)
    (raise-argument-error 'make-formula-styled-visual "formula-visual?" base))
  (unless (color-spec? color)
    (raise-argument-error 'make-formula-styled-visual "color-spec?" color))
  (formula-styled-visual
   (formula-visual-id base)
   (visual-transform base)
   (visual-opacity base)
   (formula-visual-source base)
   (formula-visual-mode base)
   (formula-visual-font-size base)
   (formula-visual-preamble base)
   (formula-visual-document-class-options base)
   (formula-visual-preview-options base)
   (formula-visual-horizontal-alignment base)
   (formula-visual-vertical-alignment base)
   base
   color))


;;;
;;; Public Assembly Operations
;;;

; formula-select : formula-assembly-visual? symbol? -> visual-path?
;; Returns the nested scene path for one known named formula fragment.
(define (formula-select formula name)
  (check-formula-assembly 'formula-select formula)
  (check-part-name 'formula-select formula name)
  (list (visual-id formula) name))

; formula-style : formula-assembly-visual?
;                 (or/c symbol? (listof symbol?) visual-selection?)
;                 [#:color (or/c false/c color-spec?)]
;                 [#:opacity (or/c false/c opacity?)]
;                 -> formula-assembly-visual?
;; Returns formula with the selected fragments immutably styled. At least one
;; style keyword must be supplied. Colour is a renderer-independent paint
;; override; opacity remains the ordinary Visual opacity property.
(define (formula-style formula selection
                       #:color [color #f]
                       #:opacity [opacity #f])
  (check-formula-assembly 'formula-style formula)
  (define names (normalize-selection 'formula-style formula selection))
  (for ([name (in-list names)])
    (check-part-name 'formula-style formula name))
  (when (and (not color) (not opacity))
    (raise-arguments-error
     'formula-style
     "at least one of #:color or #:opacity"
     "selection" selection))
  (when (and color (not (color-spec? color)))
    (raise-argument-error 'formula-style "color-spec? or #f" color))
  (when (and opacity (not (opacity? opacity)))
    (raise-argument-error 'formula-style "opacity? or #f" opacity))
  (formula-assembly-visual-with-parts
   formula
   (for/list ([part (in-list (formula-assembly-visual-parts formula))])
     (if (member (formula-part-name part) names)
         (let* ([original (formula-part-formula part)]
                [painted (if color
                             (formula-visual-with-color original color)
                             original)]
                [styled (if opacity
                            (visual-with-opacity painted opacity)
                            painted)])
           (formula-part (formula-part-name part) styled))
         part))
   ;; Styling changes paint/opacity only. The source part tree and all local
   ;; identities are intact, so retaining the source map is deliberate rather
   ;; than a stale-map fallback.
   #:source-map (formula-assembly-visual-source-map formula)))

; formula-color : formula-assembly-visual? (or/c symbol? (listof symbol?))
;                 color-spec? -> formula-assembly-visual?
;; Concise colour-only spelling of formula-style.
(define (formula-color formula selection color)
  (formula-style formula selection #:color color))

; formula-color-map : formula-assembly-visual? (hash/c symbol? color-spec?)
;                     -> formula-assembly-visual?
;; Applies one semantic colour per named formula fragment. The map is checked
;; before any immutable replacements are made, so a misspelled name cannot
;; yield a partially styled formula.
(define (formula-color-map formula color-map)
  (check-formula-assembly 'formula-color-map formula)
  (unless (hash? color-map)
    (raise-argument-error 'formula-color-map "hash?" color-map))
  (for ([(name color) (in-hash color-map)])
    (check-part-name 'formula-color-map formula name)
    (unless (color-spec? color)
      (raise-arguments-error
       'formula-color-map
       "a hash mapping formula part names to color specifications"
       "part-name" name
       "color" color)))
  (for/fold ([result formula]) ([(name color) (in-hash color-map)])
    (formula-color result name color)))


;;;
;;; Validation
;;;

(define (check-formula-assembly who value)
  (unless (formula-assembly-visual? value)
    (raise-argument-error who "formula-assembly-visual?" value)))

(define (check-part-name who formula name)
  (unless (symbol? name)
    (raise-argument-error who "symbol?" name))
  (unless (formula-assembly-visual-has-part? formula name)
    (raise-arguments-error
     who
     "a name present in the formula assembly"
     "formula-id" (visual-id formula)
     "part-name" name)))

(define (normalize-selection who formula selection)
  (define names
    (cond
      [(symbol? selection) (list selection)]
      [(and (list? selection)
            (pair? selection)
            (andmap symbol? selection))
       selection]
      [(visual-selection? selection)
       (unless (equal? (visual-selection-root selection)
                       (list (visual-id formula)))
         (raise-arguments-error
          who
          "a visual selection rooted at the supplied formula"
          "formula-id" (visual-id formula)
          "selection-root" (visual-selection-root selection)))
       (for/list ([path (in-list (visual-selection-paths selection))])
         (unless (and (list? path)
                      (= (length path) 1)
                      (symbol? (car path)))
           (raise-arguments-error
            who
            "a formula-part selection with one local part path per leaf"
            "formula-id" (visual-id formula)
            "selection-path" path))
         (car path))]
      [else
       (raise-argument-error
        who
        "symbol?, nonempty list of symbols, or visual-selection?"
        selection)]))
  (when (not (= (length names) (length (remove-duplicates names))))
    (raise-arguments-error
     who
     "a selection without duplicate part names"
     "selection" selection))
  names)
