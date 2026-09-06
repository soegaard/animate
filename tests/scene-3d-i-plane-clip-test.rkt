#lang racket/base

;;; SCENE-3D-I Render Clipping Tests

(require rackunit
         "../3d.rkt"
         "../private/3d/render-command3d.rkt")

(module+ test
  (define source (cube3d 2 #:id 'cube #:color "tomato"))
  (define plane (plane3 origin3 x-axis3))
  (define sliced (slice-mesh3d source plane))

  ;; Geometric slicing returns fresh half-space geometry while retaining the
  ;; original authored transform and material envelope.
  (check-true (positive? (vector-length (mesh3d-triangles sliced))))
  (for ([point (in-vector (mesh3d-vertices sliced))])
    (check-true (>= (vec3-x point) -1e-7)))
  (check-equal? (spatial-id sliced) 'cube)

  ;; Render clipping preserves the original mesh but attaches the local plane
  ;; to draw commands; it consequently has no geometric side effects.
  (define clipped
    (clip3d source (clip-plane3d plane #:keep 'positive) #:id 'positive-half))
  (define world (view3d (list clipped) #:id 'world #:render-mode 'opaque))
  (define command
    (car (spatial-tree->draw-mesh3d-commands world #:root-path '(world))))
  (check-equal? (vector-length (mesh3d-triangles (draw-mesh3d-command-mesh command))) 12)
  (check-equal? (length (draw-mesh3d-command-clip-planes command)) 1)
  (check-equal? (clip-plane3d-keep (car (draw-mesh3d-command-clip-planes command)))
                'positive))
