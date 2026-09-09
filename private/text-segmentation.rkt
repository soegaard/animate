#lang racket/base

;;;
;;; Immutable Unicode/rich-text segmentation
;;;

;; This module intentionally knows nothing about a renderer. It identifies
;; semantic source intervals only; a later prepared-layout stage associates
;; those intervals with shaped glyph geometry.

(require racket/list
         racket/string
         "text-visual.rkt")

(provide text-segment
         text-segment?
         text-segment-index
         text-segment-source-start
         text-segment-source-end
         text-segment-span-index
         text-segment-kind
         text-segment-content
         text-segmentation
         text-segmentation?
         text-segmentation-source-key
         text-segmentation-unit
         text-segmentation-segments
         text-segmentation-diagnostics
         segment-text-visual)

(struct text-segment
  (index source-start source-end span-index kind content)
  #:transparent)

(struct text-segmentation (source-key unit segments diagnostics)
  #:transparent)

;; segment-text-visual : text-visual? (or/c 'grapheme 'run 'line 'span)
;;                       -> text-segmentation?
;; Source positions are Racket string indexes. Grapheme iteration delegates to
;; Racket's Unicode grapheme-boundary implementation rather than splitting code
;; points, so combining sequences and emoji ZWJ clusters stay intact.
(define (segment-text-visual visual #:unit [unit 'grapheme])
  (unless (text-visual? visual)
    (raise-argument-error 'segment-text-visual "text-visual?" visual))
  (unless (memq unit '(grapheme run line span))
    (raise-argument-error 'segment-text-visual
                          "(or/c 'grapheme 'run 'line 'span)"
                          unit))
  (define content (text-visual-content visual))
  (define span-ranges (text-span-ranges visual))
  (define raw-ranges
    (case unit
      [(grapheme) (grapheme-ranges content)]
      [(run) (run-ranges content)]
      [(line) (line-ranges content)]
      [(span) span-ranges]))
  (define segments
    (for/list ([range (in-list raw-ranges)] [index (in-naturals)])
      (define start (car range))
      (define end (cdr range))
      (text-segment index start end
                    (span-index-at span-ranges start)
                    (range-kind unit content start end)
                    (substring content start end))))
  (text-segmentation
   (vector-immutable content (text-visual-spans visual))
   unit
   segments
   '()))

(define (grapheme-ranges content)
  (let loop ([start 0] [ranges '()])
    (if (= start (string-length content))
        (reverse ranges)
        (let ([span (string-grapheme-span content start)])
          (loop (+ start span) (cons (cons start (+ start span)) ranges))))))

;; This is deliberately *run* segmentation, not Unicode word segmentation.
;; Whitespace runs stay explicit so a typewriter can reveal spaces/newlines
;; without changing its source. Punctuation remains in the non-whitespace run;
;; a future genuine word-boundary mode can choose a documented whitespace rule.
(define (run-ranges content)
  (runs-by content (lambda (character) (char-whitespace? character))))

;; Newline belongs to its preceding line segment when possible. This preserves
;; the full source while retaining explicit empty lines as zero-width intervals.
(define (line-ranges content)
  (define length (string-length content))
  (let loop ([start 0] [index 0] [ranges '()])
    (cond
      [(= index length)
       (reverse (cons (cons start length) ranges))]
      [(char=? (string-ref content index) #\newline)
       (loop (add1 index) (add1 index)
             (cons (cons start (add1 index)) ranges))]
      [else (loop start (add1 index) ranges)])))

(define (runs-by content classify)
  (define length (string-length content))
  (cond
    [(zero? length) '()]
    [else
     (let loop ([start 0] [index 1]
                [classification (classify (string-ref content 0))]
                [ranges '()])
       (cond
         [(= index length)
          (reverse (cons (cons start length) ranges))]
         [(eq? classification (classify (string-ref content index)))
          (loop start (add1 index) classification ranges)]
         [else
          (loop index (add1 index)
                (classify (string-ref content index))
                (cons (cons start index) ranges))]))]))

(define (text-span-ranges visual)
  (define spans (text-visual-spans visual))
  (cond
    [(null? spans)
     (if (zero? (string-length (text-visual-content visual)))
         '()
         (list (cons 0 (string-length (text-visual-content visual)))))]
    [else
     (let loop ([remaining spans] [start 0] [ranges '()])
       (cond
         [(null? remaining) (reverse ranges)]
         [else
          (define end (+ start (string-length (text-span-content (car remaining)))))
          (loop (cdr remaining) end (cons (cons start end) ranges))]))]))

(define (span-index-at ranges position)
  (for/first ([range (in-list ranges)] [index (in-naturals)]
              #:when (and (<= (car range) position)
                          (< position (cdr range))))
    index))

(define (range-kind unit content start end)
  (case unit
    [(run)
     (if (and (< start end)
              (char-whitespace? (string-ref content start)))
         'whitespace
         'run)]
    [else unit]))
