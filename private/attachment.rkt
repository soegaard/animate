#lang racket/base

;;;
;;; Live Visual Attachments
;;;

;; Defines a derived-Visual convenience layer for world-space content that
;; follows one top-level or nested target's sampled reference point.

(require "derived-visual.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "layout-attachment.rkt"
         "visual-model.rkt")

(provide attach-to
         layout-attached-visual?
         layout-attached-visual-content
         layout-attached-visual-target
         layout-attached-visual-target-anchor
         layout-attached-visual-self-anchor
         layout-attached-visual-offset)

; attach-to : visual? (or/c visual? symbol? visual-path?)
;             [#:offset vec2?]
;             [#:target-anchor layout-attachment-anchor?]
;             [#:self-anchor layout-attachment-anchor?]
;             -> (or/c derived-visual? layout-attached-visual?)
;;   Makes ordinary world-space content follow a sampled target reference point,
;; or, when either anchor is not center, a live renderer-measured box anchor.
(define (attach-to content target
                   #:offset [offset origin]
                   #:target-anchor [target-anchor 'center]
                   #:self-anchor [self-anchor 'center])
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
  (unless (layout-attachment-anchor? target-anchor)
    (raise-argument-error 'attach-to "layout-attachment-anchor?" target-anchor))
  (unless (layout-attachment-anchor? self-anchor)
    (raise-argument-error 'attach-to "layout-attachment-anchor?" self-anchor))
  (define target-address
    (visual-target-id target 'attach-to))
  (define content-id (visual-id content))
  (define target-id
    (if (symbol? target-address)
        target-address
        (car (reverse target-address))))
  (when (eq? content-id target-id)
    (raise-arguments-error
     'attach-to
     "content and target with distinct identities"
     "content-id" content-id
     "target" target-address))
  (if (and (eq? target-anchor 'center)
           (eq? self-anchor 'center))
      ;; Preserve SCENE-CD's renderer-independent derived-Visual behavior for
      ;; the existing centre-to-centre operation.
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
          (vec2+ (visual-position target-visual) offset))))
      (make-layout-attached-visual
       content target-address target-anchor self-anchor offset)))
