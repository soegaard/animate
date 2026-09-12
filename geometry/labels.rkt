#lang racket/base

;; Semantic annotations are immutable geometry-dependent values, not positioned
;; text. Formatting is resolved once; placement belongs to annotations.rkt.
(require racket/list racket/string (only-in racket/math pi) "private/math.rkt")
(provide semantic-label? semantic-label-kind semantic-label-target semantic-label-text
         semantic-label-arc? label-style-type label-anchor label-angle-marker
         point-label segment-label length-label angle-label)
(struct label-value (kind target text arc?) #:transparent #:property prop:geometry-type 'Label)
(define semantic-label? label-value?)
(define semantic-label-kind label-value-kind)
(define semantic-label-target label-value-target)
(define semantic-label-text label-value-text)
(define semantic-label-arc? label-value-arc?)
(define (check-text text who)
  (unless (and (string? text) (positive? (string-length (string-trim text)))
               (not (regexp-match? #rx"[\r\n\t]" text)))
    (geometry-error who "text must be a nonempty single-line string without tabs"))
  (string->immutable-string text))
(define (check-precision n who)
  (unless (and (exact-integer? n) (<= 0 n 12)) (geometry-error who "precision must be an integer from 0 to 12")))
(define (format-decimal value precision)
  ;; `real->decimal-string` may return a dangling decimal point at precision 0
  ;; (for example "90."). Preserve its rounding, but normalize the display form.
  (define rendered (real->decimal-string value precision))
  (if (and (zero? precision) (string-suffix? rendered "."))
      (substring rendered 0 (sub1 (string-length rendered)))
      rendered))
(define (point-label p text)
  (unless (point? p) (geometry-error 'point-label "expected a Point"))
  (label-value 'point p (check-text text 'point-label) #f))
(define (segment-label s text)
  (unless (segment? s) (geometry-error 'segment-label "expected a Segment"))
  (label-value 'segment s (check-text text 'segment-label) #f))
(define (length-label s [text #f] #:precision [precision 2] #:unit [unit ""])
  (unless (segment? s) (geometry-error 'length-label "expected a Segment"))
  (check-precision precision 'length-label)
  (unless (and (string? unit) (not (regexp-match? #rx"[\r\n\t]" unit)))
    (geometry-error 'length-label "unit must be a single-line string"))
  (when (and text (not (string=? unit "")))
    (geometry-error 'length-label "#:unit is for measured labels; put units into explicit text instead"))
  (define rendered
    (or text (string-append (format-decimal (distance (segment-a s) (segment-b s)) precision)
                            (if (string=? unit "") "" (string-append " " unit)))))
  (label-value 'length s (check-text rendered 'length-label) #f))
(define (angle-label a [text #f] #:precision [precision 0] #:arc? [arc? #t])
  (unless (angle-spec? a) (geometry-error 'angle-label "expected an Angle"))
  (check-precision precision 'angle-label)
  (unless (boolean? arc?) (geometry-error 'angle-label "#:arc? must be a Boolean"))
  (define measure (angle-measure a)) ; also checks degenerate arms
  (unless (and (> measure 1e-10) (< measure (- pi 1e-10)))
    (geometry-error 'angle-label "requires a nondegenerate minor angle strictly between 0 and 180 degrees"))
  (label-value 'angle a
               (check-text (or text (string-append (format-decimal (* 180 (/ measure pi)) precision) "°")) 'angle-label)
               arc?))
(define (label-style-type v)
  (case (semantic-label-kind v)
    [(point) 'point-label] [(segment) 'segment-label] [(length) 'length-label] [else 'angle-label]))
(define (label-anchor v)
  (define target (semantic-label-target v))
  (cond [(point? target) target]
        [(segment? target) (midpoint (segment-a target) (segment-b target))]
        [else (angle-spec-b target)]))
(define (label-angle-marker v)
  (and (semantic-label? v) (eq? (semantic-label-kind v) 'angle)
       (semantic-label-arc? v) (angle-marker (semantic-label-target v))))
