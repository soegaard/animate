#lang racket/base

;;;
;;; Formula Part Transition Model
;;;

;; Compiles and samples deterministic transitions between explicitly matched
;; formula parts.
;;
;; This module contains no Pict, drawing-context, bitmap, filesystem, process,
;; browser, or JavaScript dependencies.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "formula-parts-visual.rkt"
         "formula-visual.rkt"
         "geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide formula-transition-plan?
         make-formula-transition-plan
         formula-transition-plan-source-parts
         formula-transition-plan-destination-parts
         formula-transition-plan-sample-parts)


;;;
;;; Compiled Transition Data
;;;

(struct formula-transition-layer
  (name template from-transform to-transform from-opacity to-opacity)
  #:transparent)

;; formula-transition-layer represents one independently rendered interior layer.
;;  - name            symbol?             deterministic temporary local identity.
;;  - template        formula-visual?     source of LaTeX and typesetting data.
;;  - from-transform  affine-transform?   local transform at progress zero.
;;  - to-transform    affine-transform?   local transform at progress one.
;;  - from-opacity    opacity?            local opacity at progress zero.
;;  - to-opacity      opacity?            local opacity at progress one.

(struct formula-transition-plan
  (source-parts layers destination-parts)
  #:transparent)

;; formula-transition-plan represents one compiled formula-part transformation.
;;  - source-parts       (listof formula-part?)  exact current source order.
;;  - layers             (listof formula-transition-layer?)
;;                       deterministic interior drawing order.
;;  - destination-parts  (listof formula-part?)  exact destination order.
;;
;; The layer order is source-only parts, matched layers in correspondence order,
;; and destination-only parts. A changed matched part contributes a source layer
;; followed by a destination layer.

(struct formula-transition-spec
  (template from-transform to-transform from-opacity to-opacity)
  #:transparent)

;; formula-transition-spec is one layer before a temporary name is allocated.
;;  - template        formula-visual?    source of LaTeX and typesetting data.
;;  - from-transform  affine-transform?  local transform at progress zero.
;;  - to-transform    affine-transform?  local transform at progress one.
;;  - from-opacity    opacity?           local opacity at progress zero.
;;  - to-opacity      opacity?           local opacity at progress one.


;;;
;;; Plan Construction
;;;

; make-formula-transition-plan : formula-assembly-visual?
;                                formula-correspondence?
;                                -> formula-transition-plan?
;;   Compiles correspondence against the current source assembly.
(define (make-formula-transition-plan current-source correspondence)
  (unless (formula-assembly-visual? current-source)
    (raise-argument-error
     'make-formula-transition-plan
     "formula-assembly-visual?"
     current-source))
  (unless (formula-correspondence? correspondence)
    (raise-argument-error
     'make-formula-transition-plan
     "formula-correspondence?"
     correspondence))
  (check-current-source-names current-source correspondence)
  (define destination
    (formula-correspondence-destination correspondence))
  (define destination-parts
    (formula-assembly-visual-parts destination))
  ;; Validate that the exact destination parts can occupy the current assembly
  ;; identity before any timeline is constructed.
  (formula-assembly-visual-with-parts current-source destination-parts)
  (define specs
    (append
     (make-unmatched-source-specs current-source correspondence)
     (make-matched-specs current-source correspondence)
     (make-unmatched-destination-specs correspondence)))
  (formula-transition-plan
   (formula-assembly-visual-parts current-source)
   (name-transition-specs
    (visual-id current-source)
    current-source
    destination
    specs)
   destination-parts))

; check-current-source-names : formula-assembly-visual?
;                              formula-correspondence?
;                              -> void?
;;   Requires the current source to have the correspondence source namespace.
(define (check-current-source-names current-source correspondence)
  (define expected-names
    (formula-assembly-visual-part-names
     (formula-correspondence-source correspondence)))
  (define current-names
    (formula-assembly-visual-part-names current-source))
  (unless (equal? current-names expected-names)
    (raise-arguments-error
     'scene-play
     "the current formula assembly does not match the correspondence source"
     "visual-id" (visual-id current-source)
     "expected part-names" expected-names
     "current part-names" current-names)))

; make-unmatched-source-specs : formula-assembly-visual?
;                               formula-correspondence?
;                               -> (listof formula-transition-spec?)
;;   Creates stationary fade-out layers in current source order.
(define (make-unmatched-source-specs current-source correspondence)
  (for/list ([name
              (in-list
               (formula-correspondence-unmatched-source-names
                correspondence))])
    (define formula
      (formula-part-formula
       (formula-assembly-visual-ref current-source name)))
    (formula-transition-spec
     formula
     (visual-transform formula)
     (visual-transform formula)
     (visual-opacity formula)
     0)))

; make-matched-specs : formula-assembly-visual?
;                      formula-correspondence?
;                      -> (listof formula-transition-spec?)
;;   Creates moving matched layers in explicit correspondence order.
(define (make-matched-specs current-source correspondence)
  (define destination
    (formula-correspondence-destination correspondence))
  (apply
   append
   (for/list ([match
               (in-list
                (formula-correspondence-matches correspondence))])
     (define source-formula
       (formula-part-formula
        (formula-assembly-visual-ref
         current-source
         (formula-part-match-source-name match))))
     (define destination-formula
       (formula-part-formula
        (formula-assembly-visual-ref
         destination
         (formula-part-match-destination-name match))))
     (make-one-match-specs source-formula destination-formula))))

; make-one-match-specs : formula-visual? formula-visual?
;                        -> (listof formula-transition-spec?)
;;   Creates one moving layer or a moving cross-fade pair for a match.
(define (make-one-match-specs source-formula destination-formula)
  (define source-transform
    (visual-transform source-formula))
  (define destination-transform
    (visual-transform destination-formula))
  (cond
    [(formula-rendering-equivalent? source-formula destination-formula)
     (list
      (formula-transition-spec
       source-formula
       source-transform
       destination-transform
       (visual-opacity source-formula)
       (visual-opacity destination-formula)))]
    [else
     (list
      (formula-transition-spec
       source-formula
       source-transform
       destination-transform
       (visual-opacity source-formula)
       0)
      (formula-transition-spec
       destination-formula
       source-transform
       destination-transform
       0
       (visual-opacity destination-formula)))]))

; make-unmatched-destination-specs : formula-correspondence?
;                                    -> (listof formula-transition-spec?)
;;   Creates stationary fade-in layers in destination order.
(define (make-unmatched-destination-specs correspondence)
  (define destination
    (formula-correspondence-destination correspondence))
  (for/list ([name
              (in-list
               (formula-correspondence-unmatched-destination-names
                correspondence))])
    (define formula
      (formula-part-formula
       (formula-assembly-visual-ref destination name)))
    (formula-transition-spec
     formula
     (visual-transform formula)
     (visual-transform formula)
     0
     (visual-opacity formula))))

; formula-rendering-equivalent? : formula-visual? formula-visual? -> boolean?
;;   Reports whether two formulas differ only in identity, transform, or opacity.
(define (formula-rendering-equivalent? source destination)
  (and (equal? (formula-visual-source source)
               (formula-visual-source destination))
       (eq? (formula-visual-mode source)
            (formula-visual-mode destination))
       (= (formula-visual-font-size source)
          (formula-visual-font-size destination))
       (equal? (formula-visual-preamble source)
               (formula-visual-preamble destination))
       (equal? (formula-visual-document-class-options source)
               (formula-visual-document-class-options destination))
       (equal? (formula-visual-preview-options source)
               (formula-visual-preview-options destination))
       (eq? (formula-visual-horizontal-alignment source)
            (formula-visual-horizontal-alignment destination))
       (eq? (formula-visual-vertical-alignment source)
            (formula-visual-vertical-alignment destination))))

; name-transition-specs : symbol?
;                         formula-assembly-visual?
;                         formula-assembly-visual?
;                         (listof formula-transition-spec?)
;                         -> (listof formula-transition-layer?)
;;   Assigns deterministic temporary names without colliding with model names.
(define (name-transition-specs target-id source destination specs)
  (define initial-used
    (for/fold ([used (hash target-id #t)])
              ([name
                (in-list
                 (append
                  (formula-assembly-visual-part-names source)
                  (formula-assembly-visual-part-names destination)))])
      (hash-set used name #t)))
  (define-values (reversed-layers _used)
    (for/fold ([layers '()]
               [used initial-used])
              ([spec (in-list specs)]
               [index (in-naturals)])
      (define name
        (fresh-transition-name used index))
      (values
       (cons
        (formula-transition-layer
         name
         (formula-transition-spec-template spec)
         (formula-transition-spec-from-transform spec)
         (formula-transition-spec-to-transform spec)
         (formula-transition-spec-from-opacity spec)
         (formula-transition-spec-to-opacity spec))
        layers)
       (hash-set used name #t))))
  (reverse reversed-layers))

; fresh-transition-name : immutable-hash? exact-nonnegative-integer? -> symbol?
;;   Returns the first deterministic reserved name absent from used.
(define (fresh-transition-name used index)
  (let loop ([suffix 0])
    (define candidate
      (string->symbol
       (string-append
        "__formula-transition-"
        (number->string index)
        (if (zero? suffix)
            ""
            (string-append "-" (number->string suffix))))))
    (if (hash-has-key? used candidate)
        (loop (add1 suffix))
        candidate)))


;;;
;;; Plan Sampling
;;;

; formula-transition-plan-sample-parts : formula-transition-plan?
;                                        finite-real?
;                                        -> (listof formula-part?)
;;   Returns exact endpoint parts or deterministic interior transition layers.
(define (formula-transition-plan-sample-parts plan progress)
  (unless (formula-transition-plan? plan)
    (raise-argument-error
     'formula-transition-plan-sample-parts
     "formula-transition-plan?"
     plan))
  (unless (and (finite-real? progress)
               (<= 0 progress 1))
    (raise-argument-error
     'formula-transition-plan-sample-parts
     "finite real in [0, 1]"
     progress))
  (cond
    [(zero? progress)
     (formula-transition-plan-source-parts plan)]
    [(= progress 1)
     (formula-transition-plan-destination-parts plan)]
    [else
     (for/list ([layer
                 (in-list
                  (formula-transition-plan-layers plan))])
       (sample-formula-transition-layer layer progress))]))

; sample-formula-transition-layer : formula-transition-layer? finite-real?
;                                   -> formula-part?
;;   Samples one temporary formula layer at interior progress.
(define (sample-formula-transition-layer layer progress)
  (define name
    (formula-transition-layer-name layer))
  (define formula-with-id
    (formula-visual-with-id
     (formula-transition-layer-template layer)
     name))
  (define formula-with-transform
    (visual-with-transform
     formula-with-id
     (affine-transform-lerp
      (formula-transition-layer-from-transform layer)
      (formula-transition-layer-to-transform layer)
      progress)))
  (define sampled-formula
    (visual-with-opacity
     formula-with-transform
     (real-lerp
      (formula-transition-layer-from-opacity layer)
      (formula-transition-layer-to-opacity layer)
      progress)))
  (formula-part name sampled-formula))
