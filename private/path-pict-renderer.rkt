#lang racket/base

;;;
;;; Path Pict Renderer
;;;

;; Shared vector-path rendering used by ordinary path Visuals and specialised
;; formula interiors.  Keeping this conversion outside the renderer registry
;; lets another renderer reuse the exact same odd-even fill semantics without
;; a dependency cycle through shape-pict-renderers.

(require racket/class
         (only-in pict dc)
         (only-in racket/draw dc-path% make-brush make-color make-pen)
         "affine-transform.rkt"
         "camera.rkt"
         "color-style.rkt"
         "geometry.rkt"
         "paint-pict.rkt"
         "path-geometry.rkt"
         "pict-renderer.rkt"
         "visual-model.rkt")

(provide (struct-out path-pict-renderer)
         path-visual->pict
         closed-path-pen-cap-and-join
         open-path-pen-cap-and-join)

(struct path-pict-renderer ()
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (path-visual? visual))
   (define (pict-renderer-render _renderer visual camera)
     (path-visual->pict visual camera))])

(define maximum-default-pict-stroke-width 255)

(define (path-visual->pict visual camera)
  (define pixel-geometry
    (path-visual->pixel-geometry visual camera))
  (if (path-geometry-empty? pixel-geometry)
      (empty-path-pict)
      (begin
        (check-default-pict-stroke-width
         'path-visual->pict
         (path-visual-stroke-width visual))
        (let-values ([(half-width half-height)
                      (path-pict-half-extents pixel-geometry
                                              (path-visual-stroke-width visual))])
          (dc (lambda (drawing-context x y)
                (draw-path-geometry! drawing-context
                                     pixel-geometry
                                     (+ x half-width)
                                     (+ y half-height)
                                     (path-visual-fill visual)
                                     (path-visual-stroke visual)
                                     (path-visual-stroke-width visual)
                                     (path-paint-point-mapper visual camera
                                                              (+ x half-width)
                                                              (+ y half-height))))
              (* 2 half-width)
              (* 2 half-height))))))

(define (path-visual->pixel-geometry visual camera)
  (define transform
    (visual-transform visual))
  (define pixel-scale
    (camera-scale camera))
  (path-geometry-map-points
   (path-visual-path visual)
   (lambda (point)
     (define transformed
       (affine-transform-apply-vector transform point))
     (vec2 (* pixel-scale (vec2-x transformed))
           (* -1 pixel-scale (vec2-y transformed))))))

(define (path-pict-half-extents geometry stroke-width)
  (define-values (minimum-x minimum-y maximum-x maximum-y)
    (path-geometry-bounds geometry))
  (define stroke-padding
    (max 1 (/ stroke-width 2)))
  (values (+ (max (abs minimum-x) (abs maximum-x)) stroke-padding)
          (+ (max (abs minimum-y) (abs maximum-y)) stroke-padding)))

(define (empty-path-pict)
  (dc (lambda (_drawing-context _x _y) (void)) 1 1))

(define (check-default-pict-stroke-width who stroke-width)
  (when (> stroke-width maximum-default-pict-stroke-width)
    (raise-arguments-error
     who
     "the default Pict renderer supports cosmetic stroke widths from 0 through 255 pixels"
     "stroke-width" stroke-width
     "maximum-stroke-width" maximum-default-pict-stroke-width)))

(define (draw-path-geometry! drawing-context geometry x-offset y-offset
                             fill stroke stroke-width paint-point-mapper)
  (define old-pen (send drawing-context get-pen))
  (define old-brush (send drawing-context get-brush))
  (dynamic-wind
    void
    (lambda ()
      (draw-closed-subpaths! drawing-context geometry x-offset y-offset
                             fill stroke stroke-width paint-point-mapper)
      (draw-open-subpaths! drawing-context geometry x-offset y-offset
                           stroke stroke-width))
    (lambda ()
      (send drawing-context set-pen old-pen)
      (send drawing-context set-brush old-brush))))

(define (draw-closed-subpaths! drawing-context geometry x-offset y-offset
                               fill stroke stroke-width paint-point-mapper)
  (define closed-subpaths
    (for/list ([subpath (in-list (path-geometry-subpaths geometry))]
               #:when (path-subpath-closed? subpath))
      subpath))
  (unless (null? closed-subpaths)
    (send drawing-context set-pen (make-closed-path-pen stroke stroke-width))
    (send drawing-context set-brush (make-path-brush fill paint-point-mapper))
    (send drawing-context draw-path (subpaths->dc-path closed-subpaths)
          x-offset y-offset 'odd-even)))

(define (draw-open-subpaths! drawing-context geometry x-offset y-offset
                             stroke stroke-width)
  (send drawing-context set-pen (make-open-path-pen stroke stroke-width))
  (send drawing-context set-brush (make-path-brush #f))
  (for ([subpath (in-list (path-geometry-subpaths geometry))]
        #:unless (path-subpath-closed? subpath))
    (send drawing-context draw-path (subpaths->dc-path (list subpath))
          x-offset y-offset 'odd-even)))

(define (subpaths->dc-path subpaths)
  (define drawing-path (new dc-path%))
  (for ([subpath (in-list subpaths)])
    (add-subpath-to-dc-path! drawing-path subpath))
  drawing-path)

(define (add-subpath-to-dc-path! drawing-path subpath)
  (define start (path-subpath-start subpath))
  (send drawing-path move-to (vec2-x start) (vec2-y start))
  (for ([segment (in-list (path-subpath-segments subpath))])
    (cond
      [(line-path-segment? segment)
       (define end (line-path-segment-end segment))
       (send drawing-path line-to (vec2-x end) (vec2-y end))]
      [(cubic-bezier-path-segment? segment)
       (define control1 (cubic-bezier-path-segment-control1 segment))
       (define control2 (cubic-bezier-path-segment-control2 segment))
       (define end (cubic-bezier-path-segment-end segment))
       (send drawing-path curve-to
             (vec2-x control1) (vec2-y control1)
             (vec2-x control2) (vec2-y control2)
             (vec2-x end) (vec2-y end))]
      [else
       (raise-argument-error 'add-subpath-to-dc-path!
                             "supported path segment" segment)]))
  (when (path-subpath-closed? subpath)
    (send drawing-path close)))

(define (make-closed-path-pen stroke stroke-width)
  (make-pen #:color (if stroke (draw-color-spec stroke) "black")
            #:width stroke-width
            #:style (if stroke 'solid 'transparent)
            #:cap 'butt
            #:join 'miter))

(define (make-open-path-pen stroke stroke-width)
  (make-pen #:color (if stroke (draw-color-spec stroke) "black")
            #:width stroke-width
            #:style (if stroke 'solid 'transparent)
            #:cap 'round
            #:join 'miter))

(define (make-path-brush fill
                         [paint-point-mapper (lambda (point) point)])
  (make-paint-brush fill paint-point-mapper))

(define (path-paint-point-mapper visual camera x-offset y-offset)
  (define transform (visual-transform visual))
  (define pixel-scale (camera-scale camera))
  (lambda (point)
    (define transformed (affine-transform-apply-vector transform point))
    (vec2 (+ x-offset (* pixel-scale (vec2-x transformed)))
          (+ y-offset (* -1 pixel-scale (vec2-y transformed))))))

(define (draw-color-spec color)
  (define resolved
    (cond [(rgba-color? color) color]
          [(and (string? color) (color-spec? color))
           (color-spec->rgba-color color 'draw-color-spec)]
          [else #f]))
  (if resolved
      (make-color (color-channel->byte (rgba-color-red resolved))
                  (color-channel->byte (rgba-color-green resolved))
                  (color-channel->byte (rgba-color-blue resolved))
                  (rgba-color-alpha resolved))
      color))

(define (color-channel->byte channel)
  (inexact->exact (round channel)))

(define (closed-path-pen-cap-and-join)
  (define pen (make-closed-path-pen "black" 2))
  (values (send pen get-cap) (send pen get-join)))

(define (open-path-pen-cap-and-join)
  (define pen (make-open-path-pen "black" 2))
  (values (send pen get-cap) (send pen get-join)))
