#lang racket/base

;;;
;;; Live Visual Attachments
;;;

;; Defines a derived-Visual convenience layer for world-space content that
;; follows one top-level or nested target's sampled reference point.

(require "derived-visual.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "visual-model.rkt")

(provide attach-to)

; attach-to : visual? (or/c visual? symbol? visual-path?)
;             [#:offset vec2?] -> derived-visual?
;;   Makes ordinary world-space content follow a sampled target reference point.
(define (attach-to content target #:offset [offset origin])
  (unless (visual? content)
    (raise-argument-error 'attach-to "visual?" content))
  (when (derived-visual? content)
    (raise-arguments-error
     'attach-to
     "a concrete content Visual, not a derived Visual"
     "content" content))
  (when (frame-space-visual? content)
    (raise-arguments-error
     'attach-to
     "ordinary world-space content, not a frame-space Visual"
     "content" content))
  (unless (vec2? offset)
    (raise-argument-error 'attach-to "vec2?" offset))
  (define target-address
    (visual-target-id target 'attach-to))
  (derived-visual
   content
   (lambda (context template)
     (define target-visual
       (derived-context-visual-ref context target-address))
     (when (frame-space-visual? target-visual)
       (raise-arguments-error
        'attach-to
        "a target in world space, not a frame-space Visual"
        "target" target-address
        "resolved-target" target-visual))
     (visual-with-position
      template
      (vec2+ (visual-position target-visual) offset)))))
