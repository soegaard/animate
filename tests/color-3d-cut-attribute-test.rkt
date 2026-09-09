#lang racket/base

;;; Semantic colour attributes survive generated cut vertices

(require rackunit
         "../3d.rkt"
         "../colors.rkt")

(module+ test
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
