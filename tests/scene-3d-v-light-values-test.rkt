#lang racket/base

;;; SCENE-3D-V3: stable authored light values and attenuation semantics

(require racket/set
         rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         (only-in "../private/3d/view3d-visual.rkt" view3d-content-key))

(define (made-view lights)
  (view3d
   (list (cube3d 1 #:id 'cube #:material (material3d #:shading 'flat)))
   #:id 'world #:width 4 #:height 3 #:render-mode 'opaque #:lights lights))

(module+ test
  ;; Every authored light has one durable symbolic identity and the generic
  ;; accessors preserve the specific constructor's values.
  (define ambient (ambient-light3d #:id 'fill #:intensity 1/4 #:color "gold"))
  (define directional
    (directional-light3d (vec3 0 0 -4) #:id 'key #:intensity 3/4 #:color "white"))
  (define point
    (point-light3d (vec3 2 3 4) #:id 'lamp #:intensity 2 #:color "tomato"
                   #:attenuation (inverse-square-attenuation3d #:reference-distance 2)
                   #:range 12))
  (define spot
    (spot-light3d (vec3 0 3 2) (vec3 0 -2 -2)
                  #:id 'spot #:intensity 5/4 #:inner-angle 1/4 #:outer-angle 1/2
                  #:attenuation (polynomial-attenuation3d #:constant 1 #:linear 1)
                  #:range 9))
  (check-equal? (map light3d-id (list ambient directional point spot))
                '(fill key lamp spot))
  (check-equal? (map light3d-kind (list ambient directional point spot))
                '(ambient directional point spot))
  (check-equal? (light3d-intensity point) 2)
  (check-equal? (light3d-shadow spot) #f)
  (check-equal? (point-light3d-position point) (vec3 2 3 4))
  (check-equal? (point-light3d-range point) 12)
  (check-equal? (spot-light3d-range spot) 9)
  (check-= (vec3-length (directional-light3d-direction directional)) 1 1e-12)
  (check-= (vec3-length (spot-light3d-direction spot)) 1 1e-12)

  ;; The named attenuation records make the finite-distance rule inspectable
  ;; before V5 installs it in the renderer.
  (define inverse (inverse-square-attenuation3d #:reference-distance 2 #:cutoff 10))
  (check-equal? (light-attenuation3d-mode inverse) 'inverse-square)
  (check-equal? (light-attenuation3d-factor inverse 0) 1)
  (check-equal? (light-attenuation3d-factor inverse 2) 1)
  (check-equal? (light-attenuation3d-factor inverse 4) 1/4)
  (check-equal? (light-attenuation3d-factor inverse 11) 0)
  (check-equal? (light-attenuation3d-factor (constant-attenuation3d #:factor 3/5) 999)
                3/5)
  (check-equal?
   (light-attenuation3d-factor
    (polynomial-attenuation3d #:constant 1 #:linear 1 #:quadratic 1)
    1)
   1/3)
  (check-equal? (spot-smoothstep3d 1/2) 1/2)
  (check-equal? (spot-cone-factor3d 1/4 3/4 0) 1)
  (check-equal? (spot-cone-factor3d 1/4 3/4 1) 0)
  (check-equal? (spot-cone-factor3d 1/4 3/4 1/2) 1/2)
  (check-exn exn:fail? (lambda () (inverse-square-attenuation3d #:reference-distance 0)))
  (check-exn exn:fail? (lambda () (polynomial-attenuation3d #:constant 0)))
  (check-exn exn:fail? (lambda () (spot-light3d origin3 origin3)))
  (check-exn exn:fail? (lambda () (spot-light3d origin3 z-axis3 #:inner-angle 1 #:outer-angle 1/2)))

  ;; A light list is an ID-addressed frame value, never a synthetic spatial
  ;; child: it can be immutably changed without invalidating the spatial cache.
  (define view (made-view (list ambient directional)))
  (define original-key (view3d-content-key view))
  (check-equal? (view3d-light-ref view 'key) directional)
  (define moved-key
    (view3d-light-update
     view 'key
     (lambda (_old)
       (directional-light3d (vec3 1 0 -1) #:id 'key #:intensity 2))))
  (check-equal? (view3d-content-key moved-key) original-key)
  (check-equal? (directional-light3d-intensity (view3d-light-ref moved-key 'key)) 2)
  (check-equal? (directional-light3d-id (view3d-light-ref moved-key 'key)) 'key)
  (check-exn exn:fail?
             (lambda ()
               (view3d-light-replace view 'key
                                     (directional-light3d z-axis3 #:id 'other))))
  (check-exn exn:fail?
             (lambda () (view3d-light-ref view 'missing)))
  (check-exn exn:fail?
             (lambda () (made-view (list ambient (point-light3d origin3 #:id 'fill)))))

  ;; V5's reference renderer accepts finite-light requests rather than
  ;; silently approximating them as directional lights. OpenGL capability
  ;; support remains an explicit later stage.
  (define finite-request (view3d->render3d-request (made-view (list point spot)) 40 30))
  (check-true (set-member? (renderer3d-request-required-features finite-request) 'point-light))
  (check-true (set-member? (renderer3d-request-required-features finite-request) 'spot-light))
  (check-equal? (hash-ref (renderer3d-request-required-limits finite-request)
                'maximum-point-lights)
                1)
  (check-equal? (hash-ref (renderer3d-request-required-limits finite-request)
                'maximum-spot-lights)
                1)
  (check-not-exn
   (lambda ()
     (renderer3d-prepare (software-renderer3d) finite-request))))
