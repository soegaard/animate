#lang racket/base

;;;
;;; SCENE-3D-E Render Integration Tests
;;;

(require racket/class
         (only-in racket/draw bitmap%)
         rackunit
         (only-in pict pict->bitmap pict?)
         "../3d.rkt"
         "../main.rkt")

(define (point id position)
  (mesh3d #:id id #:vertices (vector origin3)
          #:transform (make-transform3 #:translation position)))

(define world
  (view3d
   (list (point 'P (vec3 -1 0 0))
         (point 'Q (vec3 1 0 0))
         (segment-between3d '(P) '(Q) #:id 'distance #:color "tomato")
         (arrow-between3d '(P) '(Q) #:id 'arrow #:color "forestgreen")
         (plane-through3d '(P) '(Q) '(R) #:id 'plane #:color "lightskyblue")
         (point 'R (vec3 0 1 0))
         (normal-at3d '(R) z-axis3 #:id 'normal #:color "darkmagenta"))
   #:id 'world #:width 7 #:height 4
   #:camera (perspective-camera3d #:position (vec3 3 2 7) #:look-at origin3)
   #:render-mode 'wireframe))

(define labels
  (list
   (follow-projected-spatial (plain-text "P" #:id 'p-label #:font-size 1/3)
                             #:view 'world #:target '(P) #:offset (vec2 -10 8))
   (follow-projected-point (plain-text "O" #:id 'o-label #:font-size 1/3)
                           #:view 'world #:point origin3 #:offset (vec2 10 10))))

(module+ test
  ;; All early built-ins resolve to renderer-understood mesh trees, then the
  ;; two projected labels paint as normal 2D content over that viewport.
  (define scene
    (scene-wait
     (for/fold ([state (make-scene)])
               ([visual (in-list (cons world labels))])
       (scene-add state visual))
     1))
  (define rendered
    (scene->pict scene 0
                 #:camera (make-camera #:width 240 #:height 135 #:world-width 10)))
  (check-true (pict? rendered))
  (check-true (is-a? (pict->bitmap rendered) bitmap%)))
