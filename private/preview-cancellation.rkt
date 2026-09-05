#lang racket/base

;;;
;;; Cooperative Preview Cancellation
;;;

;; A token crosses the controller/worker boundary without granting either side
;; ownership of the other.  In-process rendering can only cooperate at safe
;; semantic boundaries; a subprocess worker may later translate the same token
;; into a hard restart.

(provide cancellation-token?
         make-cancellation-token
         cancellation-requested?
         cancellation-reason
         cancel!
         check-cancellation
         exn:fail:preview-canceled?
         exn:fail:preview-canceled-token
         exn:fail:preview-canceled-reason)

(struct cancellation-token-value (requested reason)
  #:transparent)

(define cancellation-token? cancellation-token-value?)

(struct exn:fail:preview-canceled exn:fail (token reason)
  #:transparent)

(define (make-cancellation-token)
  (cancellation-token-value (box #f) (box #f)))

(define (cancellation-requested? token)
  (check-token 'cancellation-requested? token)
  (unbox (cancellation-token-value-requested token)))

(define (cancellation-reason token)
  (check-token 'cancellation-reason token)
  (unbox (cancellation-token-value-reason token)))

; cancel! : cancellation-token? [symbol?] -> void?
;; Cancellation is idempotent.  The first explicit reason is retained so
;; diagnostics explain the event that made work obsolete.
(define (cancel! token [reason 'superseded])
  (check-token 'cancel! token)
  (unless (symbol? reason)
    (raise-argument-error 'cancel! "symbol?" reason))
  (unless (unbox (cancellation-token-value-requested token))
    (set-box! (cancellation-token-value-reason token) reason)
    (set-box! (cancellation-token-value-requested token) #t))
  (void))

; check-cancellation : cancellation-token? -> void?
;; Built-in work calls this at coarse, deterministic boundaries.  It does not
;; force-interrupt arbitrary user code or foreign renderer calls.
(define (check-cancellation token)
  (check-token 'check-cancellation token)
  (when (cancellation-requested? token)
    (raise
     (exn:fail:preview-canceled
      (format "preview render canceled: ~a" (cancellation-reason token))
      (current-continuation-marks)
      token
      (cancellation-reason token))))
  (void))

(define (check-token who value)
  (unless (cancellation-token? value)
    (raise-argument-error who "cancellation-token?" value)))
