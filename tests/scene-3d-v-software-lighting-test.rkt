#lang racket/base

;;; SCENE-3D-V5: analytic finite-light reference-raster tests

(require (only-in racket/math pi)
         rackunit
         "../3d.rkt"
         "../private/geometry.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/raster-triangle3d.rkt"
         "../private/3d/software-renderer3d.rkt")

(define white-lambert
  (material3d #:color "white" #:shading 'flat #:lighting 'lambert
              #:ambient 0 #:diffuse 1 #:specular 0))

(define red-phong
  (material3d #:color "black" #:shading 'flat #:lighting 'blinn-phong
              #:ambient 0 #:diffuse 0 #:specular 1 #:specular-color "red"
              #:roughness 1))

;; Direct raster triangles deliberately permit a separately supplied
;; camera-space position.  This makes the expected point-light distance and
;; spot angle analytic while retaining the ordinary pixel-centre pipeline.
(define (test-triangle material normal position #:back? [back? #f])
  (define coordinates
    (if back?
        (vector (vec2 -1 -1) (vec2 0 1) (vec2 1 -1))
        (vector (vec2 -1 -1) (vec2 1 -1) (vec2 0 1))))
  (for/vector ([coordinate (in-vector coordinates)])
    (raster-vertex3d coordinate 1 normal (material3d-color material) #f
                     #:view-position position)))

(define (rgb-at target [x 1] [y 2])
  (define bytes (raster-target3d-color-bytes target))
  (define index (* 4 (+ x (* y (raster-target3d-width target)))))
  (vector (bytes-ref bytes (add1 index))
          (bytes-ref bytes (+ index 2))
          (bytes-ref bytes (+ index 3))))

(define (render-direct material lights normal position #:back? [back? #f])
  (define target (make-raster-target3d 4 4 "black"))
  (raster-triangle3d!
   target (test-triangle material normal position #:back? back?) material lights 0)
  (rgb-at target))

(module+ test
  ;; A point source uses the named attenuation at the perspective-correct
  ;; fragment position. The far sample is exactly 1/4 of the near linear
  ;; energy, which sRGB-encodes to approximately 137 rather than 64.
  (define inverse (inverse-square-attenuation3d #:reference-distance 1))
  (define near
    (render-direct white-lambert
                   (list (point-light3d origin3 #:attenuation inverse))
                   z-axis3 (vec3 0 0 -1)))
  (define far
    (render-direct white-lambert
                   (list (point-light3d (vec3 0 0 1) #:attenuation inverse))
                   z-axis3 (vec3 0 0 -1)))
  (check-equal? near (vector 255 255 255))
  (check-true (<= 135 (vector-ref far 0) 139))
  (check-equal? (vector-ref far 0) (vector-ref far 1))
  (check-equal? (vector-ref far 1) (vector-ref far 2))
  (check-equal?
   (render-direct white-lambert
                  (list (point-light3d (vec3 0 0 3)
                                       #:attenuation (constant-attenuation3d)
                                       #:range 3/2))
                  z-axis3 (vec3 0 0 -1))
   (vector 0 0 0))

  ;; The spot direction is outward from the light.  Its centre is fully lit,
  ;; the pi/4 sample lies halfway through the smoothstep cone, and an outer
  ;; sample contributes nothing.
  (define spot
    (spot-light3d origin3 (vec3 0 0 -1)
                  #:inner-angle 0 #:outer-angle (/ pi 2)
                  #:attenuation (constant-attenuation3d)))
  (check-equal?
   (render-direct white-lambert (list spot) z-axis3 (vec3 0 0 -1))
   (vector 255 255 255))
  (define diagonal-position (vec3 1 0 -1))
  (define diagonal-normal (vec3-normalize (vec3 -1 0 1)))
  (define transition
    (render-direct white-lambert (list spot) diagonal-normal diagonal-position))
  (check-true (<= 186 (vector-ref transition 0) 190))
  (define outer-position (vec3 0 0 1))
  (define outer-normal (vec3 0 0 -1))
  (check-equal?
   (render-direct white-lambert (list spot) outer-normal outer-position)
   (vector 0 0 0))

  ;; Finite lights feed the same Blinn--Phong term as directional lights.
  ;; With the source at the camera, view, light, and normal all coincide.
  (check-equal?
   (render-direct red-phong
                  (list (point-light3d origin3 #:attenuation (constant-attenuation3d)))
                  z-axis3 (vec3 0 0 -1))
   (vector 255 0 0))

  ;; A clockwise back face is culled when single-sided and gets its outward
  ;; normal flipped toward the viewer when the material explicitly opts into
  ;; double-sided rendering.
  (define double-sided
    (material3d #:color "white" #:shading 'flat #:lighting 'lambert
                #:ambient 0 #:diffuse 1 #:specular 0 #:double-sided? #t))
  (check-equal?
   (render-direct white-lambert
                  (list (directional-light3d (vec3 0 0 -1)))
                  (vec3 0 0 -1) (vec3 0 0 -1) #:back? #t)
   (vector 0 0 0))
  (check-equal?
   (render-direct double-sided
                  (list (directional-light3d (vec3 0 0 -1)))
                  (vec3 0 0 -1) (vec3 0 0 -1) #:back? #t)
   (vector 255 255 255))

  ;; Preparation converts a world-space point source to the camera frame. A
  ;; source at the camera is three world units from this triangle; with an
  ;; inverse-square reference distance of one its centre pixel is about 1/9
  ;; linear white, not the 1/36 result of treating world data as view data.
  (define mesh
    (mesh3d #:id 'triangle
            #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
            #:triangles (vector (vector 0 1 2))
            #:material white-lambert))
  (define view
    (view3d (list mesh) #:id 'world #:width 4 #:height 4 #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 3) #:look-at origin3)
            #:lights (list (point-light3d (vec3 0 0 3)
                                          #:attenuation inverse))))
  (define prepared-target
    (software-render-result-target (render-view3d-opaque view 8 8)))
  (define camera-space-point (rgb-at prepared-target 4 4))
  (check-true (<= 90 (vector-ref camera-space-point 0) 96)))
