#lang racket/base

;;; SCENE-3D-V8: software depth maps, PCF comparison, and material policy

(require rackunit
         "../3d.rkt"
         "../3d/render.rkt")

(define receiver-material
  (material3d #:color "white" #:shading 'flat #:lighting 'lambert
              #:ambient 0 #:diffuse 1 #:specular 0 #:casts-shadow? #f))
(define caster-material
  (material3d #:color "gray" #:shading 'flat #:lighting 'lambert
              #:ambient 0 #:diffuse 1 #:specular 0))

(define (square id half-size z material)
  (mesh3d #:id id
          #:vertices
          (vector (vec3 (- half-size) (- half-size) z)
                  (vec3 half-size (- half-size) z)
                  (vec3 half-size half-size z)
                  (vec3 (- half-size) half-size z))
          #:triangles (vector (vector 0 1 2) (vector 0 2 3))
          #:material material))

;; A small plate at z=1 casts onto a broad receiver at z=0. The light travels
;; down and right, so the probe at x=1 is on the receiver's shadow but is not
;; geometrically covered by the plate in the main camera.
(define receiver (square 'receiver 3 0 receiver-material))
(define caster (square 'caster 1/3 1 caster-material))
(define shadow-bounds (aabb3 (vec3 -3 -3 0) (vec3 3 3 1)))
(define shadow-settings
  (shadow-settings3d #:map-size 128 #:pcf-radius 0
                     #:depth-bias 1/200 #:normal-bias 0
                     #:bounds shadow-bounds))

(define (test-view #:shadow? [shadow? #t]
                   #:casts-shadow? [casts-shadow? #t]
                   #:receives-shadow? [receives-shadow? #t])
  (define modified-receiver
    (material3d-with-shadow-policy receiver-material
                                   #:receives-shadow? receives-shadow?))
  (define modified-caster
    (material3d-with-shadow-policy caster-material #:casts-shadow? casts-shadow?))
  (define sun
    (directional-light3d
     (vec3 1 0 -1) #:id 'sun
     #:shadow (and shadow? (directional-shadow3d #:settings shadow-settings))))
  (view3d
   (list (square 'receiver 3 0 modified-receiver)
         (square 'caster 1/3 1 modified-caster))
   #:id 'shadow-world #:width 6 #:height 6 #:background "black" #:render-mode 'opaque
   #:camera (orthographic-camera3d #:position (vec3 0 0 8) #:look-at origin3
                                  #:vertical-size 6)
   #:lights (list sun)))

(define (spot-test-view #:shadow? [shadow? #t])
  ;; The source lies on the same outgoing diagonal as the directional test,
  ;; putting the plate and its receiver shadow in the centre of the spot cone.
  (define cone
    (spot-light3d
     (vec3 -3 0 4) (vec3 1 0 -1) #:id 'cone
     #:inner-angle 1/4 #:outer-angle 1
     #:attenuation (constant-attenuation3d)
     #:shadow (and shadow? (spot-shadow3d #:settings shadow-settings))))
  (view3d
   (list receiver caster)
   #:id 'spot-shadow-world #:width 6 #:height 6 #:background "black" #:render-mode 'opaque
   #:camera (orthographic-camera3d #:position (vec3 0 0 8) #:look-at origin3
                                  #:vertical-size 6)
   #:lights (list cone)))

(define (render-bytes view)
  (define renderer (software-renderer3d))
  (define request (view3d->render3d-request view 64 64))
  (renderer3d-render-result-argb-bytes
   (renderer3d-render renderer (renderer3d-prepare renderer request) request)))

(define (red-at bytes x y)
  (bytes-ref bytes (add1 (* 4 (+ x (* y 64))))))

(module+ test
  ;; Direct samples make the depth-comparison semantics independent of scene
  ;; construction: a receiver behind depth 1 is fully shadowed; a shallower
  ;; receiver and samples outside the light frustum remain lit.
  (define unit-settings
    (shadow-settings3d #:map-size 2 #:pcf-radius 0 #:depth-bias 0 #:normal-bias 0
                       #:bounds (aabb3 (vec3 -1 -1 0) (vec3 1 1 1))))
  (define unit-camera
    (orthographic-camera3d #:position (vec3 0 0 2) #:look-at origin3
                           #:near 1 #:far 3 #:vertical-size 2))
  (define unit-map
    (shadow-map3d 2 2 (vector-immutable 1 1 1 1) unit-camera unit-settings
                  (shadow-settings3d-bounds unit-settings) (hasheq)))
  (check-equal? (shadow-map3d-factor unit-map origin3 z-axis3 (vec3 0 0 -1)) 0)
  (check-equal? (shadow-map3d-factor unit-map (vec3 0 0 3/2) z-axis3 (vec3 0 0 -1)) 1)
  (check-equal? (shadow-map3d-factor unit-map (vec3 3 0 0) z-axis3 (vec3 0 0 -1)) 1)

  ;; These two probes pin down the named bias trade-off. A small positive
  ;; receiver-depth bias removes a near-coplanar acne comparison; a very large
  ;; bias intentionally turns a genuinely blocked receiver lit (the familiar
  ;; peter-panning failure), so neither backend may hide it behind an unnamed
  ;; epsilon.
  (define biased-settings
    (shadow-settings3d #:map-size 2 #:pcf-radius 0 #:depth-bias 1/50 #:normal-bias 0
                       #:bounds (shadow-settings3d-bounds unit-settings)))
  (define biased-map
    (shadow-map3d 2 2 (vector-immutable 1 1 1 1) unit-camera biased-settings
                  (shadow-settings3d-bounds biased-settings) (hasheq)))
  (check-equal? (shadow-map3d-factor biased-map (vec3 0 0 99/100)
                                      z-axis3 (vec3 0 0 -1))
                1)
  (define over-biased-settings
    (shadow-settings3d #:map-size 2 #:pcf-radius 0 #:depth-bias 1/4 #:normal-bias 0
                       #:bounds (shadow-settings3d-bounds unit-settings)))
  (define over-biased-map
    (shadow-map3d 2 2 (vector-immutable 1 1 1 1) unit-camera over-biased-settings
                  (shadow-settings3d-bounds over-biased-settings) (hasheq)))
  (check-equal? (shadow-map3d-factor over-biased-map (vec3 0 0 9/10)
                                      z-axis3 (vec3 0 0 -1))
                1)

  ;; The semantic path moves the receiver toward the light before projection,
  ;; rather than adding a backend-specific normalized-depth epsilon. On this
  ;; unit camera the 1/50 world-unit move reproduces the intended near-contact
  ;; outcome while keeping its unit explicit.
  (define semantic-settings
    (shadow-settings3d
     #:map-size 2
     #:bias (shadow-bias3d #:constant-depth-offset 1/50
                           #:pcf-radius-texels 0)
     #:bounds (shadow-settings3d-bounds unit-settings)))
  (define semantic-map
    (shadow-map3d 2 2 (vector-immutable 1 1 1 1) unit-camera semantic-settings
                  (shadow-settings3d-bounds semantic-settings) (hasheq)))
  (check-equal? (shadow-map3d-factor semantic-map (vec3 0 0 99/100)
                                      z-axis3 (vec3 0 0 -1))
                1)

  ;; The kernel is a square, including its centre. With only the central map
  ;; texel deep enough for this receiver, radius one returns exactly 1/9.
  (define pcf-settings
    (shadow-settings3d #:map-size 3 #:pcf-radius 1 #:depth-bias 0 #:normal-bias 0
                       #:bounds (shadow-settings3d-bounds unit-settings)))
  (define pcf-map
    (shadow-map3d 3 3 (vector-immutable 1 1 1 1 2 1 1 1 1)
                  unit-camera pcf-settings (shadow-settings3d-bounds pcf-settings)
                  (hasheq)))
  (check-equal? (shadow-map3d-factor pcf-map origin3 z-axis3 (vec3 0 0 -1)) 1/9)

  (define lit (render-bytes (test-view #:shadow? #f)))
  (define shadowed (render-bytes (test-view)))
  (define non-casting (render-bytes (test-view #:casts-shadow? #f)))
  (define non-receiving (render-bytes (test-view #:receives-shadow? #f)))
  (define spot-lit (render-bytes (spot-test-view #:shadow? #f)))
  (define spot-shadowed (render-bytes (spot-test-view)))
  ;; x=43 corresponds to world x slightly above 1; y=32 is the middle row.
  (define probe-x 43)
  (define probe-y 32)
  (check-true (> (red-at lit probe-x probe-y) 200))
  (check-true (< (red-at shadowed probe-x probe-y) 40))
  (check-equal? (red-at non-casting probe-x probe-y)
                (red-at lit probe-x probe-y))
  (check-equal? (red-at non-receiving probe-x probe-y)
                (red-at lit probe-x probe-y))
  (check-true (> (red-at spot-lit probe-x probe-y) 100))
  (check-true (< (red-at spot-shadowed probe-x probe-y) 30)))
