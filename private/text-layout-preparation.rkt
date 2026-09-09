#lang racket/base

;;;
;;; Prepared Text Layout Protocol
;;;

;; This is a renderer-side protocol. Semantic text Visuals stay immutable and
;; renderer-neutral; a backend may prepare one stable layout snapshot and state
;; explicitly whether it can reveal shaped fragments without reflowing text.

(require racket/generic
         "text-segmentation.rkt")

(provide gen:text-layout-preparer
         text-layout-preparer?
         text-layout-preparer-supports?
         text-layout-preparer-prepare
         prepared-text-cluster
         prepared-text-cluster?
         prepared-text-cluster-segment
         prepared-text-cluster-bounds
         prepared-text-cluster-fragments
         prepared-text-cluster-baseline-data
         prepared-text-cluster-visual-order-index
         prepared-text-layout
         prepared-text-layout?
         prepared-text-layout-source-key
         prepared-text-layout-lines
         prepared-text-layout-clusters
         prepared-text-layout-bounds
         prepared-text-layout-content-bounds
         prepared-text-layout-anchor-offset
         prepared-text-layout-initial-cursor-box
         prepared-text-layout-baseline-data
         prepared-text-layout-backend-key
         prepared-text-layout-diagnostics
         prepared-text-layout-capabilities
         prepared-text-layout-stable-fragments?)

;; A cluster retains its semantic Unicode interval even when a renderer cannot
;; yet provide reliable fragment geometry. Bounds are renderer-local coordinates
;; or #f; backend diagnostics make the latter case explicit rather than letting
;; callers silently approximate it with a reflowing substring.
(struct prepared-text-cluster (segment bounds baseline-data)
  #:transparent)

;; `lines` contains semantic line segments. `bounds` and `baseline-data` are
;; backend-local immutable data; no mutable Pict, drawing context, or cache is
;; exposed through this protocol.
(struct prepared-text-layout
  (source-key lines clusters bounds baseline-data backend-key diagnostics)
  #:transparent)

;; Compatibility accessors retain the compact original representation while
;; exposing the corrected protocol vocabulary. Backends may store the richer
;; data in diagnostics until all renderers implement shaped clusters.
(define (prepared-text-cluster-fragments cluster)
  (unless (prepared-text-cluster? cluster)
    (raise-argument-error 'prepared-text-cluster-fragments
                          "prepared-text-cluster?" cluster))
  (define bounds (prepared-text-cluster-bounds cluster))
  (if (and (vector? bounds) (= (vector-length bounds) 4)
           (< (vector-ref bounds 0) (vector-ref bounds 2))
           (< (vector-ref bounds 1) (vector-ref bounds 3)))
      (vector-immutable bounds)
      '#()))

(define (prepared-text-cluster-visual-order-index cluster)
  (unless (prepared-text-cluster? cluster)
    (raise-argument-error 'prepared-text-cluster-visual-order-index
                          "prepared-text-cluster?" cluster))
  (text-segment-index (prepared-text-cluster-segment cluster)))

(define (prepared-text-layout-content-bounds layout)
  (prepared-text-layout-bounds layout))

(define (prepared-text-layout-diagnostic layout key default)
  (unless (prepared-text-layout? layout)
    (raise-argument-error 'prepared-text-layout-diagnostic
                          "prepared-text-layout?" layout))
  (if (hash? (prepared-text-layout-diagnostics layout))
      (hash-ref (prepared-text-layout-diagnostics layout) key default)
      default))

(define (prepared-text-layout-anchor-offset layout)
  (prepared-text-layout-diagnostic layout 'anchor-offset '#(0 0)))

(define (prepared-text-layout-initial-cursor-box layout)
  (prepared-text-layout-diagnostic layout 'initial-cursor-box #f))

(define (prepared-text-layout-capabilities layout)
  (prepared-text-layout-diagnostic layout 'capabilities (hasheq)))

; text-layout-preparer-supports? : text-layout-preparer? any/c any/c -> boolean?
; text-layout-preparer-prepare : text-layout-preparer? any/c any/c
;                               -> prepared-text-layout?
(define-generics text-layout-preparer
  (text-layout-preparer-supports? text-layout-preparer visual camera)
  (text-layout-preparer-prepare text-layout-preparer visual camera))

; prepared-text-layout-stable-fragments? : prepared-text-layout? -> boolean?
;; Reports the renderer capability needed by release-quality typewrite and text
;; decorations. A false result is a deliberate refusal to use substring reflow.
(define (prepared-text-layout-stable-fragments? layout)
  (unless (prepared-text-layout? layout)
    (raise-argument-error
     'prepared-text-layout-stable-fragments?
     "prepared-text-layout?"
     layout))
  (hash-ref (prepared-text-layout-capabilities layout)
            'fragment-masks-exact?
            (prepared-text-layout-diagnostic layout 'stable-fragments? #f)))
