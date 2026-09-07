#lang racket/base

(require rackunit
         "../3d.rkt")

(module+ test
  (define near
    (mesh3d #:id 'near
            #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
            #:triangles (vector (vector 0 1 2))
            #:edges (vector (vector 0 1) (vector 1 2) (vector 2 0))
            #:vertex-ids '#(west east peak)
            #:edge-ids '#(base right-side left-side)
            #:face-ids '#(front)))
  (define far
    (mesh3d #:id 'far
            #:vertices (vector (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 0 1 -1))
            #:triangles (vector (vector 0 1 2))))
  (define world
    (view3d (list far near) #:id 'world #:width 4 #:height 4 #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 4) #:look-at origin3)))
  (define hit (view3d-pixel-pick world 100 100 #:width 200 #:height 200))
  (check-true (spatial-pick? hit))
  (check-equal? (spatial-pick-path hit) '(world near))
  (check-equal? (spatial-pick-triangle-index hit) 0)
  (check-= (vec3-z (spatial-pick-point hit)) 0 1e-12)
  (check-= (spatial-pick-distance hit) 4 1e-12)
  (check-eq? (spatial-inspection-kind (spatial-pick-inspection hit)) 'mesh)
  (check-equal? (length (hash-ref (spatial-pick-metadata hit) 'world-triangle)) 3)
  (check-true
   (andmap vec3? (hash-ref (spatial-pick-metadata hit) 'world-triangle)))
  (define pick-metadata (spatial-pick-metadata hit))
  (check-equal? (hash-ref pick-metadata 'semantic-vertex-ids)
                '#(west east peak))
  (check-equal? (sort (vector->list (hash-ref pick-metadata 'semantic-edge-ids))
                      symbol<?)
                '(base left-side right-side))
  (check-eq? (hash-ref pick-metadata 'render-triangle-id) 'front)
  (check-eq? (hash-ref pick-metadata 'semantic-polygonal-face-id) 'front)
  (check-eq? (hash-ref pick-metadata 'polygonal-face-policy) 'render-triangle)
  ;; A triangle hit has no invented exact lower-dimensional hit. These two
  ;; stable IDs instead classify the nearest authored vertex and opposite edge
  ;; from the barycentric coordinates, with source order breaking ties.
  (check-eq? (hash-ref pick-metadata 'nearest-semantic-vertex-id) 'peak)
  (check-eq? (hash-ref pick-metadata 'nearest-semantic-edge-id) 'right-side)
  (check-equal? (hash-ref pick-metadata 'connected-component) 0)
  (check-equal? (hash-ref pick-metadata 'boundary-components) '#(0))
  (define topology (hash-ref pick-metadata 'topology))
  (check-equal? (hash-ref topology 'euler-characteristic) 1)
  (check-equal? (hash-ref topology 'boundary-count) 1)
  (check-true (hash-ref topology 'manifold?))
  (check-true (hash-ref topology 'orientable?))
  (check-equal? (hash-ref (spatial-inspection-metadata
                            (spatial-pick-inspection hit))
                          'topology)
                topology)
  ;; The preview-only topology overlay derives all its world coordinates after
  ;; a selection. It is deliberately separate from immutable scene children.
  (define children-before-overlay (view3d-children world))
  (define overlay (spatial-pick-topology-overlay3d world hit))
  (check-true (spatial-topology-overlay3d? overlay))
  (check-equal? (spatial-topology-overlay3d-vertex overlay) (vec3 0 1 0))
  (check-equal? (spatial-topology-overlay3d-edge overlay)
                (vector-immutable (vec3 1 -1 0) (vec3 0 1 0)))
  (check-equal? (vector-length (spatial-topology-overlay3d-face overlay)) 3)
  (check-equal? (vector-length (spatial-topology-overlay3d-component-faces overlay)) 1)
  (check-equal? (vector-length (spatial-topology-overlay3d-boundary-segments overlay)) 3)
  (check-equal? (vector-length (spatial-topology-overlay3d-halfedges overlay)) 3)
  (check-equal? (view3d-children world) children-before-overlay)
  (check-false (view3d-pixel-pick world 0 0 #:width 200 #:height 200)))
