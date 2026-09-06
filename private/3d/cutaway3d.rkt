#lang racket/base

;;;
;;; Fixed-Structure Semantic Cutaway Assemblies
;;;

(require "clipping3d.rkt"
         "cap-style3d.rkt"
         "mesh3d.rkt"
         "mesh-cut3d.rkt"
         "section-settings3d.rkt"
         "spatial-group.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide cutaway3d)

; cutaway3d : mesh3d? plane3? ... -> group3d?
;; Makes kept geometry, optional removed geometry, and caps explicit siblings.
;; No frame history exists: an animated author can directly rebuild this value
;; from the current plane or prepare a finite sample table outside the model.
(define (cutaway3d mesh plane-or-clip
                   #:caps [caps default-cap-style3d]
                   #:show-removed? [show-removed? #f]
                   #:removed-offset [removed-offset origin3]
                   #:settings [settings (section3d-settings-for-bounds (mesh3d-local-bounds mesh))]
                   #:id [id (string->symbol (format "~a-cutaway" (spatial-id mesh)))])
  (unless (mesh3d? mesh) (raise-argument-error 'cutaway3d "mesh3d?" mesh))
  (unless (or (not caps) (cap-style3d? caps)) (raise-argument-error 'cutaway3d "#f or cap-style3d?" caps))
  (unless (boolean? show-removed?) (raise-argument-error 'cutaway3d "boolean?" show-removed?))
  (unless (vec3? removed-offset) (raise-argument-error 'cutaway3d "vec3?" removed-offset))
  (unless (symbol? id) (raise-argument-error 'cutaway3d "symbol?" id))
  (define result (cut-mesh3d mesh plane-or-clip #:settings settings #:cap caps
                             #:positive-id 'kept #:negative-id 'removed))
  (define removed
    (if show-removed?
        (spatial-with-position (mesh-cut3d-result-negative result)
                               (vec3+ (spatial-position (mesh-cut3d-result-negative result)) removed-offset))
        #f))
  (group3d
   (append (list (mesh-cut3d-result-positive result))
           (if (mesh-cut3d-result-positive-cap result) (list (mesh-cut3d-result-positive-cap result)) '())
           (if removed (list removed) '())
           (if (and removed (mesh-cut3d-result-negative-cap result))
               (list (spatial-with-position
                      (mesh-cut3d-result-negative-cap result)
                      (vec3+ (spatial-position (mesh-cut3d-result-negative-cap result)) removed-offset)))
               '()))
   #:id id))
