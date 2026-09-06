#lang racket/base

;;;
;;; Explicit Numerical Policy for Mesh Sections
;;;

(require "../geometry.rkt"
         "bounds3.rkt"
         "vec3.rkt")

(provide (struct-out section3d-settings)
         default-section3d-settings
         section3d-settings-for-bounds)

(struct section3d-settings
  (distance-tolerance weld-tolerance coplanar-policy tangent-policy validation)
  #:transparent
  #:guard
  (lambda (distance-tolerance weld-tolerance coplanar-policy tangent-policy validation who)
    (unless (and (finite-real? distance-tolerance) (positive? distance-tolerance))
      (raise-argument-error who "positive finite distance tolerance" distance-tolerance))
    (unless (and (finite-real? weld-tolerance) (positive? weld-tolerance))
      (raise-argument-error who "positive finite weld tolerance" weld-tolerance))
    (unless (memq coplanar-policy '(ignore boundary include error))
      (raise-argument-error who "coplanar policy: ignore, boundary, include, or error"
                            coplanar-policy))
    (unless (memq tangent-policy '(ignore point error))
      (raise-argument-error who "tangent policy: ignore, point, or error" tangent-policy))
    (unless (boolean? validation)
      (raise-argument-error who "boolean? validation" validation))
    (values distance-tolerance weld-tolerance coplanar-policy tangent-policy validation)))

(define default-section3d-settings
  (section3d-settings 1e-8 1e-7 'boundary 'point #t))

; section3d-settings-for-bounds : aabb3? -> section3d-settings?
;; Uses an input-scale-aware tolerance instead of a process-global epsilon.
(define (section3d-settings-for-bounds bounds)
  (unless (aabb3? bounds) (raise-argument-error 'section3d-settings-for-bounds "aabb3?" bounds))
  (define size (aabb3-size bounds))
  (define scale (max 1 (abs (vec3-x size)) (abs (vec3-y size)) (abs (vec3-z size))))
  (define distance (* scale 1e-9))
  (section3d-settings distance (* 8 distance) 'boundary 'point #t))
