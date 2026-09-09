#lang racket/base

;; Surface topology is sampled once. The material and edge roles resolve only
;; at rendering time, so rendering under another theme does not resample it.

(require animate
         animate/3d
         animate/colors
         "../private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define surface
    (parametric-surface3d
     (lambda (u v) (vec3 u v (/ (+ (* u u) (* v v)) 3)))
     #:id 'surface #:resolution '(25 25)
     #:material (material3d #:color theme-surface #:shading 'smooth)
     #:wireframe-color theme-surface-edge))
  (define world
    (view3d (list surface) #:id 'world #:width 6 #:height 4
            #:background theme-background))
  (define title
    (plain-text "Themed 3D surface" #:id 'title #:center (vec2 0 3)
                #:font-size 1/3 #:font-weight 'bold #:color theme-foreground))
  (scene-wait (scene-add (make-scene) title world) 1))

(module+ main
  (run-demo "colors/themed-surface.rkt" make-demo-scene))
