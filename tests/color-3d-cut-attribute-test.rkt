#lang racket/base

;;; Semantic colour attributes survive generated cut vertices

(require rackunit
         "../3d.rkt"
         "../colors.rkt")

(define (check-rgba-close actual expected)
  (check-= (rgba-color-red actual) (rgba-color-red expected) 1e-9)
  (check-= (rgba-color-green actual) (rgba-color-green expected) 1e-9)
  (check-= (rgba-color-blue actual) (rgba-color-blue expected) 1e-9)
  (check-= (rgba-color-alpha actual) (rgba-color-alpha expected) 1e-9))

(module+ test
  ;; Mesh attributes retain the established encoded-sRGB, straight-alpha
  ;; convention rather than the default authoring blend's linear-light,
  ;; premultiplied policy.
  (check-rgba-close (vertex-color-lerp black white 1/2)
                    (rgba-color-lerp (resolve-color black animate-light-theme)
                                     (resolve-color white animate-light-theme)
                                     1/2))
  (define translucent-red (color-with-alpha pure-red 1/4))
  (define opaque-blue pure-blue)
  (check-rgba-close (vertex-color-lerp translucent-red opaque-blue 1/2)
                    (rgba-color-lerp (resolve-color translucent-red animate-light-theme)
                                     (resolve-color opaque-blue animate-light-theme)
                                     1/2))
  (define token-midpoint (vertex-color-lerp aqua-c red-c 1/2))
  (for ([theme (in-list (list animate-light-theme animate-dark-theme))])
    (check-rgba-close (resolve-color token-midpoint theme)
                      (rgba-color-lerp (resolve-color aqua-c theme)
                                       (resolve-color red-c theme)
                                       1/2)))
  (define source
    (mesh3d #:id 'semantic-cut
            #:vertices (vector (vec3 -1 0 0) (vec3 1 -1 0) (vec3 1 1 0))
            #:triangles (vector (vector 0 1 2))
            #:colors (vector aqua-c red-c blue-c)))
  (define cut
    (slice-mesh3d source (plane3 origin3 x-axis3) #:keep 'positive))
  (check-true
   (for/or ([color (in-vector (mesh3d-colors cut))])
     (color-expression? color)))
  ;; The exact authoring expressions remain resolvable only at the later
  ;; render boundary; cutting does not bake the current default theme.
  (check-not-exn
   (lambda ()
     (for ([color (in-vector (mesh3d-colors cut))])
       (resolve-color color animate-dark-theme)))))
