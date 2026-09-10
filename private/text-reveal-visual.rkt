#lang racket/base

;;;
;;; Temporary Text-Reveal Visual
;;;

;; A renderer-facing wrapper for a frozen source text Visual. It is never an
;; authored endpoint: typewrite installs it only during an open clip interval
;; and restores the original text-visual exactly at completion.

(require (only-in racket/generic define/generic)
         "semantic-text-visual.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

(provide text-reveal-visual
         text-reveal-visual?
         text-reveal-visual-source
         text-reveal-visual-unit
         text-reveal-visual-revealed-count
         text-reveal-visual-segment-count
         text-reveal-visual-cursor?
         text-reveal-visual-cursor-style
         make-text-reveal-visual)

(struct text-reveal-visual
  (id source unit revealed-count segment-count cursor? cursor-style)
  #:transparent
  #:guard
  (lambda (id source unit revealed-count segment-count cursor? cursor-style who)
    (unless (symbol? id)
      (raise-argument-error who "symbol?" id))
    (unless (textual-visual? source)
      (raise-argument-error who "textual-visual?" source))
    (unless (memq unit '(grapheme run line span))
      (raise-argument-error
       who
       "(or/c 'grapheme 'run 'line 'span)"
       unit))
    (unless (and (exact-integer? revealed-count)
                 (not (negative? revealed-count))
                 (exact-integer? segment-count)
                 (not (negative? segment-count))
                 (<= revealed-count segment-count))
      (raise-arguments-error
       who
       "segment counts in the closed interval [0, segment-count]"
       "revealed-count" revealed-count
       "segment-count" segment-count))
    (unless (boolean? cursor?)
      (raise-argument-error who "boolean? as cursor?" cursor?))
    ;; `cursor-style` is validated by the public request constructors. The
    ;; renderer wrapper retains it as inert semantic style data so that a
    ;; backend can choose its own drawing representation without storing a
    ;; drawing context or mutable cursor object in a Scene.
    (values id source unit revealed-count segment-count cursor? cursor-style))
  #:methods gen:visual
  [(define/generic source-position visual-position)
   (define/generic source-with-position visual-with-position)
   (define (visual-id visual) (text-reveal-visual-id visual))
   (define (visual-position visual)
     (source-position (text-reveal-visual-source visual)))
   (define (visual-with-position visual position)
     (struct-copy text-reveal-visual visual
                  [source
                   (source-with-position (text-reveal-visual-source visual)
                                         position)]))]
  #:methods gen:affine-visual
  [(define/generic source-transform visual-transform)
   (define/generic source-with-transform visual-with-transform)
   (define (visual-transform visual)
     (source-transform (text-reveal-visual-source visual)))
   (define (visual-with-transform visual transform)
     (struct-copy text-reveal-visual visual
                  [source
                   (source-with-transform (text-reveal-visual-source visual)
                                          transform)]))]
  #:methods gen:opacity-visual
  [(define/generic source-opacity visual-opacity)
   (define/generic source-with-opacity visual-with-opacity)
   (define (visual-opacity visual)
     (source-opacity (text-reveal-visual-source visual)))
   (define (visual-with-opacity visual opacity)
     (struct-copy text-reveal-visual visual
                  [source
                   (source-with-opacity (text-reveal-visual-source visual)
                                        opacity)]))])

(define (make-text-reveal-visual source unit revealed-count segment-count
                                 #:cursor? [cursor? #f]
                                 #:cursor-style [cursor-style #f])
  (text-reveal-visual (visual-id source)
                      source
                      unit
                      revealed-count
                      segment-count
                      cursor?
                      cursor-style))
