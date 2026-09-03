#lang racket/base

;;;
;;; Pict Affine Transformation
;;;

;; Applies a world-space affine2 map's linear component to a Pict around its
;; semantic centre. Translation is intentionally handled by the scene adapter,
;; which places the transformed Visual at its transformed world reference point.


;;;
;;; Imports and Exports

(require racket/class
         (only-in pict dc draw-pict pict? pict-height pict-width)
         "affine-transform.rkt"
         "geometry.rkt")

(provide affine2-pict-transform)


;;;
;;; Transformation

;; affine2-pict-transform : pict? affine2? -> pict?
;; Converts the map from y-up world coordinates to y-down Pict pixels and
;; applies it around the source Pict's centre.  A Pict's reference origin is its
;; centre throughout the scene adapter, so the result deliberately uses
;; symmetric extents rather than a tight translated bounding box.
(define (affine2-pict-transform source map)
  (unless (pict? source)
    (raise-argument-error 'affine2-pict-transform "pict?" source))
  (unless (affine2? map)
    (raise-argument-error 'affine2-pict-transform "affine2?" map))
  (define linear
    (affine2-linear map))
  ;; World: (x', y') = (a*x + b*y, c*x + d*y).
  ;; Pixels use (x, -y), yielding (x', y') =
  ;; (a*x - b*y, -c*x + d*y).
  (define pixel-map
    (vector (linear2-a linear)
            (- (linear2-c linear))
            (- (linear2-b linear))
            (linear2-d linear)
            0
            0))
  (define source-half-width (/ (pict-width source) 2))
  (define source-half-height (/ (pict-height source) 2))
  (define-values (half-width half-height)
    (transformed-half-extents pixel-map source-half-width source-half-height))
  (define width (* 2 half-width))
  (define height (* 2 half-height))
  (dc
   (lambda (drawing-context x y)
     (define old-transformation
       (send drawing-context get-transformation))
     (dynamic-wind
       void
       (lambda ()
         (send drawing-context translate (+ x half-width) (+ y half-height))
         (send drawing-context transform pixel-map)
         (draw-pict source
                    drawing-context
                    (- source-half-width)
                    (- source-half-height)))
       (lambda ()
         (send drawing-context set-transformation old-transformation))))
   width
   height))

;; transformed-half-extents : vector? nonnegative-real? nonnegative-real?
;;                            -> (values positive-real? positive-real?)
(define (transformed-half-extents matrix half-width half-height)
  (define points
    (for*/list ([x (in-list (list (- half-width) half-width))]
                [y (in-list (list (- half-height) half-height))])
      (vec2 (+ (* (vector-ref matrix 0) x)
               (* (vector-ref matrix 2) y))
            (+ (* (vector-ref matrix 1) x)
               (* (vector-ref matrix 3) y)))))
  ;; Keep the Pict valid for a completely collapsed intermediate map.
  (values (max 1/2 (apply max (map (lambda (point) (abs (vec2-x point))) points)))
          (max 1/2 (apply max (map (lambda (point) (abs (vec2-y point))) points)))))
