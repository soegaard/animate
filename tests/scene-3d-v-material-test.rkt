#lang racket/base

;;; SCENE-3D-V1: material lighting, emission, and complete propagation

(require racket/list
         racket/runtime-path
         rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../private/color-style.rkt"
         "../private/geometry.rkt"
         "../private/3d/light3d.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/raster-triangle3d.rkt"
         "../private/3d/spatial-inspection.rkt")

(define-runtime-path opengl-module-path "../3d/opengl.rkt")

(define (triangle color)
  (vector (raster-vertex3d (vec2 -1 -1) 1 (vec3 0 0 1) color #f)
          (raster-vertex3d (vec2 1 -1) 1 (vec3 0 0 1) color #f)
          (raster-vertex3d (vec2 0 1) 1 (vec3 0 0 1) color #f)))

(define (pixel-rgb target)
  (define bytes (raster-target3d-color-bytes target))
  (define index (* 4 9))
  (vector (bytes-ref bytes (add1 index))
          (bytes-ref bytes (+ index 2))
          (bytes-ref bytes (+ index 3))))

(define (render-one material lights)
  (define target (make-raster-target3d 4 4 "black"))
  (raster-triangle3d! target (triangle (material3d-color material)) material lights 0)
  (pixel-rgb target))

(module+ test
  (define phong
    (material3d #:color "black" #:shading 'flat #:lighting 'blinn-phong
                #:ambient 0 #:diffuse 0 #:specular 1 #:specular-color "red"
                #:roughness 1))
  (define lambert
    (material3d #:color "black" #:shading 'flat #:lighting 'lambert
                #:ambient 0 #:diffuse 0 #:specular 1 #:specular-color "red"
                #:roughness 1))
  (define head-on-light (list (directional-light3d (vec3 0 0 -1))))
  ;; A Blinn--Phong highlight uses the derived exponent, whereas Lambert
  ;; deliberately ignores all specular material fields.
  (check-equal? (pixel-rgb (let ([target (make-raster-target3d 4 4 "black")]) target))
                (vector 0 0 0))
  (check-equal? (render-one phong head-on-light) (vector 255 0 0))
  (check-equal? (render-one lambert head-on-light) (vector 0 0 0))

  ;; Unlit keeps its base colour and adds the material emission independently
  ;; of scene lighting. Black base makes the selected emission rule unambiguous.
  (define glowing
    (material3d #:color "black" #:shading 'unlit
                #:emission "#00ff00" #:emission-strength 1))
  (check-equal? (render-one glowing '()) (vector 0 255 0))

  (check-equal? (material3d-specular-exponent (material3d #:roughness 1)) 1)
  (check-equal? (material3d-specular-exponent (material3d #:roughness 1/2)) 6)
  (check-equal? (material3d-specular-exponent (material3d #:roughness 1/4)) 30)
  (check-exn exn:fail? (lambda () (material3d #:roughness 0)))
  (check-exn exn:fail? (lambda () (material3d #:roughness 2)))
  (check-exn exn:fail? (lambda () (material3d #:emission-strength -1)))

  (define authored
    (material3d #:color "#000080" #:lighting 'blinn-phong #:roughness 1/2
                #:emission "gold" #:emission-strength 1/3
                #:casts-shadow? #f #:receives-shadow? #t))
  (define updated
    (material3d-with-shadow-policy
     (material3d-with-emission (material3d-with-color authored "#008080") "tomato"
                               #:strength 1/2)
     #:receives-shadow? #f))
  (check-equal? (material3d-lighting updated) 'blinn-phong)
  (check-equal? (material3d-roughness updated) 1/2)
  (check-false (material3d-casts-shadow? updated))
  (check-false (material3d-receives-shadow? updated))
  (check-equal? (material3d-emission-strength updated) 1/2)
  (define wireframe (mesh3d-wireframe (cube3d 1 #:id 'cube #:material authored)))
  (define copied (mesh3d-material wireframe))
  (check-equal? (material3d-emission copied) (material3d-emission authored))
  (check-equal? (material3d-casts-shadow? copied) (material3d-casts-shadow? authored))

  ;; Inspector records retain the exact derived exponent, without invoking a
  ;; renderer or reading backend state.
  (define inspected-view
    (view3d (list (cube3d 1 #:id 'cube #:material authored))
            #:id 'world #:width 4 #:height 3))
  (define cube-inspection
    (for/first ([entry (in-list (view3d-spatial-inspections inspected-view))]
                #:when (equal? (last (spatial-inspection-path entry)) 'cube))
    entry))
  (check-equal? (hash-ref (spatial-inspection-metadata cube-inspection)
                          'material-specular-exponent)
                6))

;; The normal test suite stays headless. This opt-in GRacket lane compiles the
;; amended GLSL programs and renders a material that exercises both the new
;; Blinn--Phong and emission uniforms.
(module+ test
  (when (equal? (getenv "ANIMATE_OPENGL_INTEGRATION") "1")
    (define make-opengl-renderer
      (dynamic-require opengl-module-path 'opengl-renderer3d))
    (define make-opengl-spec
      (dynamic-require opengl-module-path 'opengl-renderer3d-spec))
    (define renderer
      (make-opengl-renderer
       (make-opengl-spec #:samples 1 #:cache-megabytes 16 #:fallback 'error)))
    (dynamic-wind
     void
     (lambda ()
       (define material
         (material3d #:color "#101010" #:shading 'smooth #:lighting 'blinn-phong
                     #:ambient 0 #:diffuse 0 #:specular 1 #:specular-color "white"
                     #:roughness 1/2 #:emission "#100000" #:emission-strength 1/4))
       (define request
         (view3d->render3d-request
          (view3d (list (sphere3d 1 #:id 'sphere #:material material))
                  #:id 'world #:width 4 #:height 3 #:render-mode 'opaque
                  #:lights (list (directional-light3d (vec3 0 0 -1))))
          48 36))
       (define result
         (renderer3d-render renderer (renderer3d-prepare renderer request) request))
       (check-equal? (renderer3d-render-result-width result) 48)
       (check-equal? (renderer3d-render-result-height result) 36)
       (check-true
        (for/or ([channel (in-bytes (renderer3d-render-result-argb-bytes result))])
          (positive? channel))))
     (lambda () (renderer3d-release renderer)))))
