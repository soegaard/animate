#lang racket/base

;;; SCENE-3D-N: camera-independent compilation and retained geometry cache

(require rackunit
         "../3d.rkt"
         "../3d/render.rkt")

(define material (material3d #:color "steelblue" #:shading 'flat))

(define cube-a (cube3d 2 #:id 'left #:material material))
(define cube-b
  (spatial-with-position
   (cube3d 2 #:id 'right
           #:material (material3d #:color "tomato" #:shading 'flat))
   (vec3 3 0 0)))

(define (world camera children)
  (view3d children #:id 'world #:width 6 #:height 4 #:render-mode 'opaque #:camera camera))

(define camera-a
  (perspective-camera3d #:position (vec3 4 3 5) #:look-at origin3))
(define camera-b
  (perspective-camera3d #:position (vec3 -4 3 5) #:look-at origin3))

(module+ test
  (define first-view (world camera-a (list cube-a cube-b)))
  (define second-view (world camera-b (list cube-a cube-b)))
  (define moved-view
    (world camera-b
           (list (spatial-with-position cube-a (vec3 -1 0 0)) cube-b)))
  (define first-compiled (compile-view3d first-view))
  (define second-compiled (compile-view3d second-view))
  (define moved-compiled (compile-view3d moved-view))
  (check-equal? (vector-length (compiled-view3d-geometries first-compiled)) 1)
  (check-equal? (vector-length (compiled-view3d-instances first-compiled)) 2)
  (check-equal? (compiled-view3d-geometries first-compiled)
                (compiled-view3d-geometries second-compiled))
  (check-equal? (compiled-view3d-geometries first-compiled)
                (compiled-view3d-geometries moved-compiled))
  (check-not-equal? (compiled-view3d-instances first-compiled)
                    (compiled-view3d-instances moved-compiled))

  ;; Placement and material intentionally live on instances. Per-vertex
  ;; geometry attributes do not: changing a colour creates a new resource.
  (define differently-coloured
    (mesh3d #:id 'coloured
            #:vertices (mesh3d-vertices cube-a)
            #:triangles (mesh3d-triangles cube-a)
            #:colors (make-vector (vector-length (mesh3d-vertices cube-a)) "tomato")))
  (define colour-view (world camera-a (list cube-a differently-coloured)))
  (check-equal? (vector-length
                 (compiled-view3d-geometries (compile-view3d colour-view)))
                2)

  (define renderer (retained-software-renderer3d #:capacity 4))
  (define (render request)
    (renderer3d-render renderer (renderer3d-prepare renderer request) request))
  (renderer3d-statistics-reset! renderer)
  (define first-request
    (render3d-request first-compiled (view3d->frame3d-spec first-view 96 64) #f))
  (define orbit-request
    (render3d-request second-compiled (view3d->frame3d-spec second-view 96 64) #f))
  (define moving-request
    (render3d-request moved-compiled (view3d->frame3d-spec moved-view 96 64) #f))
  (define _first-result (render first-request))
  (define _orbit-result (render orbit-request))
  (define _moving-result (render moving-request))
  (define statistics (renderer3d-statistics-snapshot renderer))
  ;; The first request uploads one shared geometry. Camera and instance changes
  ;; create fresh frame preparation but retain that same geometry resource.
  (check-equal? (renderer3d-statistics-geometry-cache-misses statistics) 1)
  (check-equal? (renderer3d-statistics-geometry-cache-hits statistics) 2)
  (check-equal? (retained-software-renderer3d-cache-misses renderer) 3)
  (check-true (positive? (renderer3d-statistics-source-triangle-count statistics)))
  (check-true (positive? (renderer3d-statistics-raster-triangle-count statistics))))
