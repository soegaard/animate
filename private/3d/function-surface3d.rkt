#lang racket/base

;;;
;;; Graph Surfaces
;;;

;; Provides the common z=f(x,y) specialization while preserving the same
;; fixed-grid surface representation as arbitrary parameterizations.


;;;
;;; Imports and Exports
;;;

(require "../geometry.rkt"
         "material3d.rkt"
         "parametric-surface3d.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide function-surface3d)


;;;
;;; Construction
;;;

; function-surface3d : (finite-real? finite-real? -> finite-real?)
;                      #:x-range two-real-range? #:y-range two-real-range?
;                      #:resolution two-exact-integer-resolution? #:id symbol? ...
;                      -> surface3d?
;;   Creates the graph z=f(x,y), retaining optional analytic height derivatives.
(define (function-surface3d function
                            #:x-range [x-range (list -1 1)]
                            #:y-range [y-range (list -1 1)]
                            #:resolution [resolution (list 33 33)]
                            #:id id
                            #:derivative-x [derivative-x #f]
                            #:derivative-y [derivative-y #f]
                            #:material [material (material3d #:color "steelblue" #:shading 'smooth)]
                            #:transform [transform identity-transform3]
                            #:opacity [opacity 1]
                            #:wireframe-color [wireframe-color "steelblue"]
                            #:wireframe-width [wireframe-width 1])
  (unless (procedure? function)
    (raise-argument-error 'function-surface3d "procedure?" function))
  (unless (or (not derivative-x) (procedure? derivative-x))
    (raise-argument-error 'function-surface3d "(or/c #f procedure?)" derivative-x))
  (unless (or (not derivative-y) (procedure? derivative-y))
    (raise-argument-error 'function-surface3d "(or/c #f procedure?)" derivative-y))
  (define (height x y)
    (define result (function x y))
    (unless (finite-real? result)
      (raise-arguments-error 'function-surface3d
                             "a finite real height at every grid point"
                             "x" x "y" y "result" result))
    result)
  (define (dx x y)
    (and derivative-x
         (let ([result (derivative-x x y)])
           (unless (finite-real? result)
             (raise-arguments-error 'function-surface3d
                                    "a finite real partial-x derivative"
                                    "x" x "y" y "result" result))
           result)))
  (define (dy x y)
    (and derivative-y
         (let ([result (derivative-y x y)])
           (unless (finite-real? result)
             (raise-arguments-error 'function-surface3d
                                    "a finite real partial-y derivative"
                                    "x" x "y" y "result" result))
           result)))
  (define surface
    (parametric-surface3d
     (lambda (x y) (vec3 x y (height x y)))
     #:u-range x-range #:v-range y-range #:resolution resolution #:id id
     #:derivative-u (and derivative-x (lambda (x y) (vec3 1 0 (dx x y))))
     #:derivative-v (and derivative-y (lambda (x y) (vec3 0 1 (dy x y))))
     #:material material #:transform transform #:opacity opacity
     #:wireframe-color wireframe-color #:wireframe-width wireframe-width))
  (surface3d-with-scalar-data surface height dx dy))
