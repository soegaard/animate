#lang racket/base

;;;
;;; Renderer-neutral Mathematical Stroke Style
;;;

;; A stroke is a *style*, not geometry.  It deliberately contains no sampled
;; mesh, camera, renderer, or mutable cache.  A compiler later pairs it with a
;; centreline and the current transform; a renderer then resolves the requested
;; screen or world width for its target.

(require "../color-style.rkt"
         "../geometry.rkt")

(provide stroke3d
         stroke3d?
         stroke3d-color
         stroke3d-width
         stroke3d-width-mode
         stroke3d-cap
         stroke3d-join
         stroke3d-miter-limit
         stroke3d-dash
         stroke3d-dash-offset
         stroke3d-dash-space
         stroke3d-opacity
         stroke3d-depth-mode
         stroke3d-depth-bias
         stroke3d-with-color
         stroke3d-with-opacity)

(struct stroke3d-value
  (color width width-mode cap join miter-limit dash dash-offset dash-space
         opacity depth-mode depth-bias)
  #:transparent)

(define stroke3d? stroke3d-value?)
(define stroke3d-color stroke3d-value-color)
(define stroke3d-width stroke3d-value-width)
(define stroke3d-width-mode stroke3d-value-width-mode)
(define stroke3d-cap stroke3d-value-cap)
(define stroke3d-join stroke3d-value-join)
(define stroke3d-miter-limit stroke3d-value-miter-limit)
(define stroke3d-dash stroke3d-value-dash)
(define stroke3d-dash-offset stroke3d-value-dash-offset)
(define stroke3d-dash-space stroke3d-value-dash-space)
(define stroke3d-opacity stroke3d-value-opacity)
(define stroke3d-depth-mode stroke3d-value-depth-mode)
(define stroke3d-depth-bias stroke3d-value-depth-bias)

; stroke3d : [#:color color-spec?] [#:width positive-finite-real?]
;            [#:width-mode (or/c 'screen 'world)]
;            [#:cap (or/c 'butt 'square 'round)]
;            [#:join (or/c 'miter 'bevel 'round)]
;            [#:miter-limit positive-finite-real?]
;            [#:dash (or/c #f even-positive-finite-pattern?)]
;            [#:dash-offset finite-real?]
;            [#:dash-space (or/c 'screen 'world)]
;            [#:opacity unit-real?]
;            [#:depth-mode (or/c 'test 'always 'hidden)]
;            [#:depth-bias nonnegative-finite-real?]
;            -> stroke3d?
;;
;; In screen mode, width and the default dash space are pixels.  In world
;; mode, width is the full physical diameter.  The explicit dash-space option
;; is useful for a physical tube-like line with deliberately screen-constant
;; dashes, but the default always follows width mode.
(define (stroke3d #:color [color "steelblue"]
                  #:width [width 2]
                  #:width-mode [width-mode 'screen]
                  #:cap [cap 'round]
                  #:join [join 'round]
                  #:miter-limit [miter-limit 4]
                  #:dash [dash #f]
                  #:dash-offset [dash-offset 0]
                  #:dash-space [dash-space width-mode]
                  #:opacity [opacity 1]
                  #:depth-mode [depth-mode 'test]
                  #:depth-bias [depth-bias 1e-5])
  (unless (color-spec? color)
    (raise-argument-error 'stroke3d "color-spec?" color))
  (check-positive 'stroke3d "width" width)
  (unless (memq width-mode '(screen world))
    (raise-argument-error 'stroke3d "one of 'screen or 'world" width-mode))
  (unless (memq cap '(butt square round))
    (raise-argument-error 'stroke3d "one of 'butt, 'square, or 'round" cap))
  (unless (memq join '(miter bevel round))
    (raise-argument-error 'stroke3d "one of 'miter, 'bevel, or 'round" join))
  (check-positive 'stroke3d "miter-limit" miter-limit)
  (define normalized-dash (normalize-dash dash))
  (unless (finite-real? dash-offset)
    (raise-argument-error 'stroke3d "finite real dash offset" dash-offset))
  (unless (memq dash-space '(screen world))
    (raise-argument-error 'stroke3d "one of 'screen or 'world" dash-space))
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error 'stroke3d "finite real in [0, 1] as opacity" opacity))
  (unless (memq depth-mode '(test always hidden))
    (raise-argument-error 'stroke3d "one of 'test, 'always, or 'hidden" depth-mode))
  (unless (and (finite-real? depth-bias) (>= depth-bias 0))
    (raise-argument-error 'stroke3d "nonnegative finite depth bias" depth-bias))
  (stroke3d-value color width width-mode cap join miter-limit normalized-dash
                  dash-offset dash-space opacity depth-mode depth-bias))

(define (stroke3d-with-color style color)
  (unless (stroke3d? style)
    (raise-argument-error 'stroke3d-with-color "stroke3d?" style))
  (unless (color-spec? color)
    (raise-argument-error 'stroke3d-with-color "color-spec?" color))
  (struct-copy stroke3d-value style [color color]))

(define (stroke3d-with-opacity style opacity)
  (unless (stroke3d? style)
    (raise-argument-error 'stroke3d-with-opacity "stroke3d?" style))
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error 'stroke3d-with-opacity "finite real in [0, 1]" opacity))
  (struct-copy stroke3d-value style [opacity opacity]))

(define (normalize-dash dash)
  (cond [(not dash) #f]
        [(or (list? dash) (vector? dash))
         (define lengths (if (vector? dash) (vector->list dash) dash))
         (unless (and (positive? (length lengths)) (even? (length lengths))
                      (andmap (lambda (value)
                                (and (finite-real? value) (positive? value)))
                              lengths))
           (raise-argument-error
            'stroke3d
            "an even-length list or vector of positive finite dash lengths"
            dash))
         (vector->immutable-vector (list->vector lengths))]
        [else
         (raise-argument-error
          'stroke3d
          "#f or an even-length list or vector of positive finite dash lengths"
          dash)]))

(define (check-positive who name value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "a positive finite real"
                           "argument" name "value" value)))
