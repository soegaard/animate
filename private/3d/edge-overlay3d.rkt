#lang racket/base

;;;
;;; Path-Transparent Mesh Outline Wrapper
;;;

;; The wrapper deliberately has the same spatial identity, transform, opacity,
;; and bounds as its mesh.  It therefore adds no artificial path component:
;; `(with-edges3d cube ...)` keeps the cube addressable at `(world cube)`.

(require (only-in racket/generic define/generic)
         (only-in racket/math pi)
         "edge-style3d.rkt"
         "mesh3d.rkt"
         "spatial-visual.rkt"
         "stroke3d.rkt"
         "transform3.rkt")

(provide with-edges3d
         edge-overlay3d?
         edge-overlay3d-content
         edge-overlay3d-style)

(struct edge-overlay3d-value (content style)
  #:transparent
  #:methods gen:spatial-visual
  [(define/generic generic-spatial-id spatial-id)
   (define/generic generic-spatial-transform spatial-transform)
   (define/generic generic-spatial-with-transform spatial-with-transform)
   (define/generic generic-spatial-opacity spatial-opacity)
   (define/generic generic-spatial-with-opacity spatial-with-opacity)
   (define/generic generic-spatial-local-bounds spatial-local-bounds)
   (define (spatial-id value) (generic-spatial-id (edge-overlay3d-value-content value)))
   (define (spatial-transform value) (generic-spatial-transform (edge-overlay3d-value-content value)))
   (define (spatial-with-transform value transform)
     (unless (transform3? transform)
       (raise-argument-error 'spatial-with-transform "transform3?" transform))
     (struct-copy edge-overlay3d-value value
                  [content (generic-spatial-with-transform (edge-overlay3d-value-content value)
                                                           transform)]))
   (define (spatial-opacity value) (generic-spatial-opacity (edge-overlay3d-value-content value)))
   (define (spatial-with-opacity value opacity)
     (struct-copy edge-overlay3d-value value
                  [content (generic-spatial-with-opacity (edge-overlay3d-value-content value)
                                                         opacity)]))
   (define (spatial-local-bounds value)
     (generic-spatial-local-bounds (edge-overlay3d-value-content value)))])

(define edge-overlay3d? edge-overlay3d-value?)
(define edge-overlay3d-content edge-overlay3d-value-content)
(define edge-overlay3d-style edge-overlay3d-value-style)

; with-edges3d : mesh3d? ... -> edge-overlay3d?
(define (with-edges3d mesh
                      #:edges [edges 'feature]
                      #:visible [visible (stroke3d #:color "black" #:width 2 #:depth-mode 'test)]
                      #:hidden [hidden #f]
                      #:crease-angle [crease-angle (/ pi 6)]
                      #:surface [surface 'visible])
  (unless (mesh3d? mesh)
    (raise-argument-error 'with-edges3d "mesh3d?" mesh))
  (edge-overlay3d-value
   mesh
   (edge-style3d #:edges edges #:visible visible #:hidden hidden
                 #:crease-angle crease-angle #:surface surface)))
