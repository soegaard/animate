#lang racket/base

;;; OpenGL lighting receives preparation-owned numerical colours

(require rackunit
         "../3d.rkt"
         "../colors.rkt"
         (only-in "../private/3d/color-resolution3d.rkt" resolve-lights3d)
         (only-in "../private/3d/opengl/light-preparation.rkt" opengl-light-packing-datum)
         (only-in "../private/render-color-context.rkt" make-render-color-context))

(module+ test
  (define theme
    (color-theme #:id 'gl-light-resolution #:extends animate-light-theme
                 #:palette
                 (color-palette #:id 'gl-light-resolution-palette
                                #:extends animate-palette
                                #:colors (hash 'aqua-c "#2040e0"))
                 #:roles (hash 'lamp (color-mix aqua-c pure-red 1/4))))
  (define authored
    (list (ambient-light3d #:id 'fill #:color aqua-c)
          (directional-light3d (vec3 0 0 -1) #:id 'key #:color (role-color 'lamp))
          (point-light3d (vec3 1 2 3) #:id 'point
                         #:color (color-mix (role-color 'lamp) white 1/2))
          (spot-light3d (vec3 -1 2 3) (vec3 0 0 -1) #:id 'spot
                        #:color (color-mix aqua-c (role-color 'lamp) 1/2))))
  (define resolved
    (resolve-lights3d authored (make-render-color-context theme)))
  (define packed (opengl-light-packing-datum resolved))
  (check-true (andmap rgba-color? (map light3d-color resolved)))
  (check-equal? (map light3d-id resolved) '(fill key point spot))
  (check-equal? (map (lambda (entry) (hash-ref entry 'id))
                     (hash-ref packed 'non-ambient))
                '(key point spot))
  (check-true (andmap rgba-color?
                       (map (lambda (entry) (hash-ref entry 'color))
                            (hash-ref packed 'non-ambient))))
  ;; Raw retained authoring values never cross the numerical GL boundary.
  (check-exn exn:fail?
             (lambda () (opengl-light-packing-datum authored)))
  ;; Resolution rejects themed light alpha before a renderer can allocate or draw.
  (define translucent
    (color-theme #:id 'gl-light-translucent #:extends animate-light-theme
                 #:roles (hash 'lamp (color-with-alpha pure-red 1/2))))
  (check-exn exn:fail?
             (lambda ()
               (resolve-lights3d
                (list (ambient-light3d #:color (role-color 'lamp)))
                (make-render-color-context translucent)))))
