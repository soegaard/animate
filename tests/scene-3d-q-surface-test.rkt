#lang racket/base

;;; SCENE-3D-Q Surface Producer Invariants

(require rackunit
         "../3d.rkt")

(module+ test
  (define adaptive
    (adaptive-parametric-surface3d
     (lambda (u v) (vec3 u v (* 1/3 (sin (* 5 u)))))
     #:u-range '(-1 1) #:v-range '(-1 1) #:id 'adaptive
     #:maximum-depth 4 #:position-tolerance 1/100))
  (check-eq? (surface3d-kind adaptive) 'adaptive-parametric)
  (check-true (positive? (vector-length (mesh3d-triangles (surface3d->mesh3d adaptive)))))
  (check-equal? (surface3d-mesh adaptive)
                (surface3d-mesh
                 (adaptive-parametric-surface3d
                  (lambda (u v) (vec3 u v (* 1/3 (sin (* 5 u)))))
                  #:u-range '(-1 1) #:v-range '(-1 1) #:id 'adaptive
                  #:maximum-depth 4 #:position-tolerance 1/100)))

  (define disk
    (trimmed-parametric-surface3d
     (lambda (u v) (vec3 u v 0))
     #:u-range '(-1 1) #:v-range '(-1 1) #:id 'disk
     #:trims (list (surface-trim (lambda (u v) (- 1 (+ (* u u) (* v v))))))))
  (check-eq? (surface3d-kind disk) 'trimmed-parametric)
  (check-true (surface3d-domain-contains? disk 0 0))
  (check-false (surface3d-domain-contains? disk 1 1))

  (define sphere
    (implicit-surface3d
     (lambda (point)
       (- (+ (* (vec3-x point) (vec3-x point))
             (* (vec3-y point) (vec3-y point))
             (* (vec3-z point) (vec3-z point)))
          16/25))
     #:id 'sphere #:resolution 12))
  (define sphere-mesh (surface3d->mesh3d sphere))
  (check-eq? (surface3d-kind sphere) 'implicit)
  (check-true (positive? (vector-length (mesh3d-triangles sphere-mesh))))
  (check-equal? (vector-length (mesh3d-boundary-edges sphere-mesh)) 0))
