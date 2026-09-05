#lang racket/base

;;;
;;; Project Preview Worker Protocol
;;;

;; Every value crossing the process boundary is a prefab, reader-safe datum.
;; In particular, bitmaps never travel through a Racket place/channel: the
;; worker writes a temporary PNG and the preview process owns loading and
;; deleting it.  This keeps the protocol portable across Racket versions and
;; prevents a GUI eventspace from acquiring a foreign bitmap object.

(provide (struct-out worker-load-project)
         (struct-out worker-render-frame)
         (struct-out worker-cancel)
         (struct-out worker-reload)
         (struct-out worker-shutdown)
         (struct-out worker-ready)
         (struct-out worker-frame-started)
         (struct-out worker-frame-complete)
         (struct-out worker-frame-failed)
         (struct-out worker-log)
         (struct-out worker-stopped)
         worker-request?
         worker-response?)

;; module-path is serialized as a string. The source binding is intentionally
;; constrained to a module export, which is what lets a newly spawned worker
;; recreate project semantics after a hard cancellation.
(struct worker-load-project
  (plan-fingerprint module-path binding document-generation)
  #:prefab)

;; sample is either '(frame INDEX FPS) or '(time SECONDS). output-path names a
;; parent-owned temporary PNG. Generations and request id are echoed in every
;; render response, allowing a controller to reject obsolete results.
(struct worker-render-frame
  (plan-fingerprint document-generation render-generation request-id
                    sample pixel-scale supersample output-path)
  #:prefab)

(struct worker-cancel
  (plan-fingerprint document-generation render-generation request-id)
  #:prefab)

(struct worker-reload
  (plan-fingerprint module-path binding document-generation)
  #:prefab)

(struct worker-shutdown () #:prefab)

(struct worker-ready (plan-fingerprint document-generation) #:prefab)
(struct worker-frame-started
  (plan-fingerprint document-generation render-generation request-id)
  #:prefab)
(struct worker-frame-complete
  (plan-fingerprint document-generation render-generation request-id
                    output-path diagnostics)
  #:prefab)
(struct worker-frame-failed
  (plan-fingerprint document-generation render-generation request-id message)
  #:prefab)
(struct worker-log
  (plan-fingerprint level message)
  #:prefab)
(struct worker-stopped (reason) #:prefab)

(define (worker-request? value)
  (or (worker-load-project? value)
      (worker-render-frame? value)
      (worker-cancel? value)
      (worker-reload? value)
      (worker-shutdown? value)))

(define (worker-response? value)
  (or (worker-ready? value)
      (worker-frame-started? value)
      (worker-frame-complete? value)
      (worker-frame-failed? value)
      (worker-log? value)
      (worker-stopped? value)))
