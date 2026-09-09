#lang racket/base

;;;
;;; FX-F0 Unicode and Rich-Span Segmentation Tests
;;;

(require rackunit
         "../main.rkt"
         "../private/text-segmentation.rkt")

(define (contents segmentation)
  (map text-segment-content (text-segmentation-segments segmentation)))

(module+ test
  ;; Combining marks and an emoji ZWJ sequence each remain one grapheme rather
  ;; than being split at Racket string code-point boundaries.
  (define unicode (plain-text "á👩🏽‍💻 Z" #:id 'unicode))
  (define graphemes (segment-text-visual unicode #:unit 'grapheme))
  (check-equal? (contents graphemes) '("á" "👩🏽‍💻" " " "Z"))
  (check-equal? (apply string-append (contents graphemes))
                (text-visual-content unicode))
  (check-equal? (map text-segment-index (text-segmentation-segments graphemes))
                '(0 1 2 3))

  ;; Run mode retains whitespace runs as explicit source segments, including
  ;; multiple spaces, rather than discarding them between visible words.
  (define words (segment-text-visual unicode #:unit 'run))
  (check-equal? (contents words) '("á👩🏽‍💻" " " "Z"))
  (check-equal? (map text-segment-kind (text-segmentation-segments words))
                '(run whitespace run))

  ;; Line intervals include their explicit newlines, so empty lines and the
  ;; source reconstruction remain deterministic without renderer metrics.
  (define lines (segment-text-visual (paragraph "one\n\ntwo" #:id 'lines)
                                    #:unit 'line))
  (check-equal? (contents lines) '("one\n" "\n" "two"))
  (check-equal? (apply string-append (contents lines)) "one\n\ntwo")

  ;; Rich spans have stable source ranges and carry their original span index.
  (define rich
    (rich-text #:id 'rich
               (text-span "red" #:color "red")
               " "
               (text-span "blue" #:color "blue")))
  (define spans (segment-text-visual rich #:unit 'span))
  (check-equal? (contents spans) '("red" " " "blue"))
  (check-equal? (map text-segment-span-index (text-segmentation-segments spans))
                '(0 1 2))
  (check-equal? (text-segmentation-source-key spans)
                (text-segmentation-source-key
                 (segment-text-visual rich #:unit 'span)))
  (check-equal? (text-segmentation-diagnostics spans) '())

  ;; Grapheme identity follows Unicode boundaries even if an author puts a
  ;; combining mark in a different rich span from its base character.
  (define cross-span-grapheme
    (rich-text #:id 'cross-span
               (text-span "a" #:color "tomato")
               (text-span "\u0301b" #:color "navy")))
  (check-equal?
   (contents (segment-text-visual cross-span-grapheme #:unit 'grapheme))
   '("á" "b"))
  (check-exn exn:fail:contract?
             (lambda () (segment-text-visual unicode #:unit 'codepoint))))
