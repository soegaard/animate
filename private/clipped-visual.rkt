#lang racket/base

;;;
;;; Semantic visual clipping
;;;

;; A clipped Visual is a normal immutable world-space composite. Its content
;; lives in the wrapper's local coordinate system, just as a child of `group`
;; does; its clip is an immutable local path-geometry. Rendering is deferred to
;; the Pict adapter so clipping never turns semantic geometry into a bitmap.

(require "affine-transform.rkt"
         "geometry.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

(provide clipped-visual?
         clipped-visual-content
         clipped-visual-path
         clip-visual)

(struct clipped-visual (id transform opacity content path)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual) (clipped-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation (clipped-visual-transform visual)))
   (define (visual-with-position visual position)
     (check-vec2 'visual-with-position position)
     (struct-copy clipped-visual visual
                  [transform
                   (affine-transform-with-translation
                    (clipped-visual-transform visual) position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform visual) (clipped-visual-transform visual))
   (define (visual-with-transform visual transform)
     (unless (affine-transform? transform)
       (raise-argument-error 'visual-with-transform "affine-transform?" transform))
     (struct-copy clipped-visual visual [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual) (clipped-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (unless (opacity? opacity)
       (raise-argument-error 'visual-with-opacity "opacity?" opacity))
     (struct-copy clipped-visual visual [opacity opacity]))])

;; clip-visual : affine-visual? path-geometry? #:id symbol? ... -> clipped-visual?
;; Constructs a local semantic composite. The wrapped content is not added to
;; the scene separately; its own transform remains meaningful inside the clip.
(define (clip-visual content path
                     #:id id
                     #:center [center origin]
                     #:rotation [rotation 0]
                     #:scale [scale 1]
                     #:opacity [opacity 1])
  (unless (and (visual? content) (affine-visual? content))
    (raise-argument-error 'clip-visual "(and/c visual? affine-visual?)" content))
  (unless (path-geometry? path)
    (raise-argument-error 'clip-visual "path-geometry?" path))
  (unless (symbol? id)
    (raise-argument-error 'clip-visual "symbol?" id))
  (check-vec2 'clip-visual center)
  (unless (finite-real? rotation)
    (raise-argument-error 'clip-visual "finite real?" rotation))
  (unless (scale-factor? scale)
    (raise-argument-error
     'clip-visual "positive finite real or vec2 with positive components" scale))
  (unless (opacity? opacity)
    (raise-argument-error 'clip-visual "opacity?" opacity))
  (clipped-visual id
                  (make-affine-transform #:translation center
                                         #:rotation rotation
                                         #:scale scale)
                  opacity
                  content
                  path))

(define (check-vec2 who value)
  (unless (vec2? value)
    (raise-argument-error who "vec2?" value)))
