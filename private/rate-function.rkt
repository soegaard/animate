#lang racket/base

;;;
;;; Semantic Rate Functions
;;;

;; A rate function is a transparent, callable value rather than an anonymous
;; procedure.  It remains usable anywhere the historical easing procedure API
;; is accepted, while its kind and validated parameters survive scene printing
;; for automatic authoring-cache fingerprints.

(require "geometry.rkt")

(provide rate-function?
         rate-function-name
         rate-function-parameters
         rate-function->datum
         rate-function-apply
         linear
         smooth
         smoothstep
         rush-into
         rush-from
         there-and-back
         there-and-back-with-pause)


;;;
;;; Data Representation

(struct rate-function (name parameters)
  #:transparent
  #:guard
  (lambda (name parameters who)
    (unless (symbol? name)
      (raise-argument-error who "symbol?" name))
    (unless (list? parameters)
      (raise-argument-error who "list?" parameters))
    (values name parameters))
  #:property prop:procedure
  (lambda (self progress)
    (rate-function-apply self progress)))

;; rate-function->datum : rate-function? -> datum?
;; Returns a compact, stable description useful in external metadata.  The
;; transparent structure itself is already serializable in a scene value; this
;; form is useful when an author wants only the easing declaration.
(define (rate-function->datum value)
  (unless (rate-function? value)
    (raise-argument-error 'rate-function->datum "rate-function?" value))
  (cons (rate-function-name value)
        (rate-function-parameters value)))


;;;
;;; Public Constructors

;; Keep `linear` a directly callable value for complete source compatibility
;; with existing `(scene-play ... #:easing linear)` code.
(define linear (rate-function 'linear '()))

;; smooth : [#:inflection positive-finite-real?] -> rate-function?
;; A normalized logistic S curve. The normalization gives exact 0 and 1 at
;; clip boundaries, avoiding endpoint snaps from a raw sigmoid.
(define (smooth #:inflection [inflection 10])
  (check-positive-finite 'smooth "inflection" inflection)
  (rate-function 'smooth (list inflection)))

;; smoothstep : -> rate-function?
;; Cubic smoothstep with zero slope at both endpoints.
(define (smoothstep)
  (rate-function 'smoothstep '()))

;; rush-into / rush-from : -> rate-function?
;; Accelerating and decelerating normalized versions of smooth.
(define (rush-into)
  (rate-function 'rush-into '()))

(define (rush-from)
  (rate-function 'rush-from '()))

;; there-and-back : -> rate-function?
;; One smooth excursion from 0 to 1 and back to 0.
(define (there-and-back)
  (rate-function 'there-and-back '()))

;; there-and-back-with-pause : [#:pause-ratio nonnegative-real-less-than-1?]
;;                               -> rate-function?
;; Holds the peak for `pause-ratio` of the unit interval.
(define (there-and-back-with-pause #:pause-ratio [pause-ratio 1/3])
  (unless (and (finite-real? pause-ratio)
               (<= 0 pause-ratio)
               (< pause-ratio 1))
    (raise-argument-error
     'there-and-back-with-pause
     "finite real number in [0, 1)"
     pause-ratio))
  (rate-function 'there-and-back-with-pause (list pause-ratio)))


;;;
;;; Evaluation

;; rate-function-apply : rate-function? finite-real? -> finite-real?
;; Rate functions accept any finite real progress. Scene sampling supplies the
;; conventional [0,1] interval; accepting other finite values also preserves
;; the conventional procedure behavior for direct use in author code.
(define (rate-function-apply value progress)
  (unless (rate-function? value)
    (raise-argument-error 'rate-function-apply "rate-function?" value))
  (unless (finite-real? progress)
    (raise-argument-error 'rate-function-apply "finite real number" progress))
  ;; Exact end values are a timeline invariant: clip finalization must never
  ;; depend on a floating-point approximation of an easing function. They also
  ;; make the semantic values pleasant to use directly in tests and author code.
  (cond
    [(zero? progress) 0]
    [(and (= progress 1)
          (memq (rate-function-name value)
                '(there-and-back there-and-back-with-pause)))
     0]
    [(= progress 1) 1]
    [else
     (case (rate-function-name value)
       [(linear) progress]
       [(smooth)
        (normalized-sigmoid progress (car (rate-function-parameters value)))]
       [(smoothstep)
        (* progress progress (- 3 (* 2 progress)))]
       [(rush-into)
        (* 2 (normalized-sigmoid (/ progress 2) 10))]
       [(rush-from)
        (- (* 2 (normalized-sigmoid (/ (+ progress 1) 2) 10)) 1)]
       [(there-and-back)
        (normalized-sigmoid (- 1 (abs (- 1 (* 2 progress)))) 10)]
       [(there-and-back-with-pause)
        (define pause-ratio (car (rate-function-parameters value)))
        (define rise-duration (/ (- 1 pause-ratio) 2))
        (cond
          [(<= progress rise-duration)
           (normalized-sigmoid (/ progress rise-duration) 10)]
          [(<= progress (+ rise-duration pause-ratio)) 1]
          [else
           (normalized-sigmoid (/ (- 1 progress) rise-duration) 10)])]
       [else
        (raise-arguments-error
         'rate-function-apply
         "a built-in rate-function kind"
         "rate-function" value)])]))

;; normalized-sigmoid : finite-real? positive-finite-real? -> finite-real?
;; Normalizes the logistic curve on [0,1].
(define (normalized-sigmoid progress inflection)
  (cond
    [(zero? progress) 0]
    [(= progress 1) 1]
    [else
     (define (sigmoid x)
       (/ 1 (+ 1 (exp (- x)))))
     (define lower (sigmoid (/ (- inflection) 2)))
     (define upper (sigmoid (/ inflection 2)))
     (/ (- (sigmoid (* inflection (- progress 1/2))) lower)
        (- upper lower))]))

(define (check-positive-finite who field value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "positive finite real number" field value)))
