#lang racket/base

;;;
;;; Crisp Labels Anchored to Spatial Points
;;;

;; projected-label is deliberately an ordinary 2D Visual definition, not a
;; texture or a billboard mesh.  Pict rendering resolves it after the owning
;; view3d has sampled and resolved its spatial relations, so formulas retain
;; normal source mapping and raster/vector quality.

(require "../affine-transform.rkt"
         "../camera.rkt"
         "../geometry.rkt"
         "../resolvable-visual.rkt"
         "../visual-model.rkt"
         "affine3.rkt"
         "camera3d.rkt"
         "projected-anchor.rkt"
         "raster-target3d.rkt"
         "software-renderer3d.rkt"
         "spatial-path.rkt"
         "vec3.rkt"
         "view3d-visual.rkt")

(provide projected-label
         projected-label?
         projected-label-view
         projected-label-target
         projected-label-offset
         projected-label-occlusion
         follow-projected-point
         follow-projected-spatial
         resolve-projected-label)

;; Keep generic operations distinct from the struct methods below.  A method
;; must delegate to its ordinary concrete template rather than recursively
;; invoking itself on that template.
(define template-visual-id visual-id)

(struct projected-label-value
  (template outer-transform outer-opacity view-id target offset occlusion)
  #:transparent
  #:methods gen:visual
  [(define (visual-id label)
     (template-visual-id (projected-label-value-template label)))
   (define (visual-position label)
     (affine-transform-translation
      (projected-label-value-outer-transform label)))
   (define (visual-with-position label position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy
      projected-label-value label
      [outer-transform
       (affine-transform-with-translation
        (projected-label-value-outer-transform label) position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform label)
     (projected-label-value-outer-transform label))
   (define (visual-with-transform label transform)
     (unless (affine-transform? transform)
       (raise-argument-error 'visual-with-transform "affine-transform?" transform))
     (struct-copy projected-label-value label [outer-transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity label)
     (projected-label-value-outer-opacity label))
   (define (visual-with-opacity label opacity)
     (unless (and (finite-real? opacity) (<= 0 opacity 1))
       (raise-argument-error
        'visual-with-opacity "finite real in the closed unit interval" opacity))
     (struct-copy projected-label-value label [outer-opacity opacity]))])

(define projected-label? projected-label-value?)
(define projected-label-view projected-label-value-view-id)
(define projected-label-target projected-label-value-target)
(define projected-label-offset projected-label-value-offset)
(define projected-label-occlusion projected-label-value-occlusion)

; projected-label : visual? #:view symbol? #:target (or/c vec3? spatial-path?)
;                   [#:offset vec2?]
;                   [#:occlusion (or/c 'always-visible 'hide 'fade)] -> projected-label?
;; Creates a fixed-screen-size 2D label whose centre follows one point in a
;; sampled view3d.  A vec3 target is already in the view's 3D world; a path is
;; relative to `view` unless it already begins with `view`.
(define (projected-label template
                         #:view view-id
                         #:target target
                         #:offset [offset origin]
                         #:occlusion [occlusion 'always-visible])
  (unless (visual? template)
    (raise-argument-error 'projected-label "visual?" template))
  (when (resolvable-visual? template)
    (raise-arguments-error
     'projected-label
     "a concrete 2D template, not a resolvable Visual"
     "template" template))
  (unless (and (affine-visual? template) (opacity-visual? template))
    (raise-arguments-error
     'projected-label
     "a template Visual supporting affine placement and opacity"
     "template" template))
  (unless (symbol? (visual-id template))
    (raise-arguments-error
     'projected-label
     "a template Visual with a symbol identity"
     "visual-id" (visual-id template)))
  (unless (symbol? view-id)
    (raise-argument-error 'projected-label "symbol? as #:view" view-id))
  (check-target 'projected-label target)
  (unless (vec2? offset)
    (raise-argument-error 'projected-label "vec2? as #:offset" offset))
  (unless (memq occlusion '(always-visible hide fade))
    (raise-argument-error 'projected-label
                          "(or/c 'always-visible 'hide 'fade) as #:occlusion" occlusion))
  (define outer-transform (visual-transform template))
  (define outer-opacity (visual-opacity template))
  (define local-template
    (visual-with-opacity
     (visual-with-transform template identity-affine-transform)
     1))
  (projected-label-value local-template outer-transform outer-opacity
                         view-id target offset occlusion))

; follow-projected-point : visual? #:view symbol? #:point vec3?
;                          [#:offset vec2?] -> projected-label?
;; Clear spelling for a projected-label whose target is a literal spatial point.
(define (follow-projected-point template
                                #:view view-id
                                #:point point
                                #:offset [offset origin]
                                #:occlusion [occlusion 'always-visible])
  (unless (vec3? point)
    (raise-argument-error 'follow-projected-point "vec3?" point))
  (projected-label template #:view view-id #:target point #:offset offset
                   #:occlusion occlusion))

; follow-projected-spatial : visual? #:view symbol? #:target spatial-path?
;                            [#:offset vec2?] -> projected-label?
;; Clear spelling for a projected-label that follows a stable spatial path.
(define (follow-projected-spatial template
                                  #:view view-id
                                  #:target target
                                  #:offset [offset origin]
                                  #:occlusion [occlusion 'always-visible])
  (unless (spatial-path? target)
    (raise-argument-error 'follow-projected-spatial "spatial-path?" target))
  (projected-label template #:view view-id #:target target #:offset offset
                   #:occlusion occlusion))

; resolve-projected-label : projected-label? view3d? camera? -> visual?
;; Produces a concrete ordinary 2D Visual positioned in the same world plane
;; as the outer scene.  The 3D camera affects only anchor position, never the
;; template's Pict scale or orientation.
(define (resolve-projected-label label view outer-camera)
  (unless (projected-label? label)
    (raise-argument-error 'resolve-projected-label "projected-label?" label))
  (unless (view3d? view)
    (raise-argument-error 'resolve-projected-label "view3d?" view))
  (unless (camera? outer-camera)
    (raise-argument-error 'resolve-projected-label "camera?" outer-camera))
  (unless (eq? (projected-label-value-view-id label) (visual-id view))
    (raise-arguments-error
     'resolve-projected-label
     "a view3d matching the label's #:view identity"
     "label-view-id" (projected-label-value-view-id label)
     "view3d-id" (visual-id view)))
  (define spatial-point
    (target->world-point label view))
  (define anchor
    (project-spatial-point-to-view3d-world view spatial-point))
  ;; `offset` is authored in screen pixels but Animate's vec2 coordinate
  ;; convention remains y-up. It is consequently added after the view's outer
  ;; transform, rather than being rotated or scaled with the 3D viewport.
  (define screen-offset
    (vec2 (/ (vec2-x (projected-label-value-offset label))
             (camera-scale outer-camera))
          (/ (vec2-y (projected-label-value-offset label))
             (camera-scale outer-camera))))
  (define outer (projected-label-value-outer-transform label))
  (define local (visual-transform (projected-label-value-template label)))
  (define resulting-transform
    (make-affine-transform
     #:translation
     (vec2+
      (vec2+ anchor screen-offset)
      (vec2+
       (affine-transform-translation outer)
       (affine-transform-apply-vector
        outer
        (affine-transform-translation local))))
     #:rotation
     (+ (affine-transform-rotation outer)
        (affine-transform-rotation local))
     #:scale
     (vec2* (affine-transform-scale outer)
            (affine-transform-scale local))))
  (define concrete
    (visual-with-transform (projected-label-value-template label)
                           resulting-transform))
  (define opaque
    (visual-with-opacity
     concrete
     (* (projected-label-value-outer-opacity label)
        (label-occlusion-factor label view outer-camera spatial-point)
        (visual-opacity concrete))))
  (unless (and (visual? opaque)
               (not (projected-label? opaque))
               (eq? (visual-id opaque) (visual-id label)))
    (raise-arguments-error
     'resolve-projected-label
     "concrete projected-label output preserving its Visual ID"
     "label-id" (visual-id label)
     "result" opaque))
  opaque)

;; The viewport itself is rendered first in the ordinary scene drawing order.
;; Recreating its opaque depth target here is intentionally conservative: a
;; label is never hidden by transparent geometry, whose lack of a stable depth
;; write is central to the transparency contract.
(define (label-occlusion-factor label view outer-camera world-point)
  (case (projected-label-value-occlusion label)
    [(always-visible) 1]
    [else
     (define width (view-pixel-width view outer-camera))
     (define height (view-pixel-height view outer-camera))
     (define camera3 (view3d-camera view))
     (define projected (camera3d-project camera3 world-point #:aspect (/ width height)))
     (cond [(not projected) 1]
           [else
            (define x (min (sub1 width)
                           (max 0 (inexact->exact (floor (* width (/ (+ (vec2-x projected) 1) 2)))))))
            (define y (min (sub1 height)
                           (max 0 (inexact->exact (floor (* height (/ (- 1 (vec2-y projected)) 2)))))))
            (define target
              (software-render-result-target (render-view3d-opaque view width height)))
            (define index (+ x (* y width)))
            (define occluded?
              (< (+ (vector-ref (raster-target3d-depth-values target) index) 1e-6)
                 (camera3d-view-depth camera3 world-point)))
            (if occluded?
                (if (eq? (projected-label-value-occlusion label) 'hide) 0 1/4)
                1)])]))

(define (view-pixel-width view outer-camera)
  (max 1 (inexact->exact
          (round (* (camera-length->pixels outer-camera (view3d-width view))
                    (vec2-x (visual-scale view)))))))

(define (view-pixel-height view outer-camera)
  (max 1 (inexact->exact
          (round (* (camera-length->pixels outer-camera (view3d-height view))
                    (vec2-y (visual-scale view)))))))

(define (target->world-point label view)
  (define target (projected-label-value-target label))
  (cond [(vec3? target) target]
        [else
         (define path (normalize-spatial-target (visual-id view) target))
         (affine3-translation (view3d-spatial-world-transform view path))]))

(define (normalize-spatial-target view-id target)
  (if (eq? (car target) view-id)
      target
      (cons view-id target)))

(define (check-target who target)
  (unless (or (vec3? target) (spatial-path? target))
    (raise-argument-error who "(or/c vec3? spatial-path?)" target)))
