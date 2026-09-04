#lang racket/base

;;;
;;; Formula Source-Map Data
;;;

;; This module owns immutable source-to-local-leaf metadata. It has no
;; dependency on formula Visual representations, so formula assemblies can
;; retain a map without creating a cyclic model dependency.

(require racket/list
         "source-document.rkt"
         "source-selector.rkt"
         "tex-source-scanner.rkt")

(provide (struct-out formula-source-match)
         formula-source-map?
         make-formula-source-map
         formula-source-map-document
         formula-source-map-matches
         formula-source-map-find)


;;;
;;; Data Representation
;;;

;; Paths are relative to the owning formula assembly. A source map records
;; only semantic correspondence; the formula-specific layer turns these paths
;; into root-relative visual selections once it knows the assembly's ID.
(struct formula-source-match (span text name relative-paths)
  #:transparent
  #:guard
  (lambda (span text name relative-paths type-name)
    (unless (source-span? span)
      (raise-argument-error type-name "source-span?" span))
    (unless (string? text)
      (raise-argument-error type-name "string?" text))
    (unless (symbol? name)
      (raise-argument-error type-name "symbol?" name))
    (unless (and (list? relative-paths)
                 (pair? relative-paths)
                 (andmap relative-visual-path? relative-paths))
      (raise-argument-error
       type-name
       "nonempty list of relative Visual paths"
       relative-paths))
    (values span
            (string->immutable-string text)
            name
            (remove-duplicates relative-paths equal?))))

(struct formula-source-map-data (document matches)
  #:transparent
  #:guard
  (lambda (document matches type-name)
    (unless (source-document? document)
      (raise-argument-error type-name "source-document?" document))
    (unless (and (list? matches)
                 (andmap formula-source-match? matches))
      (raise-argument-error type-name "list of formula-source-match? values" matches))
    (for ([match (in-list matches)])
      (unless (source-document-valid-span? document
                                           (formula-source-match-span match))
        (raise-arguments-error
         type-name
         "source matches within the canonical source document"
         "match" match
         "source-length" (source-document-length document)))
      (when (= (source-span-start (formula-source-match-span match))
               (source-span-end (formula-source-match-span match)))
        (raise-arguments-error
         type-name
         "nonempty source matches"
         "match" match))
      (unless (string=? (formula-source-match-text match)
                         (source-document-span-text
                          document
                          (formula-source-match-span match)))
        (raise-arguments-error
         type-name
         "source matches whose text agrees with the canonical source document"
         "match" match
         "source-text"
         (source-document-span-text document
                                    (formula-source-match-span match))))
      )
    (unless (matches-in-source-order? matches)
      (raise-arguments-error
       type-name
       "non-overlapping source matches in source order"
       "matches" matches))
    (unless (= (length matches)
               (length (remove-duplicates
                        (map formula-source-match-name matches))))
      (raise-arguments-error
       type-name
       "source matches with unique stable names"
       "matches" matches))
    (values document matches)))

;; The public API uses `formula-source-map` for the formula query operation,
;; so the data constructor has a private implementation name.
(define formula-source-map? formula-source-map-data?)

(define (make-formula-source-map document matches)
  (formula-source-map-data document matches))

(define (formula-source-map-document mapping)
  (check-map 'formula-source-map-document mapping)
  (formula-source-map-data-document mapping))

(define (formula-source-map-matches mapping)
  (check-map 'formula-source-map-matches mapping)
  (formula-source-map-data-matches mapping))


;;;
;;; Source Queries
;;;

;; formula-source-map-find : formula-source-map? source-selector?
;;                           -> (listof formula-source-match?)
;; A query may address a subrange inside a declared source part. In declared
;; mode that part is the smallest renderable unit, so its complete local leaf
;; path is returned. A query spanning several parts returns every overlapping
;; leaf in source order; it never fabricates a synthetic formula group.
(define (formula-source-map-find mapping selector)
  (check-map 'formula-source-map-find mapping)
  (unless (source-selector? selector)
    (raise-argument-error 'formula-source-map-find "source-selector?" selector))
  (define selected-spans
    (resolve-source-selector (formula-source-map-document mapping) selector))
  (define scan
    (scan-tex-source
     (source-document-text (formula-source-map-document mapping))))
  (for/list ([match (in-list (formula-source-map-matches mapping))]
             #:when (for/or ([selected (in-list selected-spans)])
                      (and (tex-source-span-safe? scan selected)
                           (spans-overlap?
                            (formula-source-match-span match)
                            selected))))
    match))


;;;
;;; Internal Helpers
;;;

(define (relative-visual-path? value)
  (and (list? value)
       (andmap symbol? value)))

(define (matches-in-source-order? matches)
  (for/fold ([previous-end 0] [ordered? #t] #:result ordered?)
            ([match (in-list matches)])
    (define span (formula-source-match-span match))
    (values (source-span-end span)
            (and ordered?
                 (<= previous-end (source-span-start span))))))

(define (spans-overlap? left right)
  (and (< (source-span-start left) (source-span-end right))
       (< (source-span-start right) (source-span-end left))))

(define (check-map who value)
  (unless (formula-source-map? value)
    (raise-argument-error who "formula-source-map?" value)))
