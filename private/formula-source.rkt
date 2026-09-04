#lang racket/base

;;;
;;; Formula Source Inspection and Selection
;;;

(require racket/list
         "formula-parts-visual.rkt"
         "formula-source-map.rkt"
         "source-document.rkt"
         "source-selector.rkt"
         "tex-source-scanner.rkt"
         "visual-model.rkt"
         "visual-selection.rkt")

(provide formula-source
         formula-source-map
         formula-find
         formula-source-select
         formula-source-select-one
         formula-source-match-selection
         (struct-out source-selection-report)
         formula-explain-selection)


;;;
;;; Source Map Access
;;;

;; formula-source-map : formula-assembly-visual? -> (or/c #f formula-source-map?)
;; Ordinary `math-tex` construction carries a token map by default. Returning
;; #f remains the explicit `#:source-map 'none` opt-out, rather than inventing
;; a best-effort correspondence for legacy/unsplit formula assemblies.
(define (formula-source-map formula)
  (check-formula 'formula-source-map formula)
  (define mapping (formula-assembly-visual-source-map formula))
  (unless (or (not mapping) (formula-source-map? mapping))
    (raise-arguments-error
     'formula-source-map
     "a formula assembly carrying #f or a formula-source-map?"
     "formula-id" (visual-id formula)
     "source-map" mapping))
  mapping)

;; formula-source : formula-assembly-visual? -> immutable-string?
(define (formula-source formula)
  (source-document-text
   (formula-source-map-document
    (require-source-map 'formula-source formula))))


;;;
;;; Queries and Selections
;;;

;; formula-find : formula-assembly-visual? source-selector?
;;                -> (listof formula-source-match?)
;; An unmatched query returns an empty list. In declared mode a match refers to
;; the smallest author-declared renderable source part containing that query.
(define (formula-find formula selector)
  (formula-source-map-find
   (require-source-map 'formula-find formula)
   selector))

;; formula-source-select : formula-assembly-visual? source-selector?
;;                         -> visual-selection?
;; A selection-producing operation requires at least one mapped match.
(define (formula-source-select formula selector)
  (define matches (formula-find formula selector))
  (when (null? matches)
    (raise-arguments-error
     'formula-source-select
     "a source selector resolving to declared rendered formula material"
     "formula-id" (visual-id formula)
     "selector" selector))
  (visual-selection
   (list (visual-id formula))
   (append* (map formula-source-match-relative-paths matches))))

;; formula-source-select-one : formula-assembly-visual? source-selector?
;;                             -> visual-selection?
(define (formula-source-select-one formula selector)
  (define matches (formula-find formula selector))
  (unless (= (length matches) 1)
    (raise-arguments-error
     'formula-source-select-one
     "a source selector resolving to exactly one declared formula part"
     "formula-id" (visual-id formula)
     "selector" selector
     "match-count" (length matches)))
  (formula-source-match-selection formula (car matches)))

;; formula-source-match-selection : formula-assembly-visual?
;;                                  formula-source-match? -> visual-selection?
(define (formula-source-match-selection formula match)
  (check-formula 'formula-source-match-selection formula)
  (unless (formula-source-match? match)
    (raise-argument-error
     'formula-source-match-selection
     "formula-source-match?"
     match))
  ;; A match is only meaningful for a formula whose current local tree still
  ;; exposes each recorded path. This prevents stale source-map metadata from
  ;; silently targeting a structurally replaced assembly.
  (for ([path (in-list (formula-source-match-relative-paths match))])
    (unless (and (pair? path)
                 (formula-assembly-visual-has-part? formula (car path)))
      (raise-arguments-error
       'formula-source-match-selection
       "a source map whose local paths are present in the formula assembly"
       "formula-id" (visual-id formula)
       "source-match" match
       "missing-relative-path" path)))
  (visual-selection
   (list (visual-id formula))
   (formula-source-match-relative-paths match)))

;; source-selection-report separates source diagnostics from the identity of a
;; visual selection.  It is intentionally a transparent inspection value, not
;; metadata stored inside `visual-selection`, so selection equality remains
;; solely about the leaves selected.
(struct source-selection-report (selector matches rejected-spans diagnostics)
  #:transparent)

;; formula-explain-selection : formula-assembly-visual? source-selector?
;;                              -> source-selection-report?
;; Reports the same mapped matches as `formula-find`, together with source
;; ranges that resolved lexically but have no rendered source-map leaf. This
;; is useful for a preview inspector and makes the declared/token-map boundary
;; explicit instead of silently returning an empty visual selection.
(define (formula-explain-selection formula selector)
  (check-formula 'formula-explain-selection formula)
  (unless (source-selector? selector)
    (raise-argument-error
     'formula-explain-selection
     "source-selector?"
     selector))
  (define mapping (require-source-map 'formula-explain-selection formula))
  (define document (formula-source-map-document mapping))
  (define resolved-spans (resolve-source-selector document selector))
  (define matches (formula-source-map-find mapping selector))
  (define scan (scan-tex-source (source-document-text document)))
  (define unsafe-spans
    (filter (lambda (span) (not (tex-source-span-safe? scan span)))
            resolved-spans))
  (define rejected-spans
    (for/list ([span (in-list resolved-spans)]
               #:unless
               (and (tex-source-span-safe? scan span)
                    (for/or ([match (in-list matches)])
                      (spans-overlap? span (formula-source-match-span match)))))
      span))
  (source-selection-report
   selector
   matches
   rejected-spans
   (append
    (if (null? matches)
        (list "the selector resolved in source text but no mapped rendered leaf overlaps it")
        '())
    (if (null? rejected-spans)
        '()
        (list "some resolved source ranges are outside the formula's current declared/token atom map"))
    (for/list ([span (in-list unsafe-spans)])
      (tex-source-span-diagnostic scan span)))))


;;;
;;; Validation
;;;

(define (require-source-map who formula)
  (or (formula-source-map formula)
      (raise-arguments-error
       who
       "a source-mapped formula (the math-tex default, or #:source-map 'declared)"
       "formula-id" (visual-id formula))))

(define (check-formula who value)
  (unless (formula-assembly-visual? value)
    (raise-argument-error who "formula-assembly-visual?" value)))

(define (spans-overlap? left right)
  (and (< (source-span-start left) (source-span-end right))
       (< (source-span-start right) (source-span-end left))))
