#lang racket/base

;;;
;;; Conservative TeX Source Boundary Scanner
;;;

;; This is a lexical safety check for inserting fragment wrappers around
;; author-declared source ranges.  It deliberately is not a TeX parser: user
;; macros, category-code changes, and expansion semantics remain advanced
;; trusted input.  The scanner only refuses ranges that visibly split ordinary
;; TeX lexical structure.

(require racket/list
         "source-document.rkt")

(provide (struct-out tex-source-token)
         (struct-out tex-source-boundary)
         (struct-out tex-source-scan)
         scan-tex-source
         tex-source-scan-boundaries
         tex-source-boundary-at
         tex-source-span-safe?
         tex-source-span-has-visible-source?
         tex-source-span-diagnostic)


;;;
;;; Scanner Data
;;;

(struct tex-source-token (kind start end brace-depth)
  #:transparent)

;; `safe-wrap?` says a wrapper can begin/end at this boundary in isolation. A
;; candidate span must also have compatible brace depths and visible material.
(struct tex-source-boundary (index token-boundary? brace-depth safe-wrap?)
  #:transparent)

(struct tex-source-scan (text tokens boundaries diagnostics)
  #:transparent)


;;;
;;; Public Scanning and Queries
;;;

;; scan-tex-source : string? -> tex-source-scan?
(define (scan-tex-source text)
  (unless (string? text)
    (raise-argument-error 'scan-tex-source "string?" text))
  (define immutable-text (string->immutable-string text))
  (define length (string-length immutable-text))
  (define token-boundaries (make-vector (add1 length) #f))
  (define depths (make-vector (add1 length) 0))
  (define safe-wraps (make-vector (add1 length) #f))
  (define tokens-reversed '())
  (define diagnostics-reversed '())
  (define (record-token! kind start end depth)
    (set! tokens-reversed
          (cons (tex-source-token kind start end depth) tokens-reversed)))
  (define (record-boundary! index depth safe?)
    (vector-set! token-boundaries index #t)
    (vector-set! depths index depth)
    (vector-set! safe-wraps index safe?))
  (define (record-interior! start end depth)
    (for ([index (in-range (add1 start) end)])
      (unless (vector-ref token-boundaries index)
        (vector-set! depths index depth))))
  (record-boundary! 0 0 #t)
  (let loop ([index 0] [brace-depth 0])
    (cond
      [(= index length)
       (when (positive? brace-depth)
         (set! diagnostics-reversed
               (cons (format "source ends with ~a unmatched opening brace~a"
                             brace-depth
                             (if (= brace-depth 1) "" "s"))
                     diagnostics-reversed)))]
      [else
       (define character (string-ref immutable-text index))
       (define-values (kind end depth-after safe-end?)
         (cond
           ;; An unescaped percent starts a TeX comment. The newline belongs to
           ;; the comment token because TeX consumes it while terminating the
           ;; comment; no range may be wrapped through this region.
           [(char=? character #\%)
            (define comment-end
              (let find-end ([cursor (add1 index)])
                (cond
                  [(= cursor length) cursor]
                  [(char=? (string-ref immutable-text cursor) #\newline)
                   (add1 cursor)]
                  [else (find-end (add1 cursor))])))
            (values 'comment comment-end brace-depth #f)]
           ;; Control words include their whole alphabetic suffix. Control
           ;; symbols consume precisely one following character when present.
           [(char=? character #\\)
            (cond
              [(= (add1 index) length)
               (set! diagnostics-reversed
                     (cons (format "trailing TeX control escape at source index ~a" index)
                           diagnostics-reversed))
               (values 'control-symbol (add1 index) brace-depth #t)]
              [(char-alphabetic? (string-ref immutable-text (add1 index)))
               (define word-end
                 (let find-end ([cursor (+ index 2)])
                   (if (and (< cursor length)
                            (char-alphabetic? (string-ref immutable-text cursor)))
                       (find-end (add1 cursor))
                       cursor)))
               (values 'control-word word-end brace-depth #t)]
              [else
               (values 'control-symbol (+ index 2) brace-depth #t)])]
           [(char=? character #\{)
            (values 'open-brace (add1 index) (add1 brace-depth) #t)]
           [(char=? character #\})
            (if (zero? brace-depth)
                (begin
                  (set! diagnostics-reversed
                        (cons (format "unmatched closing brace at source index ~a" index)
                              diagnostics-reversed))
                  (values 'close-brace (add1 index) 0 #t))
                (values 'close-brace (add1 index) (sub1 brace-depth) #t))]
           [(char-whitespace? character)
            (values 'whitespace (add1 index) brace-depth #t)]
           [(or (char=? character #\^) (char=? character #\_))
            (values 'script-marker (add1 index) brace-depth #t)]
           [(char=? character #\$)
            (values 'math-shift (add1 index) brace-depth #t)]
           [else
            (values 'ordinary (add1 index) brace-depth #t)]))
       ;; A comment's opening percent is itself unsafe: inserting an opening
       ;; wrapper immediately before it would leave the closing wrapper inside
       ;; the comment. Its ending newline is safe again, and the next token's
       ;; start records that boundary accordingly.
       (record-boundary! index brace-depth (not (eq? kind 'comment)))
       (record-token! kind index end brace-depth)
       (record-interior! index end brace-depth)
       (record-boundary! end depth-after safe-end?)
       (loop end depth-after)]))
  ;; Every source index has a diagnostic boundary record. Interior characters
  ;; of a control word/comment are explicitly non-boundaries.
  (define boundaries
    (for/list ([index (in-range (add1 length))])
      (tex-source-boundary
       index
       (vector-ref token-boundaries index)
       (vector-ref depths index)
       (and (vector-ref token-boundaries index)
            (vector-ref safe-wraps index)))))
  (tex-source-scan immutable-text
                   (reverse tokens-reversed)
                   boundaries
                   (reverse diagnostics-reversed)))

;; tex-source-boundary-at : tex-source-scan? exact-nonnegative-integer?
;;                           -> tex-source-boundary?
(define (tex-source-boundary-at scan index)
  (check-scan 'tex-source-boundary-at scan)
  (unless (exact-nonnegative-integer? index)
    (raise-argument-error 'tex-source-boundary-at "exact-nonnegative-integer?" index))
  (define boundaries (tex-source-scan-boundaries scan))
  (unless (< index (length boundaries))
    (raise-arguments-error
     'tex-source-boundary-at
     "a source index within the scanned text, including its final boundary"
     "text-length" (string-length (tex-source-scan-text scan))
     "index" index))
  (list-ref boundaries index))

;; tex-source-span-safe? : tex-source-scan? source-span? -> boolean?
(define (tex-source-span-safe? scan span)
  (not (tex-source-span-diagnostic scan span)))

;; tex-source-span-has-visible-source? : tex-source-scan? source-span? -> boolean?
;; Reports only whether a span contains potentially ink-producing lexical
;; material. Unlike `tex-source-span-safe?`, it does not reject comments or
;; incompatible brace depths; callers use it while assigning unselected gaps
;; to adjacent rendered formula fragments.
(define (tex-source-span-has-visible-source? scan span)
  (check-scan 'tex-source-span-has-visible-source? scan)
  (check-span 'tex-source-span-has-visible-source? scan span)
  (span-has-visible-source? scan span))

;; tex-source-span-diagnostic : tex-source-scan? source-span?
;;                              -> (or/c #f immutable-string?)
;; Returns the first actionable reason a span cannot safely receive a TeX
;; fragment wrapper. An out-of-range span is an argument contract error.
(define (tex-source-span-diagnostic scan span)
  (check-scan 'tex-source-span-diagnostic scan)
  (check-span 'tex-source-span-diagnostic scan span)
  (cond
    [(= (source-span-start span) (source-span-end span))
     "source span is empty"]
    [(pair? (tex-source-scan-diagnostics scan))
     (string->immutable-string (car (tex-source-scan-diagnostics scan)))]
    [else
     (define start-boundary
       (tex-source-boundary-at scan (source-span-start span)))
     (define end-boundary
       (tex-source-boundary-at scan (source-span-end span)))
     (cond
       [(not (tex-source-boundary-token-boundary? start-boundary))
        (string->immutable-string
         (format "span starts inside a TeX token at source index ~a"
                 (source-span-start span)))]
       [(not (tex-source-boundary-token-boundary? end-boundary))
        (string->immutable-string
         (format "span ends inside a TeX token at source index ~a"
                 (source-span-end span)))]
       [(or (not (tex-source-boundary-safe-wrap? start-boundary))
            (not (tex-source-boundary-safe-wrap? end-boundary)))
        "span begins or ends in a TeX comment"]
       [(span-intersects-comment? scan span)
        "span crosses a TeX comment"]
       [(not (= (tex-source-boundary-brace-depth start-boundary)
                (tex-source-boundary-brace-depth end-boundary)))
        "span crosses an unmatched TeX brace boundary"]
       [(not (span-has-visible-source? scan span))
        "span contains no visible-producing source"]
       [else #f])]))


;;;
;;; Span Analysis
;;;

(define (span-intersects-comment? scan span)
  (for/or ([token (in-list (tex-source-scan-tokens scan))])
    (and (eq? (tex-source-token-kind token) 'comment)
         (spans-overlap? span
                         (source-span (tex-source-token-start token)
                                      (tex-source-token-end token))))))

(define (span-has-visible-source? scan span)
  (for/or ([token (in-list (tex-source-scan-tokens scan))])
    (and (visible-token? token)
         (spans-overlap? span
                         (source-span (tex-source-token-start token)
                                      (tex-source-token-end token))))))

(define (visible-token? token)
  ;; Control commands are conservatively treated as potentially ink-producing.
  ;; Some commands merely alter spacing, but rejecting them here would make
  ;; valid author-declared fragments needlessly unavailable.
  (memq (tex-source-token-kind token)
        '(control-word control-symbol ordinary)))

(define (spans-overlap? left right)
  (and (< (source-span-start left) (source-span-end right))
       (< (source-span-start right) (source-span-end left))))


;;;
;;; Validation
;;;

(define (check-scan who value)
  (unless (tex-source-scan? value)
    (raise-argument-error who "tex-source-scan?" value)))

(define (check-span who scan span)
  (unless (source-span? span)
    (raise-argument-error who "source-span?" span))
  (unless (<= (source-span-end span)
              (string-length (tex-source-scan-text scan)))
    (raise-arguments-error
     who
     "a source span within the scanned TeX source"
     "text-length" (string-length (tex-source-scan-text scan))
     "span" span)))
