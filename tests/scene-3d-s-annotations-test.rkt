#lang racket/base

;;; SCENE-3D-S: fixed-structure spatial annotation relations.

(require rackunit
         "../3d.rkt"
         "../main.rkt")

(define (anchor-mesh id point)
  (mesh3d #:id id #:vertices (vector origin3)
          #:transform (make-transform3 #:translation point)))

(define source-view
  (view3d
   (list (anchor-mesh 'A origin3)
         (anchor-mesh 'B (vec3 0 0 2))
         (anchor-mesh 'C (vec3 2 0 0))
         (anchor-mesh 'D (vec3 0 2 0))
         (distance-dimension3d '(A) '(B) #:id 'dimension #:offset (vec3 1/2 0 0))
         (angle-marker3d '(C) '(A) '(D) #:id 'angle #:radius 1/3 #:samples 4)
         (right-angle-marker3d '(C) '(A) '(D) #:id 'right-angle #:size 1/3)
         (dihedral-angle3d '(A) '(B) '(C) '(D) #:id 'dihedral #:radius 1/3 #:samples 4)
         (normal-marker3d '(A) z-axis3 #:id 'normal #:length 1/2)
         (coordinate-tripod3d '(A) #:id 'tripod #:length 1/2))
   #:id 'world
   #:camera (perspective-camera3d #:position (vec3 4 4 6) #:look-at (vec3 0 0 1))
   #:render-mode 'wireframe))

(define (resolved-view scene [time 0])
  (scene-state-resolved-ref (scene-sample scene time) 'world))

(module+ test
  (define view (resolved-view (scene-add (make-scene) source-view)))
  ;; Every annotation is a `fixed` relation, so readers can rely on direct
  ;; descendant paths before or after target motion.
  (for ([id (in-list '(dimension angle right-angle dihedral normal tripod))])
    (check-eq? (spatial-relation-structure
                (view3d-spatial-ref source-view (list 'world id)))
               'fixed))
  (for ([path (in-list
               '((world dimension dimension-extension-from)
                 (world dimension dimension-extension-to)
                 (world dimension dimension-dimension)
                 (world dimension dimension-from-tip)
                 (world dimension dimension-to-tip)
                 (world angle angle-first-radius)
                 (world angle angle-arc)
                 (world angle angle-second-radius)
                 (world right-angle right-angle-first-leg)
                 (world right-angle right-angle-corner)
                 (world right-angle right-angle-second-leg)
                 (world dihedral dihedral-axis)
                 (world dihedral dihedral-first-radius)
                 (world dihedral dihedral-arc)
                 (world dihedral dihedral-second-radius)
                 (world normal normal-shaft)
                 (world normal normal-head)
                 (world tripod tripod-x-shaft)
                 (world tripod tripod-x-tip)
                 (world tripod tripod-y-shaft)
                 (world tripod tripod-y-tip)
                 (world tripod tripod-z-shaft)
                 (world tripod tripod-z-tip)))])
    (check-true (spatial-visual? (view3d-spatial-ref view path))))
  ;; The geometry is derived afresh from its named targets rather than captured
  ;; at definition time.
  (define moving
    (scene-play
     (scene-add (make-scene) source-view)
     (move3d-to '(world B) (vec3 0 0 4))
     #:duration 1))
  (define moved-dimension
    (view3d-spatial-ref (resolved-view moving 1) '(world dimension dimension-dimension)))
  (check-equal? (vector-ref (curve3d-points moved-dimension) 1) (vec3 1/2 0 4))
  (check-exn exn:fail:contract?
             (lambda ()
               (resolved-view
                (scene-add
                 (make-scene)
                 (view3d (list (anchor-mesh 'A origin3)
                               (anchor-mesh 'D (vec3 0 1 0))
                               (angle-marker3d '(A) '(A) '(D) #:id 'bad))
                         #:id 'world))))))
