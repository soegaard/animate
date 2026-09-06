#lang racket/base

;;;
;;; Spatial Curve Animation Requests
;;;

;; Defines pure request and compiled-value vocabulary for Stage F curve
;; animation.  Scene compilation resolves paths and captures source geometry;
;; this module deliberately knows neither Scene state nor rendering.


;;;
;;; Imports and Exports
;;;

(require "../geometry.rkt"
         "spatial-path.rkt")

(provide move-along-curve3d
         move-along-curve3d-request?
         orient-along-curve3d
         orient-along-curve3d-request?
         spatial-curve-reveal
         spatial-curve-reveal-request?
         spatial-curve-unreveal
         spatial-curve-unreveal-request?
         spatial-curve-flash
         spatial-curve-flash-request?
         spatial-curve-animation-request?
         spatial-curve-compiled-animation?
         spatial-curve-reveal-request-target-path
         spatial-curve-reveal-request-reverse?
         spatial-curve-flash-request-target-path
         spatial-curve-flash-request-time-width
         spatial-curve-flash-request-color
         (struct-out move-along-curve3d-request)
         (struct-out orient-along-curve3d-request)
         (struct-out spatial-curve-reveal-animation)
         (struct-out spatial-curve-flash-animation)
         (struct-out spatial-curve-motion-animation)
         (struct-out spatial-curve-orientation-animation))


;;;
;;; Requests
;;;

(struct move-along-curve3d-request (target-path curve-path start end) #:transparent)
;; target-path and curve-path are rooted stable spatial paths.  `start` and
;; `end` are arc-length fractions sampled directly at each timeline progress.

(struct orient-along-curve3d-request (target-path curve-path start end) #:transparent)
;; Orients local +x along the sampled curve tangent in the target parent's
;; local coordinate frame.

(struct spatial-curve-reveal-request-value (target-path reverse?) #:transparent)
;; Reveals a retained curve from zero to full length, or reverses that order.

(struct spatial-curve-flash-request-value (target-path time-width color) #:transparent)
;; Replaces the target temporarily with one moving arc-length sliver.


;;;
;;; Public Construction
;;;

; move-along-curve3d : spatial-path? spatial-path?
;                      [#:start unit-real?] [#:end unit-real?]
;                      -> move-along-curve3d-request?
;;   Moves a spatial target along a sampled curve without storing frame history.
(define (move-along-curve3d target-path curve-path
                            #:start [start 0] #:end [end 1])
  (check-path 'move-along-curve3d target-path)
  (check-path 'move-along-curve3d curve-path)
  (check-interval 'move-along-curve3d start end)
  (move-along-curve3d-request target-path curve-path start end))

; orient-along-curve3d : spatial-path? spatial-path?
;                        [#:start unit-real?] [#:end unit-real?]
;                        -> orient-along-curve3d-request?
;;   Rotates a spatial target's local +x to the sampled curve tangent.
(define (orient-along-curve3d target-path curve-path
                              #:start [start 0] #:end [end 1])
  (check-path 'orient-along-curve3d target-path)
  (check-path 'orient-along-curve3d curve-path)
  (check-interval 'orient-along-curve3d start end)
  (orient-along-curve3d-request target-path curve-path start end))

; spatial-curve-reveal : spatial-path? -> spatial-curve-reveal-request?
;;   Creates the internal request used by `create` for an existing curve path.
(define (spatial-curve-reveal target-path)
  (check-path 'spatial-curve-reveal target-path)
  (spatial-curve-reveal-request-value target-path #f))

; spatial-curve-unreveal : spatial-path? -> spatial-curve-unreveal-request?
;;   Creates the internal request used by `uncreate` for an existing curve path.
(define (spatial-curve-unreveal target-path)
  (check-path 'spatial-curve-unreveal target-path)
  (spatial-curve-reveal-request-value target-path #t))

; spatial-curve-flash : spatial-path? [#:time-width unit-real?] [#:color color-spec?]
;                       -> spatial-curve-flash-request?
;;   Creates the spatial counterpart of `show-passing-flash`.
(define (spatial-curve-flash target-path #:time-width [time-width 1/5]
                             #:color [color "gold"])
  (check-path 'spatial-curve-flash target-path)
  (unless (and (finite-real? time-width) (positive? time-width) (<= time-width 1))
    (raise-argument-error 'spatial-curve-flash "finite real in (0, 1]" time-width))
  (spatial-curve-flash-request-value target-path time-width color))


;;;
;;; Compiled Values
;;;

(struct spatial-curve-reveal-animation (target-path curve reverse?) #:transparent)
(struct spatial-curve-flash-animation (target-path curve overlay-id time-width color) #:transparent)
(struct spatial-curve-motion-animation
  (target-path curve-path curve curve-world-transform parent-world-inverse start end)
  #:transparent)
(struct spatial-curve-orientation-animation
  (target-path curve-path curve curve-world-transform parent-world-inverse start end)
  #:transparent)


;;;
;;; Predicates and Validation
;;;

(define (spatial-curve-reveal-request? value)
  (and (spatial-curve-reveal-request-value? value)
       (not (spatial-curve-reveal-request-value-reverse? value))))

(define (spatial-curve-unreveal-request? value)
  (and (spatial-curve-reveal-request-value? value)
       (spatial-curve-reveal-request-value-reverse? value)))

(define (spatial-curve-flash-request? value)
  (spatial-curve-flash-request-value? value))

(define (spatial-curve-animation-request? value)
  (or (move-along-curve3d-request? value)
      (orient-along-curve3d-request? value)
      (spatial-curve-reveal-request-value? value)
      (spatial-curve-flash-request? value)))

(define spatial-curve-reveal-request-target-path
  spatial-curve-reveal-request-value-target-path)
(define spatial-curve-reveal-request-reverse?
  spatial-curve-reveal-request-value-reverse?)
(define spatial-curve-flash-request-target-path
  spatial-curve-flash-request-value-target-path)
(define spatial-curve-flash-request-time-width
  spatial-curve-flash-request-value-time-width)
(define spatial-curve-flash-request-color
  spatial-curve-flash-request-value-color)

(define (spatial-curve-compiled-animation? value)
  (or (spatial-curve-reveal-animation? value)
      (spatial-curve-flash-animation? value)
      (spatial-curve-motion-animation? value)
      (spatial-curve-orientation-animation? value)))

(define (check-path who value)
  (unless (and (spatial-path? value) (pair? (cdr value)))
    (raise-argument-error who "view-rooted nonempty spatial path" value)))

(define (check-interval who start end)
  (for ([value (in-list (list start end))])
    (unless (and (finite-real? value) (<= 0 value 1))
      (raise-argument-error who "finite real in [0, 1]" value)))
  (when (> start end)
    (raise-arguments-error who "start no later than end" "start" start "end" end)))
