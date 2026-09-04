#lang racket/base

;;;
;;; Canonical Mathematical Source Documents
;;;

;; A source document gives source-addressing features one documented coordinate
;; system.  Its spans use Racket string-character indices and are half-open:
;; [start, end).  This module is deliberately independent of TeX, formulas,
;; renderers, and scenes.

(require racket/list
         racket/string)

(provide (struct-out source-span)
         (struct-out source-document)
         source-document-from-strings
         source-document-length
         source-document-valid-span?
         source-document-span-text)


;;;
;;; Source Spans
;;;

(struct source-span (start end)
  #:transparent
  #:guard
  (lambda (start end type-name)
    (unless (exact-nonnegative-integer? start)
      (raise-argument-error type-name "exact-nonnegative-integer?" start))
    (unless (exact-nonnegative-integer? end)
      (raise-argument-error type-name "exact-nonnegative-integer?" end))
    (unless (<= start end)
      (raise-arguments-error
       type-name
       "a half-open source range whose start does not exceed its end"
       "start" start
       "end" end))
    (values start end)))

;; A source-span denotes [start, end) in a canonical source string.  Empty
;; spans are useful to describe empty source arguments, but a source selector
;; later rejects them because it cannot select visible material.


;;;
;;; Source Documents
;;;

(struct source-document (text argument-spans separator)
  #:transparent
  #:guard
  (lambda (text argument-spans separator type-name)
    (unless (string? text)
      (raise-argument-error type-name "string?" text))
    (unless (and (list? argument-spans)
                 (andmap source-span? argument-spans))
      (raise-argument-error type-name "list of source-span? values" argument-spans))
    (unless (string? separator)
      (raise-argument-error type-name "string?" separator))
    (define immutable-text (string->immutable-string text))
    (define immutable-separator (string->immutable-string separator))
    (for ([span (in-list argument-spans)])
      (unless (source-document-valid-span?* immutable-text span)
        (raise-arguments-error
         type-name
         "argument spans within the canonical source text"
         "text-length" (string-length immutable-text)
         "argument-span" span)))
    (unless (nonoverlapping-in-source-order? argument-spans)
      (raise-arguments-error
       type-name
       "argument spans in non-overlapping source order"
       "argument-spans" argument-spans))
    (values immutable-text argument-spans immutable-separator)))

;; source-document-from-strings : (listof string?) [#:separator string?]
;;                                 -> source-document?
;; Joins the source arguments exactly once, retaining the location of every
;; original argument.  The separator is part of the canonical source and is
;; therefore addressable by exact spans, although later formula constructors
;; may choose to reject it as a declared rendered part.
(define (source-document-from-strings strings #:separator [separator " "])
  (unless (and (pair? strings) (andmap string? strings))
    (raise-argument-error
     'source-document-from-strings
     "nonempty list of strings"
     strings))
  (unless (string? separator)
    (raise-argument-error 'source-document-from-strings "string?" separator))
  (define spans
    (let loop ([remaining strings] [start 0] [reversed '()])
      (cond
        [(null? remaining) (reverse reversed)]
        [else
         (define source (car remaining))
         (define end (+ start (string-length source)))
         (loop (cdr remaining)
               (+ end (if (null? (cdr remaining))
                          0
                          (string-length separator)))
               (cons (source-span start end) reversed))])))
  (source-document (string-join strings separator) spans separator))

;; source-document-length : source-document? -> exact-nonnegative-integer?
(define (source-document-length document)
  (check-source-document 'source-document-length document)
  (string-length (source-document-text document)))

;; source-document-valid-span? : source-document? source-span? -> boolean?
;; Reports range validity only.  In particular, it permits an empty span.
(define (source-document-valid-span? document span)
  (check-source-document 'source-document-valid-span? document)
  (unless (source-span? span)
    (raise-argument-error 'source-document-valid-span? "source-span?" span))
  (source-document-valid-span?* (source-document-text document) span))

;; source-document-span-text : source-document? source-span? -> immutable-string?
;; Extracts a valid source span.  It deliberately permits an empty span so
;; callers inspecting original source argument boundaries can use it directly.
(define (source-document-span-text document span)
  (check-source-document 'source-document-span-text document)
  (unless (source-span? span)
    (raise-argument-error 'source-document-span-text "source-span?" span))
  (unless (source-document-valid-span? document span)
    (raise-arguments-error
     'source-document-span-text
     "a source span within the canonical source text"
     "text-length" (source-document-length document)
     "span" span))
  (string->immutable-string
   (substring (source-document-text document)
              (source-span-start span)
              (source-span-end span))))


;;;
;;; Internal Validation
;;;

(define (source-document-valid-span?* text span)
  (<= (source-span-end span) (string-length text)))

(define (nonoverlapping-in-source-order? spans)
  (for/fold ([previous-end 0] [ordered? #t] #:result ordered?)
            ([span (in-list spans)])
    (values (source-span-end span)
            (and ordered?
                 (<= previous-end (source-span-start span))))))

(define (check-source-document who value)
  (unless (source-document? value)
    (raise-argument-error who "source-document?" value)))
