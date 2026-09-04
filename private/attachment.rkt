#lang racket/base

;;;
;;; Live Visual Attachments
;;;

;; Defines relation-Visual conveniences for world-space content that follows
;; one top-level or nested target's sampled rendered-box anchor.

(require "affine-transform.rkt"
         "derived-visual.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "layout-attachment.rkt"
         "layout-box.rkt"
         "relation-context.rkt"
         "relation-dependency.rkt"
         "relation-spec.rkt"
         "relation-visual.rkt"
         "visual-model.rkt")

(provide attach-to)

; attach-to : visual? (or/c visual? symbol? visual-path?)
;             [#:offset vec2?]
;             [#:target-anchor layout-attachment-anchor?]
;             [#:self-anchor layout-attachment-anchor?]
;             -> relation-visual?
;; Makes ordinary world-space content follow a sampled target anchor. A
;; centre-to-centre attachment is semantic: it does not require renderer
;; measurement. Choosing an edge or corner of either Visual promotes the
;; relationship to the renderer-aware layout phase.
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
  (unless (and (affine-visual? content) (opacity-visual? content))
    (raise-argument-error
     'attach-to
     "a concrete world-space Visual supporting affine placement and opacity"
     content))
  (unless (vec2? offset)
    (raise-argument-error 'attach-to "vec2?" offset))
  (unless (layout-attachment-anchor? target-anchor)
    (raise-argument-error 'attach-to "layout-attachment-anchor?" target-anchor))
  (unless (layout-attachment-anchor? self-anchor)
    (raise-argument-error 'attach-to "layout-attachment-anchor?" self-anchor))
  (define target-address (visual-target-path target 'attach-to))
  (define content-id (visual-id content))
  (define target-id
    (car (reverse target-address)))
  (when (eq? content-id target-id)
    (raise-arguments-error
     'attach-to
     "content and target with distinct identities"
     "content-id" content-id
     "target" target-address))
  ;; Keep the authored content's affine/opacity state as intrinsic local
  ;; content. The relation itself starts with an identity envelope, so a later
  ;; move/rotate/scale/fade is an additional, ordinary relation animation.
  (define layout?
    (or (not (eq? target-anchor 'center))
        (not (eq? self-anchor 'center))))
  (define template
    (visual-with-opacity
     (visual-with-transform content identity-affine-transform)
     1))
  (relation-visual
   template
   #:phase (if layout? 'layout 'semantic)
   #:structure 'fixed
   #:depends-on
   (list (if layout?
             (anchor-dependency target-address target-anchor)
             (visual-dependency target-address)))
   (attachment-relation-spec
    target-address
    target-anchor
    self-anchor
    offset
    (visual-transform content)
    (visual-opacity content))))

;; Built-in attachment semantics are a serializable relation specification.
;; The stored intrinsic envelope is deliberately separate from the relation's
;; animation envelope, which begins at identity in `attach-to` above.
(struct attachment-relation-spec
  (target target-anchor self-anchor offset intrinsic-transform intrinsic-opacity)
  #:transparent
  #:methods gen:relation-spec
  [(define (resolve-relation-spec specification context template)
     (define content
       (visual-with-opacity
        (visual-with-transform
         template
         (attachment-relation-spec-intrinsic-transform specification))
        (attachment-relation-spec-intrinsic-opacity specification)))
     (define target
       (attachment-relation-spec-target specification))
     (define target-anchor
       (attachment-relation-spec-target-anchor specification))
     (define self-anchor
       (attachment-relation-spec-self-anchor specification))
     (define target-point
       (if (eq? target-anchor 'center)
           (relation-context-position context target)
           (relation-context-anchor-ref context target target-anchor)))
     (visual-with-position
      content
      (if (eq? self-anchor 'center)
          (vec2+ target-point
                 (attachment-relation-spec-offset specification))
          (attachment-content-center
           target-point
           self-anchor
           (attachment-relation-spec-offset specification)
           (relation-context-layout-box context content)))))])

;; Matches the pre-relation attachment rule: Picts are centred at a Visual's
;; semantic reference point, so an anchor is a signed half-extent from there.
(define (attachment-content-center target-point self-anchor offset content-box)
  (define half-width (/ (layout-box-width content-box) 2))
  (define half-height (/ (layout-box-height content-box) 2))
  (define desired-anchor (vec2+ target-point offset))
  (define center-offset
    (case self-anchor
      [(bottom-left) (vec2 half-width half-height)]
      [(bottom) (vec2 0 half-height)]
      [(bottom-right) (vec2 (- half-width) half-height)]
      [(left) (vec2 half-width 0)]
      [(center) origin]
      [(right) (vec2 (- half-width) 0)]
      [(top-left) (vec2 half-width (- half-height))]
      [(top) (vec2 0 (- half-height))]
      [(top-right) (vec2 (- half-width) (- half-height))]
      [else
       (raise-argument-error
        'attachment-content-center
        "layout-attachment-anchor?"
        self-anchor)]))
  (vec2+ desired-anchor center-offset))
