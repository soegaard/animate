#lang racket/base

;;;
;;; Pict/racket-draw paint adapter
;;;

(require racket/class
         (only-in racket/draw
                  bitmap%
                  bitmap-dc%
                  linear-gradient%
                  make-brush
                  make-color
                  make-pen
                  radial-gradient%)
         "color-style.rkt"
         "geometry.rkt"
         "paint.rkt")

(provide paint->draw-color
         make-paint-brush)

(define (paint->draw-color color)
  (define rgba (color-spec->rgba-color color 'paint->draw-color))
  (make-color (color-channel->byte (rgba-color-red rgba))
              (color-channel->byte (rgba-color-green rgba))
              (color-channel->byte (rgba-color-blue rgba))
              (rgba-color-alpha rgba)))

;; `map-point` converts a local world point in a semantic paint into the
;; current Pict drawing coordinate system. Gradients therefore follow normal
;; Visual affine transforms instead of being fixed to the video frame. Native
;; stipple brushes do not expose that transform, so checker patterns currently
;; retain a device-aligned tile (documented as a renderer limitation).
(define (make-paint-brush paint map-point)
  (cond [(not paint)
         (make-brush #:color "black" #:style 'transparent)]
        [(color-spec? paint)
         (make-brush #:color (paint->draw-color paint) #:style 'solid)]
        [(linear-gradient-paint? paint)
         (define start (map-point (linear-gradient-paint-start paint)))
         (define end (map-point (linear-gradient-paint-end paint)))
         (make-brush
          #:color "black"
          #:style 'solid
          #:gradient
          (new linear-gradient%
               [x0 (vec2-x start)] [y0 (vec2-y start)]
               [x1 (vec2-x end)] [y1 (vec2-y end)]
               [stops (paint-stops->draw-stops (linear-gradient-paint-stops paint))]))]
        [(radial-gradient-paint? paint)
         (define focal (map-point (radial-gradient-paint-focal-center paint)))
         (define center (map-point (radial-gradient-paint-center paint)))
         ;; A native radial gradient has circular radii. The local x-direction
         ;; gives the radius scale; an enclosing nonuniform Visual transform
         ;; then naturally turns that circle into an ellipse with the shape.
         (define radius-scale
           (distance (map-point (vec2+ (radial-gradient-paint-center paint)
                                        (vec2 (radial-gradient-paint-radius paint) 0)))
                     center))
         (define focal-radius-scale
           (if (zero? (radial-gradient-paint-focal-radius paint))
               0
               (distance
                (map-point
                 (vec2+ (radial-gradient-paint-focal-center paint)
                        (vec2 (radial-gradient-paint-focal-radius paint) 0)))
                focal)))
         (make-brush
          #:color "black"
          #:style 'solid
          #:gradient
          (new radial-gradient%
               [x0 (vec2-x focal)] [y0 (vec2-y focal)] [r0 focal-radius-scale]
               [x1 (vec2-x center)] [y1 (vec2-y center)] [r1 radius-scale]
               [stops (paint-stops->draw-stops (radial-gradient-paint-stops paint))]))]
        [(checker-pattern-paint? paint)
         (make-brush #:color "black" #:style 'solid
                     #:stipple (checker-bitmap paint map-point))]
        [else
         (raise-argument-error 'make-paint-brush "paint? or #f" paint)]))

(define (paint-stops->draw-stops stops)
  (for/list ([stop (in-list stops)])
    (list (paint-stop-offset stop) (paint->draw-color (paint-stop-color stop)))))

(define (checker-bitmap paint map-point)
  (define mapped-origin (map-point origin))
  (define cell-end
    (map-point (vec2 (checker-pattern-paint-cell-size paint) 0)))
  (define cell-pixels
    (max 1 (inexact->exact (round (distance mapped-origin cell-end)))))
  (define size (* 2 cell-pixels))
  (define bitmap (make-object bitmap% size size))
  (define drawing-context (new bitmap-dc% [bitmap bitmap]))
  (dynamic-wind
    void
    (lambda ()
      (send drawing-context set-pen
            (make-pen #:color "black" #:style 'transparent))
      (for* ([row (in-range 2)] [column (in-range 2)])
        (send drawing-context set-brush
              (make-brush
               #:color (paint->draw-color
                        (if (even? (+ row column))
                            (checker-pattern-paint-first paint)
                            (checker-pattern-paint-second paint)))
               #:style 'solid))
        (send drawing-context draw-rectangle (* column cell-pixels)
              (* row cell-pixels) cell-pixels cell-pixels)))
    (lambda () (send drawing-context set-bitmap #f)))
  bitmap)

(define (distance first second)
  (sqrt (+ (sqr (- (vec2-x first) (vec2-x second)))
           (sqr (- (vec2-y first) (vec2-y second))))))

(define (sqr value) (* value value))

(define (color-channel->byte channel)
  (inexact->exact (round channel)))
