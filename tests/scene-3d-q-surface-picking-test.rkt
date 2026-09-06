#lang racket/base

;;; SCENE-3D-Q: exact surface picks retain immutable source provenance.

(require rackunit
         "../3d.rkt"
         "../private/3d/affine-map3d-visual.rkt")

(module+ test
  (define patch
    (adaptive-parametric-surface3d
     (lambda (u v) (vec3 u v 0))
     #:u-range '(-1 1) #:v-range '(-1 1) #:id 'patch
     #:minimum-depth 1 #:maximum-depth 3))
  (define patch-view
    (view3d (list patch) #:id 'world #:width 4 #:height 4 #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 4)
                                           #:look-at origin3)))
  (define patch-hit
    (view3d-surface-pick patch-view
                         (camera3d-pixel-ray (view3d-camera patch-view) 100 100
                                             #:width 200 #:height 200)))
  (check-true (surface-pick3d? patch-hit))
  (check-eq? (surface-pick3d-surface-kind patch-hit) 'adaptive-parametric)
  (check-true (spatial-pick? (surface-pick3d-spatial-pick patch-hit)))
  (check-true (hash? (surface-pick3d-source-cell patch-hit)))
  (check-true (vec3? (surface-pick3d-interpolated-normal patch-hit)))
  (define patch-parameter (surface-pick3d-parameter patch-hit))
  (check-true (vector? patch-parameter))
  (check-= (vector-ref patch-parameter 0) 0 1e-10)
  (check-= (vector-ref patch-parameter 1) 0 1e-10)
  ;; An affine wrapper has no extra path component; surface provenance must
  ;; follow the same transparent path traversal as rendering.
  (define mapped-patch-view
    (view3d (list (affine-map3d patch identity-affine3))
            #:id 'mapped-world #:width 4 #:height 4 #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 4)
                                           #:look-at origin3)))
  (check-true
   (surface-pick3d?
    (view3d-surface-pick
     mapped-patch-view
     (camera3d-pixel-ray (view3d-camera mapped-patch-view) 100 100
                         #:width 200 #:height 200))))
  (define patch-inspection
    (view3d-spatial-inspection-at patch-view '(world patch)))
  (check-eq? (hash-ref (spatial-inspection-metadata patch-inspection) 'surface-kind)
             'adaptive-parametric)
  (check-true
   (vector? (hash-ref (spatial-inspection-metadata patch-inspection)
                      'surface-topology-key)))

  (define implicit
    (implicit-surface3d
     (lambda (point)
       (- (+ (* (vec3-x point) (vec3-x point))
             (* (vec3-y point) (vec3-y point))
             (* (vec3-z point) (vec3-z point)))
          1))
     #:id 'implicit #:resolution 10))
  (define implicit-view
    (view3d (list implicit) #:id 'implicit-world #:width 4 #:height 4 #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 4)
                                           #:look-at origin3)))
  (define implicit-hit
    (view3d-surface-pick implicit-view
                         (camera3d-pixel-ray (view3d-camera implicit-view) 100 100
                                             #:width 200 #:height 200)))
  (check-true (surface-pick3d? implicit-hit))
  (check-eq? (surface-pick3d-surface-kind implicit-hit) 'implicit)
  (check-false (surface-pick3d-parameter implicit-hit))
  (check-equal? (hash-ref (surface-pick3d-source-cell implicit-hit) 'kind)
                'implicit-tetrahedron)
  (check-false
   (view3d-surface-pick patch-view
                        (camera3d-pixel-ray (view3d-camera patch-view) 0 0
                                            #:width 200 #:height 200))))
