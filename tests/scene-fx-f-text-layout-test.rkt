#lang racket/base

;;;
;;; FX-F1 Prepared Text Layout Tests
;;;

(require rackunit
         "../main.rkt"
         "../private/shape-pict-renderers.rkt"
         "../private/text-layout-preparation.rkt")

(module+ test
  (define visual
    (rich-text #:id 'caption #:font-size 1/2 #:width 3
               (text-span "cafe\u0301 " #:color "navy")
               (text-span "🙂 family" #:font-weight 'bold)))
  (define camera (make-camera #:width 640 #:height 360 #:world-width 12))
  (define preparer
    (for/first ([renderer (in-list default-pict-renderers)]
                #:when (text-layout-preparer? renderer))
      renderer))
  (check-not-false preparer)
  (check-true (text-layout-preparer-supports? preparer visual camera))
  (define first-layout
    (text-layout-preparer-prepare preparer visual camera))
  (define second-layout
    (text-layout-preparer-prepare preparer visual camera))
  (check-true (prepared-text-layout? first-layout))
  (check-equal? first-layout second-layout)
  (check-equal? (vector-length (prepared-text-layout-clusters first-layout))
                13)
  (check-true (pair? (prepared-text-layout-lines first-layout)))
  (check-equal? (vector-length (prepared-text-layout-bounds first-layout)) 4)
  (check-equal? (vector-length (prepared-text-layout-baseline-data first-layout)) 2)

  ;; Rich, wrapped source exposes final-layout cluster bounds. A typewriter can
  ;; therefore mask this one shaped layout instead of reflowing a succession of
  ;; shorter source strings.
  (check-true (prepared-text-layout-stable-fragments? first-layout))
  (check-equal? (hash-ref (prepared-text-layout-diagnostics first-layout) 'reason)
                'pict-frozen-token-layout)
  (for ([cluster (in-vector (prepared-text-layout-clusters first-layout))])
    (check-true (vector? (prepared-text-cluster-bounds cluster))))

  ;; A grapheme may cross a rich-span boundary when a combining mark carries a
  ;; different inline style. Its one semantic cluster must still receive a
  ;; final-layout mask, rather than becoming an unpainted zero-width segment.
  (define cross-span
    (rich-text #:id 'cross-span #:font-size 1/2
               (text-span "a" #:color "tomato")
               (text-span "\u0301b" #:color "navy")))
  (define cross-span-layout
    (text-layout-preparer-prepare preparer cross-span camera))
  (define cross-span-first-bounds
    (prepared-text-cluster-bounds
     (vector-ref (prepared-text-layout-clusters cross-span-layout) 0)))
  (check-true (< (vector-ref cross-span-first-bounds 0)
                 (vector-ref cross-span-first-bounds 2)))

  ;; One unwrapped, untransformed Pict run has a complete frozen final Pict and
  ;; compatible prefix advance measurements. Its cluster fronts are therefore
  ;; real renderer-local rectangles, while the visible glyphs still come from
  ;; the one final shaped run rather than reflowed prefixes.
  (define single-run
    (plain-text "office" #:id 'single-run #:font-size 1/2))
  (define single-layout
    (text-layout-preparer-prepare preparer single-run camera))
  (check-true (prepared-text-layout-stable-fragments? single-layout))
  (check-equal? (vector-length (prepared-text-layout-clusters single-layout)) 6)
  (for ([cluster (in-vector (prepared-text-layout-clusters single-layout))])
    (check-true (vector? (prepared-text-cluster-bounds cluster))))
  (check-equal? (hash-ref (prepared-text-layout-diagnostics single-layout) 'reason)
                'pict-frozen-token-layout)

  ;; A rotation changes local clip geometry; the current rectangular Pict-mask
  ;; protocol reports that boundary explicitly rather than presenting a
  ;; transformed, falsely aligned fragment map.
  (define rotated
    (plain-text "rotated" #:id 'rotated #:rotation 1/8))
  (check-false
   (prepared-text-layout-stable-fragments?
    (text-layout-preparer-prepare preparer rotated camera))))
