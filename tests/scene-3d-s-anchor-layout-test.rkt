#lang racket/base

;;; SCENE-3D-S Anchor and Direct Layout Determinism

(require rackunit
         "../3d.rkt")

(module+ test
  (define world (view3d (list (cube3d 2 #:id 'cube)) #:id 'world))
  (define anchor (vertex-anchor3d '(world cube) 0))
  (define resolved (anchor3d-resolve anchor world))
  (check-equal? (resolved-anchor3d-world-point resolved) (vec3 -1 -1 -1))
  (check-equal? (anchor3d-identity anchor) (vector 'vertex '(world cube) 0))
  (define plane
    (parametric-surface3d (lambda (u v) (vec3 u v 0))
                         #:u-range '(-1 1) #:v-range '(-1 1)
                         #:resolution '(3 3) #:id 'plane))
  (define surface-world (view3d (list plane) #:id 'surface-world))
  (define surface-anchor (surface-anchor3d '(surface-world plane) #:u 0 #:v 0))
  (check-= (vec3-z (anchor3d-normal surface-anchor surface-world)) 1 1e-12)
  (check-= (vec3-x (anchor3d-tangent surface-anchor surface-world)) 1 1e-12)
  (define placement (label-placement3d '(east north) 16 2 #t #t '() 1 8))
  (define items
    (list (label-layout-item3d 'first (vector 50 50) 30 10 0 placement)
          (label-layout-item3d 'second (vector 50 50) 30 10 0 placement)))
  (define first-layout (layout-labels3d items #:width 100 #:height 100))
  (define second-layout (layout-labels3d items #:width 100 #:height 100))
  (check-equal? first-layout second-layout)
  (check-equal? (map label-layout-candidate3d-item-id (label-layout3d-placements first-layout))
                '(first second))
  ;; Equal priorities retain declaration order, not lexical ID order.
  (define declaration-layout
    (layout-labels3d
     (list (label-layout-item3d 'zeta (vector 20 20) 5 5 0 placement)
           (label-layout-item3d 'alpha (vector 80 80) 5 5 0 placement))
     #:width 100 #:height 100))
  (check-equal? (map label-layout-candidate3d-item-id
                     (label-layout3d-placements declaration-layout))
                '(zeta alpha))
  ;; With equal geometric cost, preferred order is decisive. `east` precedes
  ;; `north` for this policy even though the global compass order is north-first.
  (define preferred-layout
    (layout-labels3d
     (list (label-layout-item3d
            'preferred (vector 50 50) 5 5 0
            (label-placement3d '(east north) 10 2 #t #t '() 1 8)))
     #:width 100 #:height 100))
  (check-eq? (label-layout-candidate3d-direction
              (car (label-layout3d-placements preferred-layout)))
             'east)
  ;; Prepared layout can retain a direction through a small direct-mode flip.
  ;; Its output is an immutable table, so arbitrary frame lookup remains pure.
  (define prepared
    (prepare-label-layout3d
     (list (cons 0 (list (label-layout-item3d 'moving (vector 50 50) 8 8 0 placement)))
           (cons 1 (list (label-layout-item3d 'moving (vector 51 50) 8 8 0 placement))))
     #:width 100 #:height 100 #:switch-penalty 100 #:movement-penalty 1))
  (check-equal? (prepared-label-layout3d-frames prepared) #(0 1))
  (check-equal? (prepared-label-layout3d-ref prepared 1)
                (prepared-label-layout3d-ref prepared 1))
  (check-equal? (hash-ref (label-layout3d-diagnostics
                           (prepared-label-layout3d-ref prepared 0))
                          'mode)
                'prepared))
