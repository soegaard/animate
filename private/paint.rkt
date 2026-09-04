#lang racket/base

;;;
;;; Semantic fills and paints
;;;

;; Paint values are renderer-independent scene data. Existing color strings and
;; rgba-color values remain valid solid paints for source compatibility; the
;; new values add local-coordinate gradients and a deterministic checker tile.
;; The default Pict renderer currently uses a device-aligned stipple for that
;; tile; its semantic cell size still participates in value equality and
;; interpolation, but it does not yet receive the full affine map.

(require "color-style.rkt"
         "geometry.rkt")

(provide (struct-out paint-stop)
         (struct-out linear-gradient-paint)
         (struct-out radial-gradient-paint)
         (struct-out checker-pattern-paint)
         linear-gradient
         radial-gradient
         checker-pattern
         paint?
         paint-lerp)

(struct paint-stop (offset color)
  #:transparent
  #:guard
  (lambda (offset color who)
    (unless (and (finite-real? offset) (<= 0 offset 1))
      (raise-arguments-error who "offset must be a finite real in [0, 1]"
                             "offset" offset))
    (unless (color-spec? color)
      (raise-arguments-error who "color must be a supported color specification"
                             "color" color))
    (values offset color)))

(struct linear-gradient-paint (start end stops)
  #:transparent
  #:guard
  (lambda (start end stops who)
    (check-gradient-points who start end)
    (check-gradient-stops who stops)
    (values start end stops)))

(struct radial-gradient-paint (focal-center focal-radius center radius stops)
  #:transparent
  #:guard
  (lambda (focal-center focal-radius center radius stops who)
    (check-gradient-points who focal-center center)
    (for ([value (in-list (list focal-radius radius))]
          [name (in-list '(focal-radius radius))])
      (unless (and (finite-real? value) (>= value 0))
        (raise-arguments-error who "radius must be a nonnegative finite real"
                               name value)))
    (check-gradient-stops who stops)
    (values focal-center focal-radius center radius stops)))

(struct checker-pattern-paint (first second cell-size)
  #:transparent
  #:guard
  (lambda (first second cell-size who)
    (unless (color-spec? first)
      (raise-arguments-error who "first color must be a supported color specification"
                             "first" first))
    (unless (color-spec? second)
      (raise-arguments-error who "second color must be a supported color specification"
                             "second" second))
    (unless (and (finite-real? cell-size) (positive? cell-size))
      (raise-arguments-error who "cell-size must be a positive finite real"
                             "cell-size" cell-size))
    (values first second cell-size)))

(define (linear-gradient start end stops)
  (linear-gradient-paint start end stops))

(define (radial-gradient center radius stops
                         #:focal-center [focal-center center]
                         #:focal-radius [focal-radius 0])
  (radial-gradient-paint focal-center focal-radius center radius stops))

(define (checker-pattern first second #:cell-size [cell-size 1])
  (checker-pattern-paint first second cell-size))

;; paint? deliberately includes the pre-existing color vocabulary. #f remains
;; the established "no fill/no stroke" sentinel and is not itself a paint.
(define (paint? value)
  (or (color-spec? value)
      (linear-gradient-paint? value)
      (radial-gradient-paint? value)
      (checker-pattern-paint? value)))

;; Interpolate compatible semantic paints. Cross-kind transitions deliberately
;; fall back to the caller's existing fade-transform policy rather than invent
;; a transient gradient with surprising semantics.
(define (paint-lerp from to progress)
  (unless (paint? from)
    (raise-argument-error 'paint-lerp "paint?" from))
  (unless (paint? to)
    (raise-argument-error 'paint-lerp "paint?" to))
  (unless (and (finite-real? progress) (<= 0 progress 1))
    (raise-argument-error 'paint-lerp "finite real in [0, 1]" progress))
  (cond [(zero? progress) from]
        [(= progress 1) to]
        [(and (color-spec? from) (color-spec? to))
         (rgba-color-lerp (color-spec->rgba-color from 'paint-lerp)
                          (color-spec->rgba-color to 'paint-lerp)
                          progress)]
        [(and (linear-gradient-paint? from) (linear-gradient-paint? to))
         (linear-gradient-paint
          (vec2-lerp (linear-gradient-paint-start from)
                     (linear-gradient-paint-start to) progress)
          (vec2-lerp (linear-gradient-paint-end from)
                     (linear-gradient-paint-end to) progress)
          (lerp-stops (linear-gradient-paint-stops from)
                      (linear-gradient-paint-stops to) progress))]
        [(and (radial-gradient-paint? from) (radial-gradient-paint? to))
         (radial-gradient-paint
          (vec2-lerp (radial-gradient-paint-focal-center from)
                     (radial-gradient-paint-focal-center to) progress)
          (real-lerp (radial-gradient-paint-focal-radius from)
                     (radial-gradient-paint-focal-radius to) progress)
          (vec2-lerp (radial-gradient-paint-center from)
                     (radial-gradient-paint-center to) progress)
          (real-lerp (radial-gradient-paint-radius from)
                     (radial-gradient-paint-radius to) progress)
          (lerp-stops (radial-gradient-paint-stops from)
                      (radial-gradient-paint-stops to) progress))]
        [(and (checker-pattern-paint? from) (checker-pattern-paint? to))
         (checker-pattern-paint
          (rgba-color-lerp (color-spec->rgba-color (checker-pattern-paint-first from)
                                                   'paint-lerp)
                           (color-spec->rgba-color (checker-pattern-paint-first to)
                                                   'paint-lerp)
                           progress)
          (rgba-color-lerp (color-spec->rgba-color (checker-pattern-paint-second from)
                                                   'paint-lerp)
                           (color-spec->rgba-color (checker-pattern-paint-second to)
                                                   'paint-lerp)
                           progress)
          (real-lerp (checker-pattern-paint-cell-size from)
                     (checker-pattern-paint-cell-size to) progress))]
        [else
         (raise-arguments-error
          'paint-lerp
          "paint interpolation requires matching paint kinds and gradient stop counts"
          "from" from "to" to)]))

(define (lerp-stops first second progress)
  (unless (= (length first) (length second))
    (raise-arguments-error
     'paint-lerp
     "gradient interpolation requires equal numbers of stops"
     "from-stop-count" (length first)
     "to-stop-count" (length second)))
  (for/list ([from (in-list first)] [to (in-list second)])
    (paint-stop
     (real-lerp (paint-stop-offset from) (paint-stop-offset to) progress)
     (rgba-color-lerp (color-spec->rgba-color (paint-stop-color from) 'paint-lerp)
                      (color-spec->rgba-color (paint-stop-color to) 'paint-lerp)
                      progress))))

(define (check-gradient-points who first second)
  (for ([point (in-list (list first second))] [name (in-list '(start end))])
    (unless (vec2? point)
      (raise-arguments-error who "gradient endpoint must be a vec2"
                             name point))))

(define (check-gradient-stops who stops)
  (unless (and (list? stops) (>= (length stops) 2)
               (andmap paint-stop? stops)
               (for/and ([previous (in-list stops)] [next (in-list (cdr stops))])
                 (<= (paint-stop-offset previous) (paint-stop-offset next))))
    (raise-arguments-error
     who
     "stops must be an ordered list of at least two paint-stop values"
     "stops" stops)))
