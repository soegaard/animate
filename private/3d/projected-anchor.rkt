#lang racket/base

;;;
;;; Spatial-to-Viewport Anchor Projection
;;;

;; Pure helpers for the boundary between a 3D camera and an ordinary 2D
;; view3d rectangle.  They contain no Pict or scene-state dependency, which
;; makes the projection policy testable without a renderer.

(require "../affine-transform.rkt"
         "../geometry.rkt"
         "../visual-model.rkt"
         "camera3d.rkt"
         "projection3d.rkt"
         "vec3.rkt"
         "view3d-visual.rkt")

(provide view3d-projection-aspect
         project-spatial-point-to-view3d-local
         project-spatial-point-to-view3d-world)

; view3d-projection-aspect : view3d? -> positive-real?
;; Returns the screen aspect of the viewport after its ordinary 2D scale.
(define (view3d-projection-aspect view)
  (unless (view3d? view)
    (raise-argument-error 'view3d-projection-aspect "view3d?" view))
  (define scale (affine-transform-scale (visual-transform view)))
  (/ (* (view3d-width view) (vec2-x scale))
     (* (view3d-height view) (vec2-y scale))))

; project-spatial-point-to-view3d-local : view3d? vec3? -> vec2?
;; Projects a point into the local coordinates of a viewport.  The current
;; Stage E policy is ``always visible'': no depth-buffer test is performed and
;; a point beyond the camera frustum is clamped to the viewport edge rather
;; than disappearing with the mesh behind an occluder or clipping plane.
(define (project-spatial-point-to-view3d-local view point)
  (unless (view3d? view)
    (raise-argument-error
     'project-spatial-point-to-view3d-local "view3d?" view))
  (unless (vec3? point)
    (raise-argument-error
     'project-spatial-point-to-view3d-local "vec3?" point))
  (define normalized
    (visible-normalized-projection (view3d-camera view) point
                                  (view3d-projection-aspect view)))
  (vec2 (* (/ (view3d-width view) 2) (vec2-x normalized))
        (* (/ (view3d-height view) 2) (vec2-y normalized))))

; project-spatial-point-to-view3d-world : view3d? vec3? -> vec2?
;; Projects a point and maps the result through the viewport's ordinary 2D
;; transform, exactly matching where view3d's Pict is placed in a scene.
(define (project-spatial-point-to-view3d-world view point)
  (affine-transform-apply-point
   (visual-transform view)
   (project-spatial-point-to-view3d-local view point)))

(define (visible-normalized-projection camera point aspect)
  (define ordinary (camera3d-project camera point #:aspect aspect))
  (cond [ordinary (clamp-normalized ordinary)]
        [else
         ;; `camera3d-project` rejects a point behind near/far depth.  Project
         ;; its camera-space direction at the nearest legal depth and clamp it
         ;; to the rectangle.  This produces a stable edge anchor rather than
         ;; a label that flickers off as its target crosses a clipping plane.
         (define view-point (camera3d-world->view camera point))
         (define raw-depth (- (vec3-z view-point)))
         (define legal-depth
           (cond [(<= raw-depth 0) (camera3d-near camera)]
                 [(< raw-depth (camera3d-near camera)) (camera3d-near camera)]
                 [(> raw-depth (camera3d-far camera)) (camera3d-far camera)]
                 [else raw-depth]))
         (clamp-normalized
          (projection3d-project-view
           (camera3d-projection camera)
           (vec3 (vec3-x view-point)
                 (vec3-y view-point)
                 (- legal-depth))
           aspect))]))

(define (clamp-normalized point)
  (vec2 (clamp -1 (vec2-x point) 1)
        (clamp -1 (vec2-y point) 1)))

(define (clamp low value high)
  (min high (max low value)))
