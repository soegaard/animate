#lang racket/base

;;;
;;; Prepared Text Layout Protocol
;;;

;; This is a renderer-side protocol. Semantic text Visuals stay immutable and
;; renderer-neutral; a backend may prepare one stable layout snapshot and state
;; explicitly whether it can reveal shaped fragments without reflowing text.

(require racket/generic)

(provide gen:text-layout-preparer
         text-layout-preparer?
         text-layout-preparer-supports?
         text-layout-preparer-prepare
         prepared-text-cluster
         prepared-text-cluster?
         prepared-text-cluster-segment
         prepared-text-cluster-bounds
         prepared-text-cluster-baseline-data
         prepared-text-layout
         prepared-text-layout?
         prepared-text-layout-source-key
         prepared-text-layout-lines
         prepared-text-layout-clusters
         prepared-text-layout-bounds
         prepared-text-layout-baseline-data
         prepared-text-layout-backend-key
         prepared-text-layout-diagnostics
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
  (and (hash? (prepared-text-layout-diagnostics layout))
       (hash-ref (prepared-text-layout-diagnostics layout)
                 'stable-fragments?
                 #f)))
