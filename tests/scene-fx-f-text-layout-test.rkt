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

  ;; A Pict whole layout is stable, but rich/wrapped content does not expose
  ;; exact final-shaping fragments. The protocol reports that boundary rather
  ;; than manufacturing rectangles from separately laid-out prefixes.
  (check-false (prepared-text-layout-stable-fragments? first-layout))
  (check-equal? (hash-ref (prepared-text-layout-diagnostics first-layout) 'reason)
                'pict-whole-layout-only)
  (for ([cluster (in-vector (prepared-text-layout-clusters first-layout))])
    (check-false (prepared-text-cluster-bounds cluster))
    (check-equal? (prepared-text-cluster-fragments cluster) '#()))

  ;; A grapheme crossing a rich-span boundary keeps one semantic cluster but is
  ;; not falsely advertised as an exact Pict fragment mask.
  (define cross-span
    (rich-text #:id 'cross-span #:font-size 1/2
               (text-span "a" #:color "tomato")
               (text-span "\u0301b" #:color "navy")))
  (define cross-span-layout
    (text-layout-preparer-prepare preparer cross-span camera))
  (check-false
   (prepared-text-layout-stable-fragments? cross-span-layout))
  (check-false
   (prepared-text-cluster-bounds
    (vector-ref (prepared-text-layout-clusters cross-span-layout) 0)))

  ;; One unwrapped, untransformed Pict run has a complete frozen final Pict and
  ;; compatible prefix advance measurements. Its cluster fronts are therefore
  ;; real renderer-local rectangles, while the visible glyphs still come from
  ;; the one final shaped run rather than reflowed prefixes.
  (define single-run
    (plain-text "sable" #:id 'single-run #:font-size 1/2))
  (define single-layout
    (text-layout-preparer-prepare preparer single-run camera))
  (check-true (prepared-text-layout-stable-fragments? single-layout))
  (check-equal? (vector-length (prepared-text-layout-clusters single-layout)) 5)
  (for ([cluster (in-vector (prepared-text-layout-clusters single-layout))])
    (check-true (vector? (prepared-text-cluster-bounds cluster))))
  (check-equal? (hash-ref (prepared-text-layout-diagnostics single-layout) 'reason)
                'pict-conservative-final-layout)

  ;; Initial cursor geometry is explicit renderer-local data. It remains a
  ;; valid nonempty baseline box for every anchoring mode, including empty
  ;; content where no painted cluster can supply a frontier.
  (for* ([horizontal '(left center right)]
         [vertical '(top center baseline bottom)]
         [content (list "cursor" "")])
    (define cursor-layout
      (text-layout-preparer-prepare
       preparer
       (plain-text content #:id 'cursor
                   #:horizontal-alignment horizontal
                   #:vertical-alignment vertical)
       camera))
    (define cursor-box
      (prepared-text-layout-initial-cursor-box cursor-layout))
    (check-true (vector? cursor-box))
    (check-equal? (vector-length cursor-box) 4)
    (check-true (<= (vector-ref cursor-box 1)
                    (vector-ref cursor-box 3)))
    (check-true (vector? (prepared-text-layout-anchor-offset cursor-layout))))

  ;; Common ligature/kerning-sensitive pairs must not enter the conservative
  ;; mask path merely because they are an unwrapped ASCII run.
  (for ([content '("office" "afflict" "AVATAR" "To" "Wa" "Yo")])
    (check-false
     (prepared-text-layout-stable-fragments?
      (text-layout-preparer-prepare
       preparer (plain-text content #:id 'complex) camera))))

  ;; A rotation changes local clip geometry; the current rectangular Pict-mask
  ;; protocol reports that boundary explicitly rather than presenting a
  ;; transformed, falsely aligned fragment map.
  (define rotated
    (plain-text "rotated" #:id 'rotated #:rotation 1/8))
  (check-false
   (prepared-text-layout-stable-fragments?
    (text-layout-preparer-prepare preparer rotated camera))))
