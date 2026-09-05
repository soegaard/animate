#lang racket/base

;;;
;;; Monotonic Preview Clock
;;;

;; The preview controller owns policy, but this small pure value supplies the
;; one absolute clock shared by visual and audio schedulers.  No render loop
;; advances a counter after rendering: a caller asks what time the clock says
;; at a given monotonic instant.

(require (only-in "geometry.rkt" finite-real?))

(provide preview-clock
         preview-clock?
         preview-clock-start-time
         preview-clock-start-milliseconds
         preview-clock-speed
         preview-clock-running?
         preview-clock-time
         preview-clock-restart
         preview-clock-pause)

(struct preview-clock-value (start-time start-milliseconds speed running?)
  #:transparent
  #:constructor-name make-preview-clock)

(define preview-clock? preview-clock-value?)
(define preview-clock-start-time preview-clock-value-start-time)
(define preview-clock-start-milliseconds preview-clock-value-start-milliseconds)
(define preview-clock-speed preview-clock-value-speed)
(define preview-clock-running? preview-clock-value-running?)

(define (preview-clock #:start-time [start-time 0]
                       #:start-milliseconds [start-milliseconds 0]
                       #:speed [speed 1]
                       #:running? [running? #f])
  (check-time 'preview-clock start-time)
  (unless (finite-real? start-milliseconds)
    (raise-argument-error 'preview-clock "finite real?" start-milliseconds))
  (unless (and (finite-real? speed) (positive? speed))
    (raise-argument-error 'preview-clock "positive finite real?" speed))
  (unless (boolean? running?)
    (raise-argument-error 'preview-clock "boolean?" running?))
  (make-preview-clock start-time start-milliseconds speed running?))

;; preview-clock-time : preview-clock? finite-real? -> nonnegative-real?
(define (preview-clock-time clock milliseconds)
  (check-clock 'preview-clock-time clock)
  (unless (finite-real? milliseconds)
    (raise-argument-error 'preview-clock-time "finite real?" milliseconds))
  (if (preview-clock-running? clock)
      (+ (preview-clock-start-time clock)
         (* (preview-clock-speed clock)
            (/ (- milliseconds (preview-clock-start-milliseconds clock)) 1000.0)))
      (preview-clock-start-time clock)))

;; Restarts from an exact semantic time.  The returned value is independent of
;; an old renderer's progress and is suitable for an audio backend too.
(define (preview-clock-restart clock time milliseconds #:speed [speed (preview-clock-speed clock)])
  (check-clock 'preview-clock-restart clock)
  (check-time 'preview-clock-restart time)
  (preview-clock #:start-time time #:start-milliseconds milliseconds
                 #:speed speed #:running? #t))

(define (preview-clock-pause clock milliseconds)
  (check-clock 'preview-clock-pause clock)
  (preview-clock #:start-time (preview-clock-time clock milliseconds)
                 #:start-milliseconds milliseconds
                 #:speed (preview-clock-speed clock)
                 #:running? #f))

(define (check-clock who value)
  (unless (preview-clock? value)
    (raise-argument-error who "preview-clock?" value)))

(define (check-time who value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-argument-error who "nonnegative finite real?" value)))
