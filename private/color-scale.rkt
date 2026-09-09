#lang racket/base

;;;
;;; Immutable Color Scales
;;;

;; Maps an already normalized scalar coordinate to a semantic color
;; expression.  It deliberately has no knowledge of plot data, frames, or a
;; current theme: choosing a data domain remains an authoring decision.

(require "color-style.rkt"
         (only-in "color-token.rkt"
                  aqua-d gold-d gray-b red-d theme-muted)
         "geometry.rkt"
         "paint.rkt")

(provide color-scale
         color-scale?
         color-scale-stops
         color-scale-space
         color-scale-outside
         color-scale-at
         sequential-color-scale
         diverging-color-scale
         scientific-color-scale?
         scientific-color-scale-kind
         scientific-color-scale-minimum
         scientific-color-scale-maximum
         scientific-color-scale-midpoint
         scientific-color-scale-missing
         scientific-color-scale-outside
         scientific-color-scale-at)


;;;
;;; Data Representation
;;;

(struct color-scale-value (stops space outside) #:transparent)

;; Carries the data meaning that a bare normalized scale intentionally omits.
(struct scientific-color-scale-value
  (kind minimum maximum midpoint missing outside normalized-scale)
  #:transparent)


;;;
;;; Construction and Queries
;;;

;; color-scale : #:stops (listof paint-stop?)
;;               [#:space interpolation-space?]
;;               [#:outside outside-policy?]
;;               -> color-scale?
;; Creates an immutable scalar-to-color mapping.  Stop offsets are ordered in
;; [0,1]; equal adjacent offsets describe a hard discontinuity.
(define (color-scale #:stops stops
                     #:space [space 'srgb-linear]
                     #:outside [outside 'clamp])
  (unless (memq space '(srgb srgb-linear oklab))
    (raise-argument-error
     'color-scale
     "one of 'srgb, 'srgb-linear, or 'oklab as #:space"
     space))
  (unless (memq outside '(clamp error))
    (raise-argument-error
     'color-scale
     "one of 'clamp or 'error as #:outside"
     outside))
  (unless (and (list? stops) (>= (length stops) 2) (andmap paint-stop? stops))
    (raise-argument-error
     'color-scale
     "a list of at least two paint-stop values as #:stops"
     stops))
  (define normalized-stops
    (for/list ([stop (in-list stops)])
      (paint-stop (paint-stop-offset stop)
                  (normalize-color-spec (paint-stop-color stop) 'color-scale))))
  (unless (for/and ([previous (in-list normalized-stops)]
                    [next (in-list (cdr normalized-stops))])
            (<= (paint-stop-offset previous) (paint-stop-offset next)))
    (raise-arguments-error
     'color-scale
     "ordered paint-stop offsets as #:stops"
     "stops" stops))
  (color-scale-value (vector->immutable-vector (list->vector normalized-stops))
                     space
                     outside))

;; color-scale? : any/c -> boolean?
;; Reports whether value is an immutable validated color scale.
(define (color-scale? value) (color-scale-value? value))

;; color-scale-stops : color-scale? -> immutable-vectorof paint-stop?
;; Returns the normalized stops in their authored order.
(define (color-scale-stops scale)
  (check-scale 'color-scale-stops scale)
  (color-scale-value-stops scale))

;; color-scale-space : color-scale? -> symbol?
;; Returns the declared authoring interpolation space.
(define (color-scale-space scale)
  (check-scale 'color-scale-space scale)
  (color-scale-value-space scale))

;; color-scale-outside : color-scale? -> symbol?
;; Returns whether coordinates outside the stop domain clamp or signal error.
(define (color-scale-outside scale)
  (check-scale 'color-scale-outside scale)
  (color-scale-value-outside scale))

;; color-scale-at : color-scale? finite-real? -> color-spec?
;; Samples a scale without resolving its semantic colors.  At a repeated stop
;; offset, the final stop at that offset wins; immediately to its left the
;; preceding segment remains in effect.  This makes equal offsets a
;; deterministic hard discontinuity.
(define (color-scale-at scale coordinate)
  (check-scale 'color-scale-at scale)
  (unless (finite-real? coordinate)
    (raise-argument-error 'color-scale-at "finite-real? coordinate" coordinate))
  (define stops (color-scale-value-stops scale))
  (define first-stop (vector-ref stops 0))
  (define last-stop (vector-ref stops (sub1 (vector-length stops))))
  (cond
    [(< coordinate (paint-stop-offset first-stop))
     (outside-result scale coordinate first-stop)]
    [(> coordinate (paint-stop-offset last-stop))
     (outside-result scale coordinate last-stop)]
    [else
     ;; Find the first offset strictly greater than `coordinate`, then use its
     ;; predecessor. This upper-bound search preserves the documented rule
     ;; that the final repeated stop wins without scanning every prior stop.
     (define left-index (rightmost-stop-at-or-before stops coordinate))
     (define left (vector-ref stops left-index))
     (cond
       [(or (= left-index (sub1 (vector-length stops)))
            (= coordinate (paint-stop-offset left)))
        (paint-stop-color left)]
       [else
        (define right (vector-ref stops (add1 left-index)))
        (color-mix (paint-stop-color left)
                   (paint-stop-color right)
                   (/ (- coordinate (paint-stop-offset left))
                      (- (paint-stop-offset right) (paint-stop-offset left)))
                   #:space (color-scale-value-space scale))])]))

(define (rightmost-stop-at-or-before stops coordinate)
  ;; `color-scale-at` has already handled coordinates outside the closed stop
  ;; domain, so this upper bound always returns an index in the vector.
  (let loop ([low 0] [high (vector-length stops)])
    (if (= low high)
        (sub1 low)
        (let* ([middle (quotient (+ low high) 2)]
               [offset (paint-stop-offset (vector-ref stops middle))])
          (if (<= offset coordinate)
              (loop (add1 middle) high)
              (loop low middle))))))


;;;
;;; Scientific Scalar Recipes
;;;

;; sequential-color-scale : #:minimum finite-real? #:maximum finite-real?
;;                          ... -> scientific-color-scale?
;; Creates a reviewed two-ended scalar scale. Its low-to-high ordering is
;; explicit and therefore does not reverse when themes change.
(define (sequential-color-scale #:minimum minimum
                                #:maximum maximum
                                #:low [low aqua-d]
                                #:high [high gold-d]
                                #:missing [missing theme-muted]
                                #:space [space 'oklab]
                                #:outside [outside 'clamp])
  (check-domain 'sequential-color-scale minimum maximum)
  (make-scientific-scale 'sequential minimum maximum #f
                         low #f high missing space outside))

;; diverging-color-scale : #:minimum finite-real? #:maximum finite-real?
;;                         #:midpoint finite-real? ... -> scientific-color-scale?
;; Creates a three-stop scale whose declared midpoint has semantic meaning.
(define (diverging-color-scale #:minimum minimum
                               #:maximum maximum
                               #:midpoint midpoint
                               #:low [low aqua-d]
                               #:middle [middle gray-b]
                               #:high [high red-d]
                               #:missing [missing theme-muted]
                               #:space [space 'oklab]
                               #:outside [outside 'clamp])
  (check-domain 'diverging-color-scale minimum maximum)
  (unless (and (finite-real? midpoint) (<= minimum midpoint maximum))
    (raise-arguments-error
     'diverging-color-scale
     "a finite midpoint within the declared domain"
     "minimum" minimum "midpoint" midpoint "maximum" maximum))
  (make-scientific-scale 'diverging minimum maximum midpoint
                         low middle high missing space outside))

;; scientific-color-scale? : any/c -> boolean?
;; Reports whether value carries an explicit scalar-data scale policy.
(define (scientific-color-scale? value) (scientific-color-scale-value? value))

(define (scientific-color-scale-kind scale)
  (check-scientific-scale 'scientific-color-scale-kind scale)
  (scientific-color-scale-value-kind scale))
(define (scientific-color-scale-minimum scale)
  (check-scientific-scale 'scientific-color-scale-minimum scale)
  (scientific-color-scale-value-minimum scale))
(define (scientific-color-scale-maximum scale)
  (check-scientific-scale 'scientific-color-scale-maximum scale)
  (scientific-color-scale-value-maximum scale))
(define (scientific-color-scale-midpoint scale)
  (check-scientific-scale 'scientific-color-scale-midpoint scale)
  (scientific-color-scale-value-midpoint scale))
(define (scientific-color-scale-missing scale)
  (check-scientific-scale 'scientific-color-scale-missing scale)
  (scientific-color-scale-value-missing scale))
(define (scientific-color-scale-outside scale)
  (check-scientific-scale 'scientific-color-scale-outside scale)
  (scientific-color-scale-value-outside scale))

;; scientific-color-scale-at : scientific-color-scale? any/c -> color-spec?
;; Non-finite input uses the explicit missing-data specification; it never
;; silently selects a numerical endpoint.
(define (scientific-color-scale-at scale value)
  (check-scientific-scale 'scientific-color-scale-at scale)
  (cond
    [(not (finite-real? value)) (scientific-color-scale-value-missing scale)]
    [else
     (define minimum (scientific-color-scale-value-minimum scale))
     (define maximum (scientific-color-scale-value-maximum scale))
     (color-scale-at
      (scientific-color-scale-value-normalized-scale scale)
      (/ (- value minimum) (- maximum minimum)))]))


;;;
;;; Local Helpers
;;;

(define (outside-result scale coordinate endpoint)
  (case (color-scale-value-outside scale)
    [(clamp) (paint-stop-color endpoint)]
    [(error)
     (raise-arguments-error
      'color-scale-at
      "a coordinate within the color scale's stop domain"
      "coordinate" coordinate
      "domain"
      (vector (paint-stop-offset (vector-ref (color-scale-value-stops scale) 0))
              (paint-stop-offset
               (vector-ref (color-scale-value-stops scale)
                           (sub1 (vector-length (color-scale-value-stops scale)))))))]))

(define (check-scale who value)
  (unless (color-scale? value)
    (raise-argument-error who "color-scale?" value)))

(define (make-scientific-scale kind minimum maximum midpoint low middle high missing space outside)
  (unless (color-spec? missing)
    (raise-argument-error 'scientific-color-scale "color-spec? as #:missing" missing))
  (define stops
    (if middle
        (let ([middle-offset (/ (- midpoint minimum) (- maximum minimum))])
          (list (paint-stop 0 low)
                (paint-stop middle-offset middle)
                (paint-stop 1 high)))
        (list (paint-stop 0 low) (paint-stop 1 high))))
  (scientific-color-scale-value
   kind minimum maximum midpoint
   (normalize-color-spec missing 'scientific-color-scale)
   outside
   (color-scale #:stops stops #:space space #:outside outside)))

(define (check-domain who minimum maximum)
  (unless (and (finite-real? minimum) (finite-real? maximum) (< minimum maximum))
    (raise-arguments-error who "finite minimum smaller than finite maximum"
                           "minimum" minimum "maximum" maximum)))

(define (check-scientific-scale who value)
  (unless (scientific-color-scale? value)
    (raise-argument-error who "scientific-color-scale?" value)))
