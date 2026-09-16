#lang racket/base

;;;
;;; Mathematical Gallery Catalogue
;;;
;; One ordered registry drives selection, documentation, scene preparation, and
;; regression review. Loading the catalogue performs no external work.

;;;
;;; Imports and Exports
;;;
(require (only-in racket/list remove-duplicates)
         "model.rkt" "held.rkt" "selection.rkt" "conditions.rkt" "moves.rkt" "presentation.rkt")
(provide gallery-plates gallery-chapters select-gallery-plates)

; gallery-chapters : (listof (cons/c symbol? string?))
;;   Orders the five teaching chapters and their human-readable names.
(define gallery-chapters
  '((held . "Held expressions and precise operations")
    (selection . "Selection, provenance, and rewriting")
    (conditions . "Conditions and alternatives")
    (moves . "Named moves and reusable recipes")
    (presentation . "Presentation and choreography")))

; gallery-plates : (listof gallery-plate?)
;;   Lists all independently selectable plates in chapter and teaching order.
(define gallery-plates
  (append held-plates selection-plates condition-plates move-plates presentation-plates))

; select-gallery-plates : [#:plates (or/c #f list?)] [#:chapter (or/c #f symbol?)] -> list?
;;   Resolves a nonempty canonical-order selection and rejects typos, repeats, and conflicts.
(define (select-gallery-plates #:plates [ids #f] #:chapter [chapter #f])
  (when (and chapter (not (assq chapter gallery-chapters)))
    (raise-arguments-error 'select-gallery-plates "unknown chapter" "chapter" chapter))
  (when ids
    (unless (and (list? ids) (pair? ids) (andmap gallery-safe-id? ids)
                 (= (length ids) (length (remove-duplicates ids))))
      (raise-argument-error 'select-gallery-plates "nonempty list of unique plate ids" ids))
    (for ([id (in-list ids)])
      (define plate (findf (lambda (p) (eq? id (gallery-plate-id p))) gallery-plates))
      (unless plate (raise-arguments-error 'select-gallery-plates "unknown plate" "plate" id))
      (when (and chapter (not (eq? chapter (gallery-plate-chapter plate))))
        (raise-arguments-error 'select-gallery-plates "plate is not in selected chapter"
                               "plate" id "chapter" chapter))))
  (filter (lambda (plate)
            (and (or (not chapter) (eq? chapter (gallery-plate-chapter plate)))
                 (or (not ids) (memq (gallery-plate-id plate) ids))))
          gallery-plates))
