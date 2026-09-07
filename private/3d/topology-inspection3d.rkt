#lang racket/base

;;; Immutable topology explanation for exact spatial picks

;; This module is intentionally a tiny read-only bridge between the generic
;; mesh-picking result and an inspector client. The preview, a REPL, and a
;; headless tool therefore agree on one stable topology report instead of each
;; decoding extension metadata independently.

(require "spatial-inspection.rkt")

(provide (struct-out topology-inspection3d)
         spatial-pick-topology-inspection3d)

;; `topology` is the immutable mesh report recorded by `spatial-pick`; its
;; diagnostics remain values, rather than presentation strings, so clients can
;; choose whether a nonmanifold condition is a warning row, a coloured overlay,
;; or a serialized diagnostic.
(struct topology-inspection3d
  (path semantic-vertex-ids semantic-edge-ids
        nearest-vertex-id nearest-edge-id nearest-edge-incident-face-ids
        render-triangle-id polygonal-face-id polygonal-face-policy
        connected-component boundary-components topology)
  #:transparent)

;; spatial-pick-topology-inspection3d : spatial-pick?
;;                                        -> (or/c #f topology-inspection3d?)
;; Returns #f for strokes, markers, and other non-mesh primitive picks. It
;; never traverses, augments, or otherwise changes an authored spatial tree.
(define (spatial-pick-topology-inspection3d pick)
  (unless (spatial-pick? pick)
    (raise-argument-error 'spatial-pick-topology-inspection3d "spatial-pick?" pick))
  (define metadata (spatial-pick-metadata pick))
  (define topology (hash-ref metadata 'topology #f))
  (and (eq? (spatial-pick-kind pick) 'mesh-triangle)
       (hash? topology)
       (topology-inspection3d
        (spatial-pick-path pick)
        (hash-ref metadata 'semantic-vertex-ids '#())
        (hash-ref metadata 'semantic-edge-ids '#())
        (hash-ref metadata 'nearest-semantic-vertex-id #f)
        (hash-ref metadata 'nearest-semantic-edge-id #f)
        (hash-ref metadata 'nearest-edge-incident-face-ids '#())
        (hash-ref metadata 'render-triangle-id #f)
        (hash-ref metadata 'semantic-polygonal-face-id #f)
        (hash-ref metadata 'polygonal-face-policy #f)
        (hash-ref metadata 'connected-component #f)
        (hash-ref metadata 'boundary-components '#())
        topology)))
