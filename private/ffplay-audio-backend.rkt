#lang racket/base

;;;
;;; Optional FFplay Audio Backend
;;;

;; FFplay is intentionally an optional adapter. It starts a seekable proxy WAV
;; in its own subprocess; the preview remains fully usable when ffplay is not
;; installed. Position is an explicit monotonic estimate, not a claim that
;; ffplay exposes sample-accurate feedback.

(require racket/path
         racket/system
         "preview-audio-backend.rkt"
         "audio-plan.rkt"
         (only-in "geometry.rkt" finite-real?))

(provide ffplay-audio-backend
         ffplay-audio-backend?
         ffplay-audio-backend-available?)

(struct ffplay-audio-backend-value
  (executable plan process position start-milliseconds playing? closed? muted?)
  #:mutable
  #:transparent
  #:methods gen:preview-audio-backend
  [(define (audio-backend-open self plan)
     (unless (preview-audio-plan? plan)
       (raise-argument-error 'audio-backend-open "preview-audio-plan?" plan))
     (define proxy (preview-audio-plan-proxy-path plan))
     (unless (and proxy (file-exists? proxy))
       (raise-arguments-error 'audio-backend-open
                              "an existing prepared preview-audio proxy"
                              "proxy-path" proxy))
     (set-ffplay-audio-backend-value-plan! self plan)
     self)
   (define (audio-backend-play self time speed)
     (check-time 'audio-backend-play time)
     (unless (= speed 1)
       (raise-arguments-error 'audio-backend-play
                              "an ffplay backend supports speed 1 only"
                              "speed" speed))
     (ensure-opened 'audio-backend-play self)
     (stop-process! self)
     (define plan (ffplay-audio-backend-value-plan self))
     (define arguments
       (list "-nodisp" "-autoexit" "-loglevel" "error"
             "-volume"
             (if (ffplay-audio-backend-value-muted? self) "0" "100")
             "-ss" (number->string time)
             (path-string->string (preview-audio-plan-proxy-path plan))))
     (define-values (process _stdout _stdin _stderr)
       (apply subprocess #f #f #f
              (ffplay-audio-backend-value-executable self)
              arguments))
     (set-ffplay-audio-backend-value-process! self process)
     (set-ffplay-audio-backend-value-position! self time)
     (set-ffplay-audio-backend-value-start-milliseconds!
      self (current-inexact-monotonic-milliseconds))
     (set-ffplay-audio-backend-value-playing?! self #t)
     (void))
   (define (audio-backend-pause self)
     (set-ffplay-audio-backend-value-position! self (audio-backend-position self))
     (stop-process! self)
     (set-ffplay-audio-backend-value-playing?! self #f)
     (void))
   (define (audio-backend-seek self time)
     (check-time 'audio-backend-seek time)
     (set-ffplay-audio-backend-value-position! self time)
     (set-ffplay-audio-backend-value-start-milliseconds!
      self (current-inexact-monotonic-milliseconds))
     (when (ffplay-audio-backend-value-playing? self)
       (audio-backend-play self time 1))
     (void))
   (define (audio-backend-stop self)
     (stop-process! self)
     (set-ffplay-audio-backend-value-position! self 0)
     (set-ffplay-audio-backend-value-playing?! self #f)
     (void))
   (define (audio-backend-set-muted! self muted?)
     (unless (boolean? muted?)
       (raise-argument-error 'audio-backend-set-muted! "boolean?" muted?))
     (unless (equal? muted? (ffplay-audio-backend-value-muted? self))
       (set-ffplay-audio-backend-value-muted?! self muted?)
       ;; ffplay has no portable live-volume control. Restarting at the
       ;; monitor's current estimated time changes only output volume; it
       ;; never changes the controller's semantic clock.
       (when (ffplay-audio-backend-value-playing? self)
         (audio-backend-play self (audio-backend-position self) 1)))
     (void))
   (define (audio-backend-muted? self)
     (ffplay-audio-backend-value-muted? self))
   (define (audio-backend-position self)
     (if (ffplay-audio-backend-value-playing? self)
         (+ (ffplay-audio-backend-value-position self)
            (/ (- (current-inexact-monotonic-milliseconds)
                  (ffplay-audio-backend-value-start-milliseconds self))
               1000.0))
         (ffplay-audio-backend-value-position self)))
   (define (audio-backend-close self)
     (stop-process! self)
     (set-ffplay-audio-backend-value-playing?! self #f)
     (set-ffplay-audio-backend-value-closed?! self #t)
     (void))
   (define (audio-backend-capabilities _self)
     (hasheq 'seek? #t 'rate? #f 'position? 'estimated 'mute? #t 'subprocess? #t))])

(define (ffplay-audio-backend #:executable [executable (find-executable-path "ffplay")])
  (unless executable
    (raise-arguments-error 'ffplay-audio-backend
                           "FFplay available on PATH" "executable" "ffplay"))
  (unless (path-string? executable)
    (raise-argument-error 'ffplay-audio-backend "path-string?" executable))
  (ffplay-audio-backend-value executable #f #f 0 0 #f #f #f))

(define ffplay-audio-backend? ffplay-audio-backend-value?)
(define (ffplay-audio-backend-available?) (and (find-executable-path "ffplay") #t))

(define (ensure-opened who self)
  (when (ffplay-audio-backend-value-closed? self)
    (raise-arguments-error who "an open audio backend" "backend" self))
  (unless (ffplay-audio-backend-value-plan self)
    (raise-arguments-error who "audio-backend-open before playback" "backend" self)))

(define (stop-process! self)
  (define process (ffplay-audio-backend-value-process self))
  (when (and process (not (eq? (subprocess-status process) 'running)))
    (set-ffplay-audio-backend-value-process! self #f))
  (when (and process (eq? (subprocess-status process) 'running))
    (subprocess-kill process #t)
    (set-ffplay-audio-backend-value-process! self #f)))

(define (check-time who value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-argument-error who "nonnegative finite real?" value)))

(define (path-string->string value)
  (if (path? value) (path->string value) value))
