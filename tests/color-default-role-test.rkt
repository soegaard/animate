#lang racket/base

;;;
;;; Semantic Default Role Tests
;;;

(require rackunit
         "../main.rkt"
         "../3d.rkt"
         "../colors.rkt")

(module+ test
  ;; Readability defaults retain roles in the authoring model; they do not
  ;; depend on a mutable current theme at construction time.
  (check-eq? (camera-background (make-camera)) theme-background)
  (check-eq? (text-visual-color (plain-text "x" #:id 'text)) theme-foreground)
  (define coordinate-axes (axes #:id 'axes))
  (check-eq? (axes-visual-stroke coordinate-axes) theme-axis)
  (check-eq? (visual-stroke-color
              (axes-grid-lines coordinate-axes #:id 'grid))
             theme-grid)
  (check-eq? (text-visual-color
              (car (axes-number-labels coordinate-axes #:id-prefix 'label)))
             theme-foreground)
  (check-eq? (visual-stroke-color (circle #:id 'circle)) theme-axis)
  (check-eq? (visual-stroke-color (rectangle #:id 'rectangle)) theme-axis)
  (check-eq? (visual-stroke-color (line (vec2 -1 0) (vec2 1 0) #:id 'line))
             theme-axis)
  (check-eq? (visual-stroke-color
              (polygon (list (vec2 -1 -1) (vec2 1 -1) (vec2 0 1)) #:id 'polygon))
             theme-axis)
  (check-eq? (arrow-visual-stroke
              (arrow (vec2 -1 0) (vec2 1 0) #:id 'arrow))
             theme-axis)
  (check-eq? (visual-stroke-color
              (angle-marker (vec2 1 0) origin (vec2 0 1) #:id 'angle))
             theme-axis)

  ;; Generic spatial constructors use surface and edge roles while preserving
  ;; their numerical geometry exactly.
  (define cube (cube3d 2 #:id 'cube))
  (check-eq? (material3d-color (mesh3d-material cube)) theme-surface)
  (check-eq? (mesh3d-wireframe-color cube) theme-surface-edge)
  (define viewport (view3d (list cube) #:id 'world))
  (check-eq? (view3d-background viewport) theme-background)
  (define vertices-before (mesh3d-vertices cube))
  (void (resolve-color (material3d-color (mesh3d-material cube)) animate-light-theme))
  (void (resolve-color (material3d-color (mesh3d-material cube)) animate-dark-theme))
  (check-equal? (mesh3d-vertices cube) vertices-before)

  ;; Explicit literals remain deliberately theme-independent.
  (define branded (plain-text "brand" #:id 'brand #:color pure-blue))
  (check-eq? (text-visual-color branded) pure-blue)
  (check-equal? (resolve-color (text-visual-color branded) animate-light-theme)
                (resolve-color (text-visual-color branded) animate-dark-theme))
  (define explicit-black-line
    (line (vec2 -1 0) (vec2 1 0) #:id 'black-line #:stroke "black"))
  (check-equal? (resolve-color (visual-stroke-color explicit-black-line)
                               animate-light-theme)
                (resolve-color (visual-stroke-color explicit-black-line)
                               animate-dark-theme))
  (check-not-equal? (resolve-color theme-foreground animate-light-theme)
                    (resolve-color theme-foreground animate-dark-theme)))
