#lang racket/base

;;;
;;; Vector Fields
;;;

;; Defines immutable sampled vector fields as ordinary groups of semantic arrows.
;; Sampling occurs only at construction; the returned group retains no callback
;; or renderer state and its individual arrows have stable nested identities.

(require "arrow-visual.rkt"
         "axes-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "visual-model.rkt")

(provide vector-field)

; vector-field : axes-visual? (procedure-arity-includes/c 2)
;                #:id symbol?
;                [#:x-count exact-integer-at-least-1?]
;                [#:y-count exact-integer-at-least-1?]
;                [#:scale finite-real?]
;                [#:opacity opacity?]
;                [#:stroke color-spec?]
;                [#:stroke-width nonnegative-finite-real?]
;                [#:tip-length positive-finite-real?]
;                [#:tip-width positive-finite-real?]
;                -> group-visual?
;; Samples numeric vector values over an axes grid into stable arrow children.
(define (vector-field axes field
                      #:id id
                      #:x-count [x-count 9]
                      #:y-count [y-count 7]
                      #:scale [scale 1/4]
                      #:opacity [opacity 1]
                      #:stroke [stroke "seagreen"]
                      #:stroke-width [stroke-width 2]
                      #:tip-length [tip-length 3/20]
                      #:tip-width [tip-width 1/8])
  (check-vector-field-arguments axes field id x-count y-count scale opacity
                                stroke-width tip-length tip-width)
  (define xs (axis-grid-values (axes-visual-x-range axes) x-count))
  (define ys (axis-grid-values (axes-visual-y-range axes) y-count))
  (define arrows
    (for*/list ([y (in-list ys)]
                [y-index (in-naturals)]
                [x (in-list xs)]
                [x-index (in-naturals)]
                #:do [(define vector (sample-field-value field x y))]
                #:unless (and (zero? (vec2-x vector))
                              (zero? (vec2-y vector))))
      (define start (axes-coordinates->point axes x y))
      (define end
        (axes-coordinates->point
         axes
         (+ x (* scale (vec2-x vector)))
         (+ y (* scale (vec2-y vector)))))
      (arrow start end
             #:id (vector-field-arrow-id id x-index y-index)
             #:stroke stroke
             #:stroke-width stroke-width
             #:tip-length tip-length
             #:tip-width tip-width)))
  ;; Arrow points are already expressed in the containing coordinate system so
  ;; a neutral group preserves arbitrary axes transforms exactly.
  (group arrows #:id id #:opacity opacity))

; axis-grid-values : axis-range? exact-positive-integer? -> (listof finite-real?)
;; Returns evenly spaced closed grid values in increasing numeric order.
(define (axis-grid-values range count)
  (cond
    [(= count 1)
     (list (/ (+ (axis-range-minimum range)
                 (axis-range-maximum range))
              2))]
    [else
     (for/list ([index (in-range count)])
       (cond
         [(zero? index) (axis-range-minimum range)]
         [(= index (sub1 count)) (axis-range-maximum range)]
         [else
          (real-lerp (axis-range-minimum range)
                     (axis-range-maximum range)
                     (/ index (sub1 count)))]))]))

; sample-field-value : procedure? finite-real? finite-real? -> vec2?
;; Calls a field procedure once and validates its single semantic vector result.
(define (sample-field-value field x y)
  (define results
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error
             'vector-field
             "the vector-field procedure raised an exception"
             "x" x
             "y" y
             "exception message" (exn-message exception)))])
      (call-with-values (lambda () (field x y)) list)))
  (unless (= (length results) 1)
    (raise-arguments-error
     'vector-field
     "the vector-field procedure must return exactly one value"
     "x" x
     "y" y
     "result count" (length results)))
  (define result (car results))
  (unless (vec2? result)
    (raise-arguments-error
     'vector-field
     "the vector-field procedure must return a vec2"
     "x" x
     "y" y
     "result" result))
  result)

; vector-field-arrow-id : symbol? exact-nonnegative-integer?
;                         exact-nonnegative-integer? -> symbol?
;; Derives a stable grid-child identity.
(define (vector-field-arrow-id field-id x-index y-index)
  (string->symbol
   (format "~a-vector-~a-~a"
           (symbol->string field-id) x-index y-index)))

; check-vector-field-arguments : any/c any/c any/c any/c any/c any/c any/c
;                                any/c any/c any/c -> void?
(define (check-vector-field-arguments axes field id x-count y-count scale opacity
                                      stroke-width tip-length tip-width)
  (unless (axes-visual? axes)
    (raise-argument-error 'vector-field "axes-visual?" axes))
  (unless (and (procedure? field)
               (procedure-arity-includes? field 2))
    (raise-argument-error 'vector-field "procedure accepting two arguments" field))
  (unless (symbol? id)
    (raise-argument-error 'vector-field "symbol?" id))
  (for ([count (in-list (list x-count y-count))]
        [name (in-list '(#:x-count #:y-count))])
    (unless (and (exact-integer? count) (positive? count))
      (raise-arguments-error
       'vector-field
       "grid counts must be positive exact integers"
       "argument" name
       "value" count)))
  (unless (finite-real? scale)
    (raise-argument-error 'vector-field "finite real?" scale))
  (unless (opacity? opacity)
    (raise-argument-error 'vector-field "finite real in [0, 1]" opacity))
  (unless (and (finite-real? stroke-width) (not (negative? stroke-width)))
    (raise-argument-error 'vector-field "nonnegative finite real?" stroke-width))
  (for ([value (in-list (list tip-length tip-width))])
    (unless (and (finite-real? value) (positive? value))
      (raise-argument-error 'vector-field "positive finite real?" value))))
