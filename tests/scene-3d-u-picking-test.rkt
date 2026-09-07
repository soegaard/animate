#lang racket/base

;;; SCENE-3D-U8: semantic topology picking and preview-only overlays

(require rackunit
         "../3d.rkt")

(define labelled-cube
  (mesh3d
   #:id 'cube
   #:vertices
   (vector (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 1 1 -1) (vec3 -1 1 -1)
           (vec3 -1 -1 1) (vec3 1 -1 1) (vec3 1 1 1) (vec3 -1 1 1))
   #:triangles
   (vector (vector 4 5 6) (vector 4 6 7) ; front
           (vector 0 2 1) (vector 0 3 2) ; back
           (vector 0 4 7) (vector 0 7 3) ; left
           (vector 1 2 6) (vector 1 6 5) ; right
           (vector 0 1 5) (vector 0 5 4) ; bottom
           (vector 3 7 6) (vector 3 6 2)) ; top
   ;; `mesh3d` derives these exact eighteen source edges in first-encounter
   ;; order, so the semantic labels are neither renderer-generated nor tied to
   ;; camera ordering.
   #:edges
   (vector (vector 4 5) (vector 5 6) (vector 6 4) (vector 6 7)
           (vector 7 4) (vector 0 2) (vector 2 1) (vector 1 0)
           (vector 0 3) (vector 3 2) (vector 0 4) (vector 7 0)
           (vector 7 3) (vector 2 6) (vector 6 1) (vector 1 5)
           (vector 0 5) (vector 6 3))
   #:vertex-ids '#(back-left-bottom back-right-bottom back-right-top back-left-top
                   front-left-bottom front-right-bottom front-right-top front-left-top)
   #:edge-ids '#(front-bottom front-right front-diagonal front-top front-left
                 back-diagonal back-bottom back-right back-left back-top
                 left-bottom left-diagonal left-top right-top right-diagonal
                 right-bottom bottom-diagonal top-diagonal)
   #:face-ids '#(front-lower front-upper back-lower back-upper left-lower left-upper
                 right-lower right-upper bottom-lower bottom-upper top-lower top-upper)))

(define (cube-view camera)
  (view3d (list labelled-cube) #:id 'world #:width 4 #:height 4
          #:render-mode 'opaque #:camera camera))

(module+ test
  (define front-ray (ray3 (vec3 0 -1/2 5) (vec3 0 0 -1)))
  (define initial-view
    (cube-view
     (perspective-camera3d #:position (vec3 0 0 5) #:look-at origin3)))
  (define initial-children (view3d-children initial-view))
  (define initial-pick (view3d-pick initial-view front-ray))
  (check-true (spatial-pick? initial-pick))
  (check-equal? (spatial-pick-path initial-pick) '(world cube))
  (define metadata (spatial-pick-metadata initial-pick))
  (check-eq? (hash-ref metadata 'semantic-polygonal-face-id) 'front-lower)
  (check-eq? (hash-ref metadata 'render-triangle-id) 'front-lower)
  (check-equal? (hash-ref metadata 'polygonal-face-policy) 'render-triangle)
  (check-not-false (member (hash-ref metadata 'nearest-semantic-vertex-id)
                           (vector->list (hash-ref metadata 'semantic-vertex-ids))))
  (check-not-false (member (hash-ref metadata 'nearest-semantic-edge-id)
                           (vector->list (hash-ref metadata 'semantic-edge-ids))))
  (check-equal? (hash-ref metadata 'connected-component) 0)
  (check-equal? (hash-ref metadata 'boundary-components) '#())
  (define topology (hash-ref metadata 'topology))
  (check-equal? (hash-ref topology 'euler-characteristic) 2)
  (check-equal? (hash-ref topology 'boundary-count) 0)
  (check-true (hash-ref topology 'manifold?))
  (check-true (hash-ref topology 'closed?))
  (check-true (hash-ref topology 'orientable?))

  ;; The GUI and a headless author receive one neutral inspection record,
  ;; rather than each decoding the pick's extensible metadata hash themselves.
  (define report (spatial-pick-topology-inspection3d initial-pick))
  (check-true (topology-inspection3d? report))
  (check-equal? (topology-inspection3d-path report) '(world cube))
  (check-equal? (topology-inspection3d-semantic-vertex-ids report)
                (hash-ref metadata 'semantic-vertex-ids))
  (check-equal? (topology-inspection3d-nearest-edge-incident-face-ids report)
                (hash-ref metadata 'nearest-edge-incident-face-ids))

  (define overlay (spatial-pick-topology-overlay3d initial-view initial-pick))
  (check-true (spatial-topology-overlay3d? overlay))
  (check-equal? (vector-length (spatial-topology-overlay3d-face overlay)) 3)
  (check-equal? (vector-length (spatial-topology-overlay3d-component-faces overlay)) 12)
  (check-equal? (vector-length (spatial-topology-overlay3d-boundary-segments overlay)) 0)
  (check-equal? (vector-length (spatial-topology-overlay3d-halfedges overlay)) 3)
  ;; Overlay geometry depends on world mesh geometry, not the active camera.
  (define orbit-view
    (cube-view
     (perspective-camera3d #:position (vec3 4 3 5) #:look-at origin3)))
  (define orbit-pick (view3d-pick orbit-view front-ray))
  (check-equal? (spatial-pick-topology-overlay3d orbit-view orbit-pick) overlay)
  (check-equal? (view3d-children initial-view) initial-children)

  ;; An inspector must expose a nonmanifold condition as data rather than
  ;; create a plausible genus or silently choose one adjacent face.
  (define nonmanifold
    (mesh3d #:id 'nonmanifold
            #:vertices (vector origin3 (vec3 1 0 0) (vec3 0 1 0)
                              (vec3 0 0 1) (vec3 0 -1 0))
            #:triangles (vector (vector 0 1 2) (vector 1 0 3) (vector 0 1 4))))
  (define nonmanifold-view
    (view3d (list nonmanifold) #:id 'nonmanifold-world #:width 4 #:height 4
            #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 5)
                                           #:look-at origin3)))
  (define nonmanifold-inspection
    (view3d-spatial-inspection-at nonmanifold-view '(nonmanifold-world nonmanifold)))
  (define nonmanifold-topology
    (hash-ref (spatial-inspection-metadata nonmanifold-inspection) 'topology))
  (check-false (hash-ref nonmanifold-topology 'manifold?))
  (check-false (mesh3d-genus-report-valid? (hash-ref nonmanifold-topology 'genus)))
  (define marker-view
    (view3d (list (point3d origin3 #:id 'marker
                          #:style (point-style3d #:size 12)))
            #:id 'marker-world #:width 4 #:height 4 #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 4)
                                           #:look-at origin3)))
  (check-false
   (spatial-pick-topology-inspection3d
    (view3d-pixel-pick marker-view 80 80 #:width 160 #:height 160))))
