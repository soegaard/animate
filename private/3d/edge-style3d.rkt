#lang racket/base

;;;
;;; Mesh Outline Style
;;;

;; `edge-style3d` is an immutable declaration of which indexed mesh edges are
;; meaningful and how their visible and hidden portions should be drawn.  It
;; has no camera-dependent classification; silhouettes are selected only by a
;; renderer preparing a specific camera frame.

(require (only-in racket/math pi)
         "../geometry.rkt"
         "stroke3d.rkt")

(provide edge-style3d
         edge-style3d?
         edge-style3d-edges
         edge-style3d-visible
         edge-style3d-hidden
         edge-style3d-crease-angle
         edge-style3d-surface)

(struct edge-style3d-value (edges visible hidden crease-angle surface)
  #:transparent)

(define edge-style3d? edge-style3d-value?)
(define edge-style3d-edges edge-style3d-value-edges)
(define edge-style3d-visible edge-style3d-value-visible)
(define edge-style3d-hidden edge-style3d-value-hidden)
(define edge-style3d-crease-angle edge-style3d-value-crease-angle)
(define edge-style3d-surface edge-style3d-value-surface)

; edge-style3d : [#:edges edge-selection?]
;                [#:visible (or/c #f stroke3d?)]
;                [#:hidden (or/c #f stroke3d?)]
;                [#:crease-angle finite-nonnegative-real?]
;                [#:surface (or/c 'visible 'depth-only 'none)] -> edge-style3d?
(define (edge-style3d #:edges [edges 'feature]
                      #:visible [visible (stroke3d #:color "black" #:width 2 #:depth-mode 'test)]
                      #:hidden [hidden #f]
                      #:crease-angle [crease-angle (/ pi 6)]
                      #:surface [surface 'visible])
  (unless (memq edges '(explicit all boundary crease silhouette feature))
    (raise-argument-error 'edge-style3d
                          "one of 'explicit, 'all, 'boundary, 'crease, 'silhouette, or 'feature"
                          edges))
  (unless (or (not visible) (stroke3d? visible))
    (raise-argument-error 'edge-style3d "(or/c #f stroke3d?) as #:visible" visible))
  (unless (or (not hidden) (stroke3d? hidden))
    (raise-argument-error 'edge-style3d "(or/c #f stroke3d?) as #:hidden" hidden))
  (unless (and (finite-real? crease-angle) (<= 0 crease-angle pi))
    (raise-argument-error 'edge-style3d "finite angle in [0, pi]" crease-angle))
  (unless (memq surface '(visible depth-only none))
    (raise-argument-error 'edge-style3d "one of 'visible, 'depth-only, or 'none" surface))
  (edge-style3d-value edges visible hidden crease-angle surface))
