#lang racket/base

;;; SCENE-3D-C Capability Declaration Tests

(require racket/set
         rackunit
         "../project.rkt"
         "../3d/render.rkt")

(module+ test
  (define spatial
    (renderer3d-capabilities
     (seteq 'opaque-triangles 'perspective 'orthographic 'depth-buffer
            'flat-shading 'smooth-shading 'clipping-planes)
     (hasheq 'maximum-directional-lights 0
             'maximum-point-lights 0
             'maximum-spot-lights 0
             'maximum-shadow-lights 0
             'maximum-clip-planes 8
             'maximum-shadow-map-size 0
             'maximum-samples 1)
     #hasheq()))
  (define capabilities
    (renderer-capabilities #t #t #t #t #f #t #t #t spatial))
  (check-true (renderer3d-supports? spatial 'opaque-triangles))
  (check-true (renderer3d-supports? spatial 'depth-buffer))
  (check-false (renderer3d-supports? spatial 'transparency))
  (check-eq? (renderer-capabilities-three-dimensional capabilities) spatial))
