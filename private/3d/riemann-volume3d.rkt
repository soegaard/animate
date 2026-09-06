#lang racket/base

;;;
;;; Addressable Riemann Volume Columns
;;;

;; This is deliberately a small explanatory construction rather than a CAD
;; Boolean.  Every midpoint column is an ordinary mesh below a stable row/cell
;; path, so it can be selected, styled, or animated through the usual spatial
;; relation machinery.

(require racket/list
         "../geometry.rkt"
         "material3d.rkt"
         "solids3d.rkt"
         "spatial-group.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide riemann-volume3d
         washer-sum3d
         shell-sum3d)

; riemann-volume3d : (finite-real? finite-real? -> finite-real?) ... -> group3d?
;; Constructs m*n midpoint columns between `base` and f(x,y).  A zero-height
;; sample remains an empty addressable cell group; it does not fabricate a
;; nonzero solid merely to satisfy a renderer representation.
(define (riemann-volume3d function
                          #:x-range [x-range (list -1 1)]
                          #:y-range [y-range (list -1 1)]
                          #:resolution [resolution (list 8 8)]
                          #:base [base 0]
                          #:id id
                          #:material [material (material3d #:color "cornflowerblue"
                                                           #:shading 'flat)])
  (unless (procedure? function)
    (raise-argument-error 'riemann-volume3d "procedure?" function))
  (check-range 'riemann-volume3d x-range)
  (check-range 'riemann-volume3d y-range)
  (unless (and (list? resolution) (= (length resolution) 2)
               (andmap exact-positive-integer? resolution))
    (raise-argument-error 'riemann-volume3d "two positive exact resolution counts" resolution))
  (unless (finite-real? base)
    (raise-argument-error 'riemann-volume3d "finite real base" base))
  (unless (symbol? id)
    (raise-argument-error 'riemann-volume3d "symbol? id" id))
  (unless (material3d? material)
    (raise-argument-error 'riemann-volume3d "material3d?" material))
  (define x-count (first resolution))
  (define y-count (second resolution))
  (define dx (/ (- (second x-range) (first x-range)) x-count))
  (define dy (/ (- (second y-range) (first y-range)) y-count))
  (group3d
   (for/list ([x-index (in-range x-count)])
     (define x (+ (first x-range) (* (+ x-index 1/2) dx)))
     (group3d
      (for/list ([y-index (in-range y-count)])
        (define y (+ (first y-range) (* (+ y-index 1/2) dy)))
        (define height
          (with-handlers ([exn:fail?
                           (lambda (exception)
                             (raise-arguments-error
                              'riemann-volume3d "a total finite height function"
                              "x" x "y" y "exception" (exn-message exception)))])
            (function x y)))
        (unless (finite-real? height)
          (raise-arguments-error 'riemann-volume3d "a finite height function"
                                 "x" x "y" y "result" height))
        (define cell-id (string->symbol (format "cell-~a" y-index)))
        (if (= height base)
            (group3d '() #:id cell-id)
            (box3d dx dy (abs (- height base))
                   #:id cell-id #:material material
                   #:transform
                   (make-transform3
                    #:translation (vec3 x y (/ (+ base height) 2))))))
      #:id (string->symbol (format "row-~a" x-index))))
   #:id id))

(define (check-range who range)
  (unless (and (list? range) (= (length range) 2)
               (andmap finite-real? range) (< (first range) (second range)))
    (raise-argument-error who "an increasing two-finite-real range" range)))

;; washer-sum3d : (real? -> real?) (real? -> real?) ... -> group3d?
;; Builds midpoint annular slabs around the x axis.  It is a visual sum, not a
;; numerical estimate; use `volume-by-slices3d` when a measured value is the
;; goal.  Each slab remains separately addressable as `washer-n`.
(define (washer-sum3d outer inner
                       #:x-range [x-range (list -1 1)]
                       #:count [count 8]
                       #:segments [segments 48]
                       #:id id
                       #:material [material (material3d #:color "goldenrod" #:shading 'flat)])
  (unless (and (procedure? outer) (procedure? inner))
    (raise-argument-error 'washer-sum3d "two procedures" (list outer inner)))
  (check-range 'washer-sum3d x-range)
  (check-positive-count 'washer-sum3d count)
  (check-revolution-segments 'washer-sum3d segments)
  (unless (symbol? id) (raise-argument-error 'washer-sum3d "symbol? id" id))
  (unless (material3d? material)
    (raise-argument-error 'washer-sum3d "material3d?" material))
  (define dx (/ (- (second x-range) (first x-range)) count))
  (group3d
   (for/list ([index (in-range count)])
     (define left (+ (first x-range) (* index dx)))
     (define right (+ left dx))
     (define midpoint (/ (+ left right) 2))
     (define outer-radius (evaluate-radius 'washer-sum3d outer midpoint 'outer))
     (define inner-radius (evaluate-radius 'washer-sum3d inner midpoint 'inner))
     (unless (<= inner-radius outer-radius)
       (raise-arguments-error 'washer-sum3d "an inner radius no larger than the outer radius"
                              "x" midpoint "inner" inner-radius "outer" outer-radius))
     (define cell-id (string->symbol (format "washer-~a" index)))
     (if (= inner-radius outer-radius)
         (group3d '() #:id cell-id)
         (revolve3d (list (vec2 left inner-radius) (vec2 right inner-radius)
                          (vec2 right outer-radius) (vec2 left outer-radius))
                    #:id cell-id #:axis 'x #:segments segments #:material material)))
   #:id id))

;; shell-sum3d : (real? -> real?) ... -> group3d?
;; Builds midpoint cylindrical shells about the z axis. A supplied function
;; denotes the z coordinate of the graph; `base` is its other endpoint.
(define (shell-sum3d height
                      #:radius-range [radius-range (list 0 1)]
                      #:count [count 8]
                      #:segments [segments 48]
                      #:base [base 0]
                      #:id id
                      #:material [material (material3d #:color "mediumpurple" #:shading 'flat)])
  (unless (procedure? height)
    (raise-argument-error 'shell-sum3d "procedure?" height))
  (check-range 'shell-sum3d radius-range)
  (unless (>= (first radius-range) 0)
    (raise-argument-error 'shell-sum3d "a nonnegative radius range" radius-range))
  (check-positive-count 'shell-sum3d count)
  (check-revolution-segments 'shell-sum3d segments)
  (unless (finite-real? base)
    (raise-argument-error 'shell-sum3d "finite real base" base))
  (unless (symbol? id) (raise-argument-error 'shell-sum3d "symbol? id" id))
  (unless (material3d? material)
    (raise-argument-error 'shell-sum3d "material3d?" material))
  (define dr (/ (- (second radius-range) (first radius-range)) count))
  (group3d
   (for/list ([index (in-range count)])
     (define inner-radius (+ (first radius-range) (* index dr)))
     (define outer-radius (+ inner-radius dr))
     (define radius (/ (+ inner-radius outer-radius) 2))
     (define top
       (with-handlers ([exn:fail?
                        (lambda (exception)
                          (raise-arguments-error 'shell-sum3d "a total finite height function"
                                                 "radius" radius "exception" (exn-message exception)))])
         (height radius)))
     (unless (finite-real? top)
       (raise-arguments-error 'shell-sum3d "a finite height function"
                              "radius" radius "result" top))
     (define cell-id (string->symbol (format "shell-~a" index)))
     (if (= top base)
         (group3d '() #:id cell-id)
         (revolve3d (list (vec2 base inner-radius) (vec2 top inner-radius)
                          (vec2 top outer-radius) (vec2 base outer-radius))
                    #:id cell-id #:axis 'z #:segments segments #:material material)))
   #:id id))

(define (evaluate-radius who function x role)
  (define result
    (with-handlers ([exn:fail?
                     (lambda (exception)
                       (raise-arguments-error who "a total finite radius function"
                                              "x" x "role" role "exception" (exn-message exception)))])
      (function x)))
  (unless (and (finite-real? result) (>= result 0))
    (raise-arguments-error who "a nonnegative finite radius" "x" x "role" role "result" result))
  result)

(define (check-positive-count who count)
  (unless (exact-positive-integer? count)
    (raise-argument-error who "exact-positive-integer?" count)))

(define (check-revolution-segments who count)
  (unless (and (exact-positive-integer? count) (>= count 3))
    (raise-argument-error who "an exact integer at least 3" count)))
