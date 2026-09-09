#lang racket/base

;;;
;;; Immutable Animation Inspection Metadata
;;;

;; Animation requests and compiled animations may carry a small immutable
;; explanation value.  It is intentionally independent of rendering, preview
;; widgets, and formula implementation details: the compiler stores it once and
;; the headless inspector can retrieve it from the active clip.

(require racket/generic)

(provide gen:animation-inspection
         animation-inspection?
         animation-inspection-kind
         animation-inspection-data
         animation-inspection-with-provenance
         string-transition-inspection-with-compiled-plan
         (struct-out string-transition-inspection))

(define-generics animation-inspection
  (animation-inspection-kind animation-inspection)
  (animation-inspection-data animation-inspection))

;; Keep these calls outside a `gen:animation-inspection` method body.  Inside a
;; method the generated method binding shadows the generic identifier, which
;; would otherwise try to apply the provenance accessor to the wrapped base.
(define (base-inspection-kind inspection)
  (animation-inspection-kind inspection))

(define (base-inspection-data inspection)
  (animation-inspection-data inspection))

;; A scene scheduler owns expansion provenance, while individual animation
;; implementations own their effect-specific explanation.  This small generic
;; wrapper combines both without forcing every effect inspection struct to know
;; about a scheduler or a preview.
(struct provenance-animation-inspection (base provenance)
  #:transparent
  #:methods gen:animation-inspection
  [(define (animation-inspection-kind inspection)
     (base-inspection-kind
      (provenance-animation-inspection-base inspection)))
   (define (animation-inspection-data inspection)
     (define data
       (base-inspection-data
        (provenance-animation-inspection-base inspection)))
     (if (hash? data)
         (hash-set data
                   'expansion-origin
                   (provenance-animation-inspection-provenance inspection))
         (hasheq 'effect-data data
                 'expansion-origin
                 (provenance-animation-inspection-provenance inspection))))])

; animation-inspection-with-provenance : animation-inspection? any/c
;                                         -> animation-inspection?
;; Returns a generic inspection whose data retains the immutable scheduler
;; origin alongside the effect's own data.
(define (animation-inspection-with-provenance inspection provenance)
  (unless (animation-inspection? inspection)
    (raise-argument-error
     'animation-inspection-with-provenance "animation-inspection?" inspection))
  (provenance-animation-inspection inspection provenance))

;; string-transition-inspection retains the exact plan calculated by
;; transform-matching-strings or rewrite-matching-strings. `options` is an
;; immutable author-facing datum describing the planner inputs. Compilation
;; fills target-id and compiled-plan once, giving a preview access to exact
;; world-relative route geometry without reconstructing the planner per frame.
(struct string-transition-inspection
  (plan source destination options target-id compiled-plan)
  #:transparent
  #:methods gen:animation-inspection
  [(define (animation-inspection-kind _inspection) 'string-transition)
   (define (animation-inspection-data inspection)
     (hasheq 'plan (string-transition-inspection-plan inspection)
             'source (string-transition-inspection-source inspection)
             'destination (string-transition-inspection-destination inspection)
             'options (string-transition-inspection-options inspection)
             'target-id (string-transition-inspection-target-id inspection)
             'compiled-plan (string-transition-inspection-compiled-plan inspection)))])

;; Adds only compiler-owned data to an immutable author-plan explanation. A
;; non-string inspection is returned untouched so generic animation inspection
;; remains extensible and does not need formula dependencies.
(define (string-transition-inspection-with-compiled-plan inspection target-id compiled-plan)
  (cond
    [(string-transition-inspection? inspection)
     (unless (symbol? target-id)
       (raise-argument-error
        'string-transition-inspection-with-compiled-plan "symbol?" target-id))
     (struct-copy string-transition-inspection inspection
                  [target-id target-id]
                  [compiled-plan compiled-plan])]
    [else inspection]))
