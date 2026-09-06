#lang racket/base

;;;
;;; View3D Pict Adapter
;;;

;; Converts prepared wireframe segments to a clipped ordinary Pict.  This is
;; the first effectful spatial adapter; the spatial tree, camera, and segment
;; preparation modules remain Pict-free and work in headless model tests.


;;;
;;; Imports and Exports
;;;

(require racket/class
         (only-in pict bitmap dc rotate)
         (only-in racket/draw dc-path% make-brush make-color make-pen region%)
         "../camera.rkt"
         "../color-style.rkt"
         "../geometry.rkt"
         "../pict-renderer.rkt"
         "../visual-model.rkt"
         "renderer3d.rkt"
         "frame-artifact-cache3d.rkt"
         "software-renderer3d.rkt"
         "view3d-visual.rkt"
         "wireframe-renderer.rkt")

(provide (struct-out view3d-pict-renderer)
         default-view3d-pict-renderer
         view3d->pict)


;;;
;;; Renderer Protocol Value
;;;

(struct view3d-pict-renderer ()
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (view3d? visual))
   (define (pict-renderer-render _renderer visual camera)
     (view3d->pict visual camera))])

;; view3d-pict-renderer selects either the legacy wireframe adapter or the
;; deterministic opaque software target, then returns an ordinary Pict.

; default-view3d-pict-renderer : pict-renderer?
;;   Gives the built-in renderer selected before ordinary 2D primitive renderers.
(define default-view3d-pict-renderer
  (view3d-pict-renderer))


;;;
;;; Pict Conversion
;;;

; view3d->pict : view3d? camera? -> pict?
;;   Renders the immutable spatial tree into its outer 2D viewport rectangle.
(define (view3d->pict view outer-camera)
  (unless (view3d? view)
    (raise-argument-error 'view3d->pict "view3d?" view))
  (unless (camera? outer-camera)
    (raise-argument-error 'view3d->pict "camera?" outer-camera))
  (define scale (visual-scale view))
  (define width
    (positive-pixel-extent
     (* (camera-length->pixels outer-camera (view3d-width view))
        (vec2-x scale))))
  (define height
    (positive-pixel-extent
     (* (camera-length->pixels outer-camera (view3d-height view))
        (vec2-y scale))))
  (define aspect (/ width height))
  (define rendered
    (case (view3d-render-mode view)
      [(wireframe)
       (wireframe-pict
        width height
        (view3d-background view)
        (spatial-tree->wireframe-segments view (view3d-camera view) aspect))]
      [(opaque)
       (define renderer (current-view3d-renderer3d))
        (define artifact
         (render-view3d-frame-artifact
          view width height renderer
          #:attachments '(color depth)
          #:cancellation-token (current-software-render-cancellation-token)))
       (bitmap
        (renderer3d-render-result->bitmap
         (renderer3d-render-result
          width height (renderer3d-frame-artifact-straight-argb artifact)
          (renderer3d-frame-artifact-diagnostics artifact)))) ]
      [else (error 'view3d->pict "unsupported render mode: ~e"
                   (view3d-render-mode view))]))
  (if (zero? (visual-rotation view))
      rendered
      (rotate rendered (visual-rotation view))))

; wireframe-pict : exact-positive-integer? exact-positive-integer? color-spec?
;                  (listof wireframe-segment?) -> pict?
;;   Draws a clipped opaque viewport background and significant-order line list.
(define (wireframe-pict width height background segments)
  (dc
   (lambda (drawing-context x-offset y-offset)
     (define old-pen (send drawing-context get-pen))
     (define old-brush (send drawing-context get-brush))
     (define old-region (send drawing-context get-clipping-region))
     (dynamic-wind
       void
       (lambda ()
         (send drawing-context set-pen
               (make-pen #:color (draw-color-spec background)
                         #:style 'transparent))
         (send drawing-context set-brush
               (make-brush #:color (draw-color-spec background) #:style 'solid))
         (send drawing-context draw-rectangle x-offset y-offset width height)
         (define viewport-path (new dc-path%))
         (send viewport-path move-to 0 0)
         (send viewport-path line-to width 0)
         (send viewport-path line-to width height)
         (send viewport-path line-to 0 height)
         (send viewport-path close)
         (define viewport-region (new region% [dc drawing-context]))
         (send viewport-region set-path viewport-path x-offset y-offset 'odd-even)
         (when old-region (send viewport-region intersect old-region))
         (send drawing-context set-clipping-region viewport-region)
         (for ([segment (in-list segments)])
           (draw-wireframe-segment! drawing-context x-offset y-offset
                                    width height segment)))
       (lambda ()
         (send drawing-context set-clipping-region old-region)
         (send drawing-context set-pen old-pen)
         (send drawing-context set-brush old-brush))))
   width height))

(define (draw-wireframe-segment! drawing-context x-offset y-offset width height segment)
  (define color
    (rgba-with-opacity (wireframe-segment-color segment)
                       (wireframe-segment-opacity segment)))
  (send drawing-context set-pen
        (make-pen #:color color
                  #:width (wireframe-segment-width segment)
                  #:style 'solid
                  #:cap 'round
                  #:join 'round))
  (define start (wireframe-segment-start segment))
  (define end (wireframe-segment-end segment))
  (send drawing-context draw-line
        (+ x-offset (normalized-x->pixel (vec2-x start) width))
        (+ y-offset (normalized-y->pixel (vec2-y start) height))
        (+ x-offset (normalized-x->pixel (vec2-x end) width))
        (+ y-offset (normalized-y->pixel (vec2-y end) height))))

(define (normalized-x->pixel x width)
  (* width (/ (+ x 1) 2)))

(define (normalized-y->pixel y height)
  (* height (/ (- 1 y) 2)))

(define (positive-pixel-extent value)
  (max 1 (inexact->exact (round value))))

(define (draw-color-spec color)
  (define resolved (color-spec->rgba-color color 'view3d-pict-renderer))
  (make-color (color-byte (rgba-color-red resolved))
              (color-byte (rgba-color-green resolved))
              (color-byte (rgba-color-blue resolved))
              (rgba-color-alpha resolved)))

(define (rgba-with-opacity color opacity)
  (define resolved (color-spec->rgba-color color 'view3d-pict-renderer))
  (make-color (color-byte (rgba-color-red resolved))
              (color-byte (rgba-color-green resolved))
              (color-byte (rgba-color-blue resolved))
              (* opacity (rgba-color-alpha resolved))))

(define (color-byte channel)
  (inexact->exact (round channel)))
