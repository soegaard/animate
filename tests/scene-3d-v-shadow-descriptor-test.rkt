#lang racket/base

;;; SCENE-3D-V7: immutable shadow descriptors and stable bounds preparation

(require racket/set
         rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../private/color-style.rkt")

(define caster-material
  (material3d #:color "white" #:shading 'flat #:lighting 'lambert))
(define transparent-material
  (material3d #:color (rgba-color 255 255 255 1/2) #:shading 'flat))
(define non-caster-material
  (material3d #:color "white" #:shading 'flat #:casts-shadow? #f))

(define (world light #:camera [camera (orthographic-camera3d #:position (vec3 0 0 8)
                                                          #:look-at origin3)]
               #:caster-x [caster-x 0])
  (view3d
   (list (cube3d 2 #:id 'caster #:material caster-material
                 #:transform (make-transform3 #:translation (vec3 caster-x 0 0)))
         ;; These two remain visible scene geometry, but V7 documents that
         ;; transparent and explicitly opted-out material do not cast maps.
         (cube3d 2 #:id 'transparent #:material transparent-material
                 #:transform (make-transform3 #:translation (vec3 12 0 0)))
         (cube3d 2 #:id 'non-caster #:material non-caster-material
                 #:transform (make-transform3 #:translation (vec3 -12 0 0))))
   #:id 'world #:width 8 #:height 6 #:render-mode 'opaque #:camera camera
   #:lights (list light)))

(module+ test
  (define settings
    (shadow-settings3d #:map-size 256 #:depth-bias 1/2000 #:normal-bias 1/100
                       #:pcf-radius 2 #:prepared-bounds-key 'stable-sun))
  (check-true (shadow-settings3d? settings))
  (check-equal? (shadow-settings3d-map-size settings) 256)
  (check-equal? (shadow-settings3d-pcf-radius settings) 2)
  (check-equal? (shadow-settings3d-prepared-bounds-key settings) 'stable-sun)
  (check-exn exn:fail? (lambda () (shadow-settings3d #:map-size 0)))
  (check-exn exn:fail? (lambda () (shadow-settings3d #:depth-bias -1)))
  (check-exn exn:fail? (lambda () (shadow-settings3d #:near 2 #:far 1)))
  (check-exn exn:fail?
             (lambda () (shadow-settings3d #:bounds aabb3-empty)))

  (define sun-shadow (directional-shadow3d #:settings settings))
  (define cone-shadow (spot-shadow3d #:settings settings))
  (check-true (directional-shadow3d? sun-shadow))
  (check-true (spot-shadow3d? cone-shadow))
  (check-equal? (shadow3d-kind sun-shadow) 'directional)
  (check-equal? (shadow3d-settings cone-shadow) settings)

  (define sun
    (directional-light3d (vec3 1 -1 -1) #:id 'sun #:shadow sun-shadow))
  (define cone
    (spot-light3d (vec3 0 3 4) (vec3 0 -1 -1) #:id 'cone #:shadow cone-shadow))
  (check-equal? (light3d-shadow sun) sun-shadow)
  (check-equal? (light3d-shadow cone) cone-shadow)
  (check-exn exn:fail?
             (lambda () (directional-light3d z-axis3 #:shadow cone-shadow)))
  (check-exn exn:fail?
             (lambda () (spot-light3d origin3 z-axis3 #:shadow sun-shadow)))
  (check-exn exn:fail?
             (lambda () (ambient-light3d #:shadow sun-shadow)))
  (check-exn exn:fail?
             (lambda () (point-light3d origin3 #:shadow sun-shadow)))

  ;; Only the central opaque caster contributes.  The prepared world bounds
  ;; exclude the transparent/non-casting cubes at x = +/-12.
  (define first-view (world sun))
  (define prepared
    (prepare-shadow-bounds3d first-view #:light-id 'sun))
  (check-true (prepared-shadow-bounds3d? prepared))
  (check-equal? (prepared-shadow-bounds3d-frame-range prepared) (cons 0 0))
  (check-true (aabb3-contains? (prepared-shadow-bounds3d-bounds prepared) origin3))
  (check-false (aabb3-contains? (prepared-shadow-bounds3d-bounds prepared) (vec3 12 0 0)))
  (check-false (aabb3-empty? (prepared-shadow-bounds3d-light-space-bounds prepared)))
  (check-equal? (hash-ref (prepared-shadow-bounds3d-diagnostics prepared) 'source)
                'opaque-casters)

  ;; A sampled range unions opaque casters across the supplied immutable views.
  (define moved-view (world sun #:caster-x 4))
  (define range-prepared
    (prepare-shadow-bounds3d (list first-view moved-view) #:light-id 'sun
                             #:frame-range (cons 4 5)))
  (check-true (aabb3-contains? (prepared-shadow-bounds3d-bounds range-prepared)
                               (vec3 5 0 0)))
  (check-equal? (prepared-shadow-bounds3d-frame-range range-prepared) (cons 4 5))
  (check-exn
   exn:fail?
   (lambda ()
     (prepare-shadow-bounds3d
      (list first-view
            (world (directional-light3d (vec3 0 -1 -1) #:id 'sun #:shadow sun-shadow)))
      #:light-id 'sun)))

  ;; The identity captures caster resources and light settings, but not the
  ;; view camera. A camera orbit can therefore reuse a future shadow map.
  (define orbit-view
    (world sun #:camera (orthographic-camera3d #:position (vec3 4 3 8)
                                               #:look-at origin3)))
  (check-equal? (shadow-map3d-identity first-view 'sun prepared)
                (shadow-map3d-identity orbit-view 'sun prepared))
  (check-not-equal? (shadow-map3d-identity first-view 'sun prepared)
                    (shadow-map3d-identity moved-view 'sun range-prepared))

  ;; A descriptor remains a capability demand. V8's software renderer now
  ;; advertises and prepares directional maps; the OpenGL renderer remains
  ;; deliberately unavailable until V9 rather than silently ignoring it.
  (define request (view3d->render3d-request first-view 80 60))
  (check-true (set-member? (renderer3d-request-required-features request)
                           'directional-shadow))
  (check-equal? (hash-ref (renderer3d-request-required-limits request)
                          'maximum-shadow-lights)
                1)
  (check-equal? (hash-ref (renderer3d-request-required-limits request)
                          'maximum-shadow-map-size)
                256)
  (check-true
   (renderer3d-supports?
    (renderer3d-capabilities-of (software-renderer3d))
    '(directional-shadow)))
  (check-not-exn
   (lambda () (renderer3d-prepare (software-renderer3d) request))))
