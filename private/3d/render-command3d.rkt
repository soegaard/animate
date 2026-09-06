#lang racket/base

;;; Stable Spatial Draw Commands

(require racket/list
         "affine3.rkt"
         "affine-map3d-visual.rkt"
         "clipping3d.rkt"
         "curve3d.rkt"
         "linear3.rkt"
         "mesh3d.rkt"
         "parametric-surface3d.rkt"
         "spatial-group.rkt"
         "spatial-visual.rkt"
         "transform3.rkt")

(provide (struct-out draw-mesh3d-command)
         spatial-tree->draw-mesh3d-commands)

;; The command stream is the ordered boundary between the immutable spatial
;; scene graph and every renderer.  `drawing-index` follows declared child and
;; triangle order, never hash traversal order.
(struct draw-mesh3d-command
  (path world-transform normal-transform mesh material opacity clip-planes drawing-index)
  #:transparent)

; spatial-tree->draw-mesh3d-commands : spatial-container?
;                                       [#:root-path (listof symbol?)]
;                                       -> (listof draw-mesh3d-command?)
(define (spatial-tree->draw-mesh3d-commands root #:root-path [root-path '()])
  (unless (spatial-container? root)
    (raise-argument-error 'spatial-tree->draw-mesh3d-commands
                          "spatial-container?" root))
  (unless (and (list? root-path) (andmap symbol? root-path))
    (raise-argument-error 'spatial-tree->draw-mesh3d-commands
                          "(listof symbol?)" root-path))
  (define-values (reversed _next-index)
    (flatten-container root identity-affine3 1 root-path '() 0 '()))
  (reverse reversed))

(define (flatten-container container parent-transform parent-opacity parent-path parent-clips
                           next-index reversed)
  (for/fold ([reversed reversed] [next-index next-index])
            ([entry (in-list (spatial-child-entries container))])
    (flatten-object (spatial-child-visual entry)
                    parent-transform
                    parent-opacity
                    (append parent-path (list (spatial-id (spatial-child-visual entry))))
                    parent-clips
                    next-index
                    reversed)))

(define (flatten-object object parent-transform parent-opacity path parent-clips next-index reversed)
  (define opacity (* parent-opacity (spatial-opacity object)))
  (cond
    [(zero? opacity)
     (values reversed next-index)]
    ;; A semantic affine wrapper owns a full map, including shears that do not
    ;; fit in transform3. Its public transform is only a proxy for position
    ;; tooling and must not be applied a second time by render traversal.
    [(affine-map3d? object)
     (flatten-object (affine-map3d-content object)
                     (affine3-compose parent-transform (affine-map3d-map object))
                     opacity path parent-clips next-index reversed)]
    [else
     (define world-transform
       (affine3-compose parent-transform
                        (transform3->affine3 (spatial-transform object))))
     (cond
       [(or (mesh3d? object) (curve3d? object) (surface3d? object))
        (define mesh
          (cond [(curve3d? object) (curve3d->mesh3d object)]
                [(surface3d? object) (surface3d->mesh3d object)]
                [else object]))
        (values
         (cons (draw-mesh3d-command
                path
                world-transform
                ;; An affine map is permitted to be singular: flattening a
                ;; solid into a plane must produce degenerate geometry, not an
                ;; unrelated renderer exception.  There is no mathematically
                ;; defined inverse-transpose normal map in that case.  Keep
                ;; the authored normal as a deterministic shading fallback;
                ;; any collapsed triangle still has zero raster area.
                (normal-transform-or-authored world-transform)
                mesh
                (mesh3d-material mesh)
                opacity
                parent-clips
                next-index)
               reversed)
         (add1 next-index))]
       [(clip3d? object)
        (flatten-container
         object world-transform opacity path
         (append parent-clips
                 (list (clip-plane3d-world (clip3d-plane object) world-transform)))
         next-index reversed)]
       [(spatial-container? object)
        (flatten-container object world-transform opacity path parent-clips next-index reversed)]
       [else
        (values reversed next-index)])]))

(define (normal-transform-or-authored world-transform)
  (with-handlers ([exn:fail? (lambda (_exception) identity-linear3)])
    (affine3-normal-transform world-transform)))
