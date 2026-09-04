#lang racket/base

;;;
;;; Normalized Formula Source Units
;;;

;; This module converts the renderable entries of a formula source map into a
;; stable stream suitable for source-aware correspondence planning.  It does
;; not parse TeX or infer algebraic equivalence.  In particular, macros are
;; never expanded and distinct TeX token streams remain distinct.

(require racket/list
         racket/string
         "formula-parts-visual.rkt"
         "formula-source-map.rkt"
         "formula-source.rkt"
         "source-document.rkt"
         "tex-source-scanner.rkt"
         "visual-model.rkt")

(provide (struct-out formula-source-unit)
         normalize-formula-source
         formula-source-units)


;;;
;;; Units
;;;

;; `glyph-paths` are relative to the formula assembly.  They are named this
;; way deliberately: a future token mapping will populate the same field with
;; actual glyph leaves.  Declared mappings currently expose whole fragments.
(struct formula-source-unit
  (span raw-key normalized-key glyph-paths visible-weight)
  #:transparent
  #:guard
  (lambda (span raw-key normalized-key glyph-paths visible-weight who)
    (unless (source-span? span)
      (raise-argument-error who "source-span?" span))
    (unless (string? raw-key)
      (raise-argument-error who "string?" raw-key))
    (unless (list? normalized-key)
      (raise-argument-error who "list?" normalized-key))
    (unless (and (list? glyph-paths)
                 (pair? glyph-paths)
                 (andmap relative-visual-path? glyph-paths))
      (raise-argument-error who "nonempty list of relative Visual paths" glyph-paths))
    (unless (exact-positive-integer? visible-weight)
      (raise-argument-error who "exact-positive-integer?" visible-weight))
    (values span
            (string->immutable-string raw-key)
            normalized-key
            (remove-duplicates glyph-paths equal?)
            visible-weight)))


;;;
;;; Normalization
;;;

;; normalize-formula-source : string? -> (listof immutable token datum)
;; A token list, rather than a flattened string, prevents accidental joins
;; such as `\\sin x` becoming indistinguishable from `\\sinx`.  Whitespace and
;; comments are deliberately discarded; every remaining TeX lexical token is
;; retained, including braces and script markers.
(define (normalize-formula-source source)
  (unless (string? source)
    (raise-argument-error 'normalize-formula-source "string?" source))
  (define scan (scan-tex-source source))
  (for/list ([token (in-list (tex-source-scan-tokens scan))]
             #:unless (memq (tex-source-token-kind token)
                            '(whitespace comment)))
    (list (tex-source-token-kind token)
          (string->immutable-string
           (substring source
                      (tex-source-token-start token)
                      (tex-source-token-end token))))))

;; formula-source-units : formula-assembly-visual? -> (listof formula-source-unit?)
;; Returns mapped source fragments in canonical source order.  A formula with
;; no source map is rejected rather than silently falling back to rendered
;; shape matching.
(define (formula-source-units formula)
  (unless (formula-assembly-visual? formula)
    (raise-argument-error 'formula-source-units "formula-assembly-visual?" formula))
  (define mapping (formula-source-map formula))
  (unless mapping
    (raise-arguments-error
     'formula-source-units
     "a formula constructed with math-tex source mapping"
     "formula-id" (visual-id formula)))
  (for/list ([match (in-list (formula-source-map-matches mapping))])
    (define raw-key (formula-source-match-text match))
    (define normalized-key (normalize-formula-source raw-key))
    ;; Every declared match was scanner-validated as visibly producing source.
    ;; Counting non-space lexical tokens gives deterministic tie-breaking now;
    ;; a token-to-glyph map will later replace this with glyph weight.
    (formula-source-unit
     (formula-source-match-span match)
     raw-key
     normalized-key
     (formula-source-match-relative-paths match)
     (max 1 (length normalized-key)))))


;;;
;;; Validation
;;;

(define (relative-visual-path? value)
  (and (list? value)
       (andmap symbol? value)))
