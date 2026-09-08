#lang racket/base

;;; SCENE-3D-V10: pure material/light/fragment inspection records

(require rackunit
         "../3d.rkt"
         "../private/color-style.rkt")

(module+ test
  (define material
    (material3d #:color "white" #:shading 'smooth #:lighting 'blinn-phong
                #:ambient 1/2 #:diffuse 1 #:specular 1 #:roughness 1
                #:emission "black" #:casts-shadow? #t #:receives-shadow? #t))
  (define shadow-settings
    (shadow-settings3d #:map-size 64 #:depth-bias 1/100 #:normal-bias 1/20
                       #:pcf-radius 2))
  (define sun
    (directional-light3d (vec3 0 0 -1) #:id 'sun #:intensity 2
                         #:shadow (directional-shadow3d #:settings shadow-settings)))
  (define fill (ambient-light3d #:id 'fill #:intensity 1))
  (define lamp
    (spot-light3d (vec3 0 0 2) (vec3 0 0 -1) #:id 'lamp
                  #:intensity 3 #:inner-angle 1/10 #:outer-angle 1/2
                  #:attenuation (constant-attenuation3d #:factor 1/4)))

  (define material-report (material3d-inspection material))
  (check-equal? (hash-ref (material-inspection3d-fields material-report) 'normal-mode) 'smooth)
  (check-equal? (hash-ref (material-inspection3d-fields material-report)
                          'derived-specular-exponent)
                1)
  (check-true (hash-ref (material-inspection3d-fields material-report) 'casts-shadow?))

  (define sun-report (light3d-inspection sun))
  (define sun-fields (light-inspection3d-fields sun-report))
  (check-equal? (hash-ref sun-fields 'id) 'sun)
  (check-equal? (hash-ref sun-fields 'type) 'directional)
  (check-equal? (hash-ref (hash-ref sun-fields 'shadow) 'map-size) 64)
  (check-equal? (hash-ref (hash-ref sun-fields 'shadow) 'bias-model) 'legacy-depth)
  (define semantic-sun
    (directional-light3d
     (vec3 0 0 -1) #:id 'semantic-sun
     #:shadow
     (directional-shadow3d
      #:settings
      (shadow-settings3d
       #:bias (shadow-bias3d #:world-normal-offset 1/100
                             #:slope-scale 1/2
                             #:constant-depth-offset 1/500
                             #:pcf-radius-texels 2)))))
  (define semantic-shadow
    (hash-ref (light-inspection3d-fields (light3d-inspection semantic-sun))
              'shadow))
  (check-equal? (hash-ref semantic-shadow 'bias-model) 'semantic-world)
  (check-equal? (hash-ref (hash-ref semantic-shadow 'semantic-bias)
                          'pcf-radius-texels)
                2)
  (define lamp-fields (light-inspection3d-fields (light3d-inspection lamp)))
  (check-equal? (hash-ref lamp-fields 'type) 'spot)
  (check-equal? (hash-ref lamp-fields 'range) #f)
  (check-equal? (hash-ref (hash-ref lamp-fields 'attenuation) 'mode) 'constant)

  ;; At the origin the directional source has facing one. Its supplied shadow
  ;; factor is retained explicitly, so the report shows the scalar that has
  ;; already reduced both diffuse and Blinn--Phong energy.
  (define report
    (fragment-lighting-inspection3d
     material (list fill sun) origin3 z-axis3 (vec3 0 0 4)
     #:tone-map (tone-map3d 'reinhard 1 1)
     #:shadow-factors (hasheq 'sun 1/4)))
  (define sample
    (for/first ([candidate (in-list (fragment-lighting-report3d-light-samples report))]
                #:when (eq? (fragment-light-sample3d-id candidate) 'sun))
      candidate))
  (check-equal? (fragment-light-sample3d-id sample) 'sun)
  (check-equal? (fragment-light-sample3d-shadow-factor sample) 1/4)
  (check-equal? (fragment-light-sample3d-shadow-state sample) 'sampled)
  (check-= (fragment-light-sample3d-facing sample) 1 1e-12)
  (check-= (fragment-light-sample3d-diffuse-energy sample) 1/2 1e-12)
  (check-= (fragment-light-sample3d-specular-energy sample) 1/2 1e-12)
  ;; Material ambient is 1/2; diffuse and specular each contribute 1/2, so
  ;; pre-tone-map white is 3/2 and Reinhard maps it to 3/5.
  (check-= (linear-rgba3d-red (fragment-lighting-report3d-pre-tone-map report)) 3/2 1e-12)
  (check-= (rgba-color-red (fragment-lighting-report3d-final-srgb report))
           (* 255 (linear-channel->srgb 3/5)) 1e-12)
  (check-equal? (fragment-lighting-report3d-diagnostics report) '())

  ;; A declared descriptor with no renderer-provided map sample is visible as
  ;; an honest diagnostic rather than a fabricated occlusion answer.
  (define unavailable
    (fragment-lighting-inspection3d material (list sun) origin3 z-axis3 (vec3 0 0 4)))
  (check-equal? (fragment-light-sample3d-shadow-state
                 (car (fragment-lighting-report3d-light-samples unavailable)))
                'not-sampled)
  (check-equal? (hash-ref (car (fragment-lighting-report3d-diagnostics unavailable)) 'kind)
                'shadow-factor-unavailable)

  (define unlit
    (material3d #:color "tomato" #:shading 'unlit #:emission "white"
                #:emission-strength 1/2))
  (define unlit-report
    (fragment-lighting-inspection3d unlit (list sun lamp) origin3 z-axis3 (vec3 0 0 4)))
  (check-equal? (linear-rgba3d-alpha (fragment-lighting-report3d-pre-tone-map unlit-report)) 1))
