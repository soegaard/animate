#lang racket/base

;;;
;;; Deterministic Mathematical Source Selectors
;;;

;; Selector resolution operates solely on canonical source strings.  It does
;; not parse TeX, infer algebraic meaning, or inspect rendered glyphs.

(require racket/list
         "source-document.rkt")

(provide (struct-out source-occurrence)
         (struct-out source-part)
         source-selector?
         resolve-source-selector)


;;;
;;; Selector Values
;;;

(define (atomic-source-selector? value)
  (or (string? value)
      (regexp? value)
      (source-span? value)))

(struct source-occurrence (selector index)
  #:transparent
  #:guard
  (lambda (selector index type-name)
    (unless (atomic-source-selector? selector)
      (raise-argument-error
       type-name
       "string?, regexp?, or source-span?"
       selector))
    (unless (exact-nonnegative-integer? index)
      (raise-argument-error type-name "exact-nonnegative-integer?" index))
    (values selector index)))

(struct source-part (name selector)
  #:transparent
  #:guard
  (lambda (name selector type-name)
    (unless (symbol? name)
      (raise-argument-error type-name "symbol?" name))
    (unless (atomic-source-selector? selector)
      (raise-argument-error
       type-name
       "string?, regexp?, or source-span?"
       selector))
    (values name selector)))

;; source-selector? : any/c -> boolean?
;; A source part supplies an author-facing stable name, while an occurrence
;; selects one zero-based result from an atomic selector.  Nesting either form
;; would make the occurrence/counting semantics unclear, so it is rejected at
;; construction time.
(define (source-selector? value)
  (or (atomic-source-selector? value)
      (source-occurrence? value)
      (source-part? value)))


;;;
;;; Resolution
;;;

;; resolve-source-selector : source-document? source-selector?
;;                           [#:protected (listof source-span?)]
;;                           -> (listof source-span?)
;; Resolves literal strings and regexps from left to right with non-overlapping
;; matches.  Protected spans suppress automatic literal/regexp matches but
;; never override an explicit source-span selector.  The result is ordered by
;; start and then end, with duplicate spans removed.
(define (resolve-source-selector document selector #:protected [protected '()])
  (unless (source-document? document)
    (raise-argument-error 'resolve-source-selector "source-document?" document))
  (unless (source-selector? selector)
    (raise-argument-error 'resolve-source-selector "source-selector?" selector))
  (unless (and (list? protected) (andmap source-span? protected))
    (raise-argument-error
     'resolve-source-selector
     "list of source-span? values"
     protected))
  (for ([span (in-list protected)])
    (check-document-span 'resolve-source-selector document span #:allow-empty? #t))
  (normalize-spans
   (resolve-selector document selector protected)))

(define (resolve-selector document selector protected)
  (cond
    [(source-part? selector)
     (resolve-atomic-selector document (source-part-selector selector) protected)]
    [(source-occurrence? selector)
     (define matches
       (resolve-atomic-selector document
                                (source-occurrence-selector selector)
                                protected))
     (define index (source-occurrence-index selector))
     (unless (< index (length matches))
       (raise-arguments-error
        'resolve-source-selector
        "an occurrence index within the resolved source matches"
        "selector" (source-occurrence-selector selector)
        "occurrence-index" index
        "match-count" (length matches)))
     (list (list-ref matches index))]
    [else
     (resolve-atomic-selector document selector protected)]))

(define (resolve-atomic-selector document selector protected)
  (cond
    [(source-span? selector)
     (check-document-span 'resolve-source-selector document selector)
     (list selector)]
    [(string? selector)
     (when (zero? (string-length selector))
       (raise-arguments-error
        'resolve-source-selector
        "a nonempty literal source selector"
        "selector" selector))
     (remove-protected
      (literal-match-spans (source-document-text document) selector)
      protected)]
    [(regexp? selector)
     (remove-protected
      (regexp-match-spans (source-document-text document) selector)
      protected)]
    [else
     ;; All constructors maintain the selector invariant, but keeping this
     ;; defensive branch makes failures from future selector extensions local.
     (raise-argument-error
      'resolve-source-selector
      "string?, regexp?, or source-span?"
      selector)]))


;;;
;;; Match Discovery
;;;

(define (literal-match-spans text literal)
  (define literal-length (string-length literal))
  (let loop ([start 0] [reversed '()])
    (define found (next-literal-index text literal start))
    (cond
      [(not found) (reverse reversed)]
      [else
       ;; Advancing by the complete literal length establishes the documented
       ;; left-to-right, non-overlapping policy for repeated source strings.
       (loop (+ found literal-length)
             (cons (source-span found (+ found literal-length)) reversed))])))

(define (next-literal-index text literal start)
  (define text-length (string-length text))
  (define literal-length (string-length literal))
  (let loop ([index start])
    (cond
      [(> (+ index literal-length) text-length) #f]
      [(string=? literal (substring text index (+ index literal-length))) index]
      [else (loop (add1 index))])))

(define (regexp-match-spans text selector)
  (define positions (regexp-match-positions* selector text))
  (define spans
    (for/list ([position (in-list positions)])
      ;; regexp-match-positions* returns the whole-match range first; capture
      ;; groups are not independently selectable source occurrences.
      (define start (car position))
      (define end (cdr position))
      (when (= start end)
        (raise-arguments-error
         'resolve-source-selector
         "a regexp selector that never produces an empty match"
         "selector" selector
         "empty-match-span" (source-span start end)))
      (source-span start end)))
  spans)


;;;
;;; Normalization and Protection
;;;

(define (remove-protected spans protected)
  (for/list ([span (in-list spans)]
             #:unless (for/or ([protected-span (in-list protected)])
                        (spans-overlap? span protected-span)))
    span))

(define (spans-overlap? left right)
  (and (< (source-span-start left) (source-span-end right))
       (< (source-span-start right) (source-span-end left))))

(define (normalize-spans spans)
  (remove-duplicates
   (sort spans
         (lambda (left right)
           (or (< (source-span-start left) (source-span-start right))
               (and (= (source-span-start left) (source-span-start right))
                    (< (source-span-end left) (source-span-end right))))))))

(define (check-document-span who document span #:allow-empty? [allow-empty? #f])
  (unless (source-document-valid-span? document span)
    (raise-arguments-error
     who
     "a source span within the canonical source text"
     "text-length" (source-document-length document)
     "span" span))
  (when (and (not allow-empty?)
             (= (source-span-start span) (source-span-end span)))
    (raise-arguments-error
     who
     "a nonempty source span"
     "span" span)))
