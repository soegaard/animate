#lang racket/base

;;;
;;; SCENE-3D-B Viewport Model Tests
;;;

(require rackunit
         "../3d.rkt"
         "../main.rkt")

(define wire
  (mesh3d #:id 'wire
          #:vertices (vector (vec3 -1 0 0) (vec3 1 0 0))
          #:edges (vector (vector 0 1))))

(module+ test
  (define left (view3d (list wire) #:id 'left #:center (vec2 -3 0)
                       #:width 4 #:height 3))
  (define right (view3d (list wire) #:id 'right #:center (vec2 3 0)
                        #:width 4 #:height 3))
  (check-true (visual? left))
  (check-true (affine-visual? left))
  (check-true (opacity-visual? left))
  (check-equal? (visual-position left) (vec2 -3 0))
  (check-false (visual-container? left))
  ;; A view3d is nevertheless an ordinary measurable 2D Visual. The spatial
  ;; children stay behind its explicit boundary rather than entering layout.
  (check-= (layout-box-width (visual-layout-box left)) 4 1/100)
  (check-= (layout-box-height (visual-layout-box left)) 3 1/100)
  (define scene (scene-add (make-scene) left right))
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order (scene-current-state scene)))
   '(left right))
  ;; Opaque triangles arrive in SCENE-3D-C without changing the 2D viewport
  ;; boundary or requiring a second scene type.
  (check-equal? (view3d-render-mode
                 (view3d (list wire) #:id 'opaque #:render-mode 'opaque))
                'opaque))
