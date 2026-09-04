#lang racket/base

;;;
;;; Semantic Rate Functions
;;;

;; A rate function is a transparent, callable value rather than an anonymous
;; procedure.  It remains usable anywhere the historical easing procedure API
;; is accepted, while its kind and validated parameters survive scene printing
;; for automatic authoring-cache fingerprints.

(require (only-in racket/math pi)
         "geometry.rkt")

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
         there-and-back-with-pause
         cubic-bezier
         spring
         reverse-rate
         compose-rate
         squish-rate
         change-speed)


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
        (map rate-parameter->datum (rate-function-parameters value))))

(define (rate-parameter->datum parameter)
  (if (rate-function? parameter)
      (rate-function->datum parameter)
      parameter))


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

;; cubic-bezier : #:x1 finite-unit? #:y1 finite-real?
;;                #:x2 finite-unit? #:y2 finite-real? -> rate-function?
;; A CSS/Manim-style cubic Bézier timing curve. x controls time, so constraining
;; its two handles to [0,1] makes the bisection inversion deterministic.
(define (cubic-bezier #:x1 [x1 1/4] #:y1 [y1 1/10]
                      #:x2 [x2 1/4] #:y2 [y2 1])
  (check-finite-unit 'cubic-bezier "x1" x1)
  (check-finite-real 'cubic-bezier "y1" y1)
  (check-finite-unit 'cubic-bezier "x2" x2)
  (check-finite-real 'cubic-bezier "y2" y2)
  (rate-function 'cubic-bezier (list x1 y1 x2 y2)))

;; spring : [#:frequency positive-finite-real?]
;;          [#:damping nonnegative-finite-real?] -> rate-function?
;; A deterministic damped timing curve. Intermediate overshoot is preserved by
;; direct evaluation (the scene clamps its ordinary progress), while exact
;; timeline endpoints remain the standard 0 and 1.
(define (spring #:frequency [frequency 3] #:damping [damping 6])
  (check-positive-finite 'spring "frequency" frequency)
  (check-nonnegative-finite 'spring "damping" damping)
  (rate-function 'spring (list frequency damping)))

;; reverse-rate : rate-function? -> rate-function?
;; Reverses time while preserving conventional 0/1 endpoints for ordinary
;; forward rate functions.
(define (reverse-rate function)
  (check-rate-function 'reverse-rate function)
  (rate-function 'reverse-rate (list function)))

;; compose-rate : rate-function? rate-function? ... -> rate-function?
;; `(compose-rate outer inner)` evaluates outer after inner. Requiring at least
;; one semantic rate keeps the resulting value inspectable and serializable.
(define (compose-rate first . rest)
  (define functions (cons first rest))
  (for ([function (in-list functions)])
    (check-rate-function 'compose-rate function))
  (rate-function 'compose-rate functions))

;; squish-rate : rate-function? #:from finite-unit? #:to finite-unit? -> rate-function?
;; Runs a rate only over [from,to], holding at 0 and 1 outside that interval.
(define (squish-rate function #:from [from 0] #:to [to 1])
  (check-rate-function 'squish-rate function)
  (check-finite-unit 'squish-rate "from" from)
  (check-finite-unit 'squish-rate "to" to)
  (unless (< from to)
    (raise-arguments-error
     'squish-rate "a from value strictly smaller than to" "from" from "to" to))
  (rate-function 'squish-rate (list function from to)))

;; change-speed : (listof (list/c finite-unit? positive-finite-real?)) -> rate-function?
;; Converts a piecewise-linear speed profile into elapsed animation progress.
;; A speed of two covers twice as much animation distance per unit wall-clock
;; time as speed one. The profile must start at time zero and end at time one.
(define (change-speed keyframes)
  (define checked (check-speed-keyframes 'change-speed keyframes))
  (rate-function 'change-speed (list checked)))


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
       [(cubic-bezier)
        (apply cubic-bezier-progress
               progress
               (rate-function-parameters value))]
       [(spring)
        (define frequency (car (rate-function-parameters value)))
        (define damping (cadr (rate-function-parameters value)))
        (- 1
           (* (exp (* -1 damping progress))
              (cos (* 2 pi frequency progress))))]
       [(reverse-rate)
        (- 1
           (rate-function-apply
            (car (rate-function-parameters value))
            (- 1 progress)))]
       [(compose-rate)
        (for/fold ([result progress])
                  ([function (in-list (reverse (rate-function-parameters value)))])
          (rate-function-apply function result))]
       [(squish-rate)
        (define function (car (rate-function-parameters value)))
        (define from (cadr (rate-function-parameters value)))
        (define to (caddr (rate-function-parameters value)))
        (cond [(<= progress from) 0]
              [(>= progress to) 1]
              [else (rate-function-apply function (/ (- progress from) (- to from)))])]
       [(change-speed)
        (change-speed-progress progress (car (rate-function-parameters value)))]
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

(define (check-nonnegative-finite who field value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-arguments-error who "nonnegative finite real number" field value)))

(define (check-finite-real who field value)
  (unless (finite-real? value)
    (raise-arguments-error who "finite real number" field value)))

(define (check-finite-unit who field value)
  (unless (and (finite-real? value) (<= 0 value 1))
    (raise-arguments-error who "finite real number in [0, 1]" field value)))

(define (check-rate-function who value)
  (unless (rate-function? value)
    (raise-argument-error who "rate-function?" value)))

(define (cubic-bezier-progress progress x1 y1 x2 y2)
  (define p (exact->inexact (clamp-unit progress)))
  (define (curve first-control second-control t)
    (define complement (- 1 t))
    (+ (* 3 complement complement t first-control)
       (* 3 complement t t second-control)
       (* t t t)))
  ;; x is monotone for x1,x2 in [0,1]. Forty bisections gives a deterministic
  ;; sub-pixel-irrelevant inverse while avoiding platform-dependent solvers.
  (define parameter
    (let loop ([lower 0.0] [upper 1.0] [remaining 40])
      (if (zero? remaining)
          (/ (+ lower upper) 2)
          (let ([middle (/ (+ lower upper) 2)])
            (if (< (curve x1 x2 middle) p)
                (loop middle upper (sub1 remaining))
                (loop lower middle (sub1 remaining)))))))
  (curve y1 y2 parameter))

(define (check-speed-keyframes who keyframes)
  (unless (and (list? keyframes) (>= (length keyframes) 2))
    (raise-argument-error who "list with at least two speed keyframes" keyframes))
  (define checked
    (for/list ([keyframe (in-list keyframes)])
      (unless (and (list? keyframe) (= (length keyframe) 2))
        (raise-argument-error who "two-element (time speed) list" keyframe))
      (define time (car keyframe))
      (define speed (cadr keyframe))
      (check-finite-unit who "keyframe time" time)
      (check-positive-finite who "keyframe speed" speed)
      (list time speed)))
  (unless (zero? (caar checked))
    (raise-arguments-error who "a first keyframe at time 0" "keyframes" keyframes))
  (unless (= (caar (reverse checked)) 1)
    (raise-arguments-error who "a final keyframe at time 1" "keyframes" keyframes))
  (for ([left (in-list checked)] [right (in-list (cdr checked))])
    (unless (< (car left) (car right))
      (raise-arguments-error
       who "strictly increasing keyframe times" "keyframes" keyframes)))
  checked)

(define (change-speed-progress progress keyframes)
  (define p (clamp-unit progress))
  (define total (speed-integral 1 keyframes))
  (/ (speed-integral p keyframes) total))

;; Integral of a linearly interpolated positive speed over [0,progress].
(define (speed-integral progress keyframes)
  (for/fold ([total 0])
            ([left (in-list keyframes)] [right (in-list (cdr keyframes))])
    (define start (car left))
    (define finish (car right))
    (define speed-start (cadr left))
    (define speed-finish (cadr right))
    (define covered (min (max 0 (- progress start)) (- finish start)))
    (define slope (/ (- speed-finish speed-start) (- finish start)))
    (+ total
       (* speed-start covered)
       (* 1/2 slope covered covered))))

(define (clamp-unit value)
  (min 1 (max 0 value)))
