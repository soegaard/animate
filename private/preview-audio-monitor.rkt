#lang racket/base

;;;
;;; Session-Owned Preview Audio Monitor
;;;

;; A monitor is the small policy layer between the controller's authoritative
;; absolute timeline and an effectful audio backend.  In particular, muting is
;; not a transport operation: the visual clock continues unchanged while the
;; backend is paused, and unmuting starts audio again at the current semantic
;; time.  Keeping that policy out of the GUI makes it usable by a future native
;; preview client and testable without a display or sound device.

(require "preview-audio-backend.rkt"
         (only-in "geometry.rkt" finite-real?))

(provide preview-audio-monitor
         preview-audio-monitor?
         preview-audio-monitor-backend
         preview-audio-monitor-muted?
         preview-audio-monitor-playing?
         preview-audio-monitor-sync!
         preview-audio-monitor-set-muted!)

(struct preview-audio-monitor (backend muted? playing? last-speed)
  #:mutable
  #:transparent
  #:guard
  (lambda (backend muted? playing? last-speed who)
    (unless (preview-audio-backend? backend)
      (raise-argument-error who "preview-audio-backend?" backend))
    (unless (boolean? muted?)
      (raise-argument-error who "boolean?" muted?))
    (unless (boolean? playing?)
      (raise-argument-error who "boolean?" playing?))
    (unless (or (not last-speed) (positive-finite-real? last-speed))
      (raise-argument-error who "#f or positive finite real" last-speed))
    (values backend muted? playing? last-speed)))

;; preview-audio-monitor-sync! : preview-audio-monitor? nonnegative-real?
;;                               boolean? positive-real? -> void?
;; Synchronizes backend output to an already sampled controller status.  The
;; caller's time is authoritative: an estimated backend position can trigger a
;; restart, but it never moves the Scene's playhead.
(define (preview-audio-monitor-sync! monitor time controller-playing? speed)
  (check-monitor 'preview-audio-monitor-sync! monitor)
  (check-time 'preview-audio-monitor-sync! time)
  (unless (boolean? controller-playing?)
    (raise-argument-error 'preview-audio-monitor-sync! "boolean?" controller-playing?))
  (check-speed 'preview-audio-monitor-sync! speed)
  (define backend (preview-audio-monitor-backend monitor))
  (cond
    [(and controller-playing? (not (preview-audio-monitor-muted? monitor)))
     (define backend-playing? (preview-audio-monitor-playing? monitor))
     (define drift
       (and backend-playing?
            (- (audio-backend-position backend) time)))
     (when (or (not backend-playing?)
               (not (equal? speed (preview-audio-monitor-last-speed monitor)))
               (and drift (> (abs drift) 1/4)))
       (audio-backend-play backend time speed)
       (set-preview-audio-monitor-playing?! monitor #t)
       (set-preview-audio-monitor-last-speed! monitor speed))]
    [(preview-audio-monitor-playing? monitor)
     ;; Pausing before seeking ensures muting, ordinary pause, scrubbing, and
     ;; end-of-range all leave the backend at the same next-resume position.
     (audio-backend-pause backend)
     (audio-backend-seek backend time)
     (set-preview-audio-monitor-playing?! monitor #f)
     (set-preview-audio-monitor-last-speed! monitor #f)])
  (void))

;; preview-audio-monitor-set-muted! : preview-audio-monitor? boolean?
;;                                    nonnegative-real? boolean? positive-real?
;;                                    -> void?
;; Muting deliberately calls the same synchronizer used by controller events.
;; This prevents an unmute from resuming at a stale backend position.
(define (preview-audio-monitor-set-muted! monitor muted? time controller-playing? speed)
  (check-monitor 'preview-audio-monitor-set-muted! monitor)
  (unless (boolean? muted?)
    (raise-argument-error 'preview-audio-monitor-set-muted! "boolean?" muted?))
  (unless (equal? muted? (preview-audio-monitor-muted? monitor))
    ;; Backends that can change volume without a restart receive the same
    ;; semantic control. The monitor still pauses them while muted, so this is
    ;; never relied upon to advance or preserve transport state.
    (audio-backend-set-muted! (preview-audio-monitor-backend monitor) muted?)
    (set-preview-audio-monitor-muted?! monitor muted?))
  (preview-audio-monitor-sync! monitor time controller-playing? speed))

(define (check-monitor who value)
  (unless (preview-audio-monitor? value)
    (raise-argument-error who "preview-audio-monitor?" value)))

(define (check-time who value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-argument-error who "nonnegative finite real" value)))

(define (check-speed who value)
  (unless (positive-finite-real? value)
    (raise-argument-error who "positive finite real" value)))

(define (positive-finite-real? value)
  (and (finite-real? value) (positive? value)))
