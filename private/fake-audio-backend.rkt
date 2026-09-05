#lang racket/base

;;;
;;; Deterministic Test Audio Backend
;;;

(require "preview-audio-backend.rkt"
         (only-in "geometry.rkt" finite-real?))

(provide fake-audio-backend
         fake-audio-backend?
         fake-audio-backend-closed?
         fake-audio-backend-playing?
         fake-audio-backend-muted?)

;; The caller controls the supplied `clock` thunk, normally with a box in a
;; test. This makes seeking and visual/audio synchronization testable without
;; a subprocess or physical audio device.
(struct fake-audio-backend-value (clock position started speed playing? closed? muted? plan)
  #:mutable
  #:transparent
  #:methods gen:preview-audio-backend
  [(define (audio-backend-open self plan)
     (set-fake-audio-backend-value-plan! self plan)
     self)
   (define (audio-backend-play self time speed)
     (check-time 'audio-backend-play time)
     (check-speed 'audio-backend-play speed)
     (set-fake-audio-backend-value-position! self time)
     (set-fake-audio-backend-value-started! self ((fake-audio-backend-value-clock self)))
     (set-fake-audio-backend-value-speed! self speed)
     (set-fake-audio-backend-value-playing?! self #t)
     (void))
   (define (audio-backend-pause self)
     (set-fake-audio-backend-value-position! self (audio-backend-position self))
     (set-fake-audio-backend-value-playing?! self #f)
     (void))
   (define (audio-backend-seek self time)
     (check-time 'audio-backend-seek time)
     (set-fake-audio-backend-value-position! self time)
     (set-fake-audio-backend-value-started! self ((fake-audio-backend-value-clock self)))
     (void))
   (define (audio-backend-stop self)
     (set-fake-audio-backend-value-position! self 0)
     (set-fake-audio-backend-value-playing?! self #f)
     (void))
   (define (audio-backend-set-muted! self muted?)
     (unless (boolean? muted?)
       (raise-argument-error 'audio-backend-set-muted! "boolean?" muted?))
     (set-fake-audio-backend-value-muted?! self muted?)
     (void))
   (define (audio-backend-muted? self)
     (fake-audio-backend-value-muted? self))
   (define (audio-backend-position self)
     (if (fake-audio-backend-value-playing? self)
         (+ (fake-audio-backend-value-position self)
            (* (fake-audio-backend-value-speed self)
               (- ((fake-audio-backend-value-clock self))
                  (fake-audio-backend-value-started self))))
         (fake-audio-backend-value-position self)))
   (define (audio-backend-close self)
     (set-fake-audio-backend-value-playing?! self #f)
     (set-fake-audio-backend-value-closed?! self #t)
     (void))
   (define (audio-backend-capabilities _self)
     (hasheq 'seek? #t 'rate? #t 'position? #t 'mute? #t 'subprocess? #f))])

(define (fake-audio-backend
         #:clock [clock (lambda () (/ (current-inexact-monotonic-milliseconds) 1000.0))])
  (unless (procedure-arity-includes? clock 0)
    (raise-argument-error 'fake-audio-backend "procedure accepting zero arguments" clock))
  (fake-audio-backend-value clock 0 (clock) 1 #f #f #f #f))

(define fake-audio-backend? fake-audio-backend-value?)
(define fake-audio-backend-closed? fake-audio-backend-value-closed?)
(define fake-audio-backend-playing? fake-audio-backend-value-playing?)
(define fake-audio-backend-muted? fake-audio-backend-value-muted?)

(define (check-time who value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-argument-error who "nonnegative finite real?" value)))
(define (check-speed who value)
  (unless (and (finite-real? value) (positive? value))
    (raise-argument-error who "positive finite real?" value)))
