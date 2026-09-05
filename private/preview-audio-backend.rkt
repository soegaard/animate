#lang racket/base

;;;
;;; Preview Audio Backend Protocol
;;;

(require racket/generic
         "audio-plan.rkt")

(provide gen:preview-audio-backend
         preview-audio-backend?
         audio-backend-open
         audio-backend-play
         audio-backend-pause
         audio-backend-seek
         audio-backend-stop
         audio-backend-set-muted!
         audio-backend-muted?
         audio-backend-position
         audio-backend-close
         audio-backend-capabilities)

;; Backends own effects but share absolute timeline values with the visual
;; clock. A missing backend is represented by #f at the integration boundary,
;; rather than silently altering semantic preview time.
(define-generics preview-audio-backend
  (audio-backend-open preview-audio-backend audio-plan)
  (audio-backend-play preview-audio-backend time speed)
  (audio-backend-pause preview-audio-backend)
  (audio-backend-seek preview-audio-backend time)
  (audio-backend-stop preview-audio-backend)
  (audio-backend-set-muted! preview-audio-backend muted?)
  (audio-backend-muted? preview-audio-backend)
  (audio-backend-position preview-audio-backend)
  (audio-backend-close preview-audio-backend)
  (audio-backend-capabilities preview-audio-backend))
