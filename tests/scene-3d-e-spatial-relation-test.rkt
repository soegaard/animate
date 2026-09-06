#lang racket/base

;;;
;;; SCENE-3D-E Spatial Relation Tests
;;;

(require rackunit
         "../3d.rkt"
         "../main.rkt")

(define (point-mesh id point)
  (mesh3d #:id id
          #:vertices (vector origin3)
          #:transform (make-transform3 #:translation point)))

(define point-a (point-mesh 'A (vec3 -1 0 0)))
(define point-b (point-mesh 'B (vec3 1 0 0)))
(define segment
  (segment-between3d '(A) '(B) #:id 'segment #:color "tomato"))
(define source-view
  (view3d (list point-a point-b segment)
          #:id 'world
          #:camera (perspective-camera3d #:position (vec3 0 0 6)
                                         #:look-at origin3)
          #:render-mode 'wireframe))

(define (resolved-view scene time)
  (scene-state-resolved-ref (scene-sample scene time) 'world))

(module+ test
  ;; A live segment reads current spatial origins, not endpoints captured at
  ;; construction. Moving B changes only the target input sampled at that time.
  (define moving-scene
    (scene-play
     (scene-add (make-scene) source-view)
     (move3d-to '(world B) (vec3 3 0 0))
     #:duration 2))
  (define midpoint-view (resolved-view moving-scene 1))
  (define midpoint-segment
    (view3d-spatial-ref midpoint-view '(world segment)))
  (check-equal? (vector-ref (mesh3d-vertices midpoint-segment) 0) (vec3 -1 0 0))
  (check-equal? (vector-ref (mesh3d-vertices midpoint-segment) 1) (vec3 2 0 0))

  ;; A fixed relation can publish a stable descendant. A second relation reads
  ;; that concrete descendant, proving spatial relation-to-relation dependency.
  (define anchor-template
    (group3d (list (point-mesh 'anchor origin3)) #:id 'midpoint))
  (define midpoint-relation
    (spatial-relation
     anchor-template
     #:structure 'fixed
     #:depends-on (list (spatial-visual-dependency '(A))
                        (spatial-visual-dependency '(B)))
     (lambda (context _template)
       (define a (spatial-relation-context-spatial-position context '(A)))
       (define b (spatial-relation-context-spatial-position context '(B)))
       (group3d
        (list (mesh3d #:id 'anchor
                      #:vertices (vector origin3)
                      #:transform
                      (make-transform3 #:translation (vec3-scale 1/2 (vec3+ a b)))))
        #:id 'midpoint))))
  (define follower-template (point-mesh 'follower origin3))
  (define follower
    (spatial-relation
     follower-template
     #:depends-on (list (spatial-visual-dependency '(midpoint anchor)))
     (lambda (context _template)
       (mesh3d #:id 'follower
               #:vertices (vector origin3)
               #:transform
               (make-transform3
                #:translation
                (spatial-relation-context-spatial-position
                 context '(midpoint anchor)))))))
  (define relation-view
    (view3d (list point-a point-b midpoint-relation follower) #:id 'world))
  (define completed
    (resolved-view (scene-add (make-scene) relation-view) 0))
  (check-equal?
   (spatial-position (view3d-spatial-ref completed '(world midpoint anchor)))
   origin3)
  (check-equal?
   (spatial-position (view3d-spatial-ref completed '(world follower)))
   origin3)

  ;; An outer spatial animation is an envelope around current relation output,
  ;; rather than a request to mutate the relation's own resolver closure.
  (define translated
    (scene-play
     (scene-add (make-scene) source-view)
     (move3d-to '(world segment) (vec3 0 2 0))
     #:duration 1))
  (define translated-segment
    (view3d-spatial-ref (resolved-view translated 1) '(world segment)))
  (check-equal? (spatial-position translated-segment) (vec3 0 2 0))

  ;; Generic functions are intentionally process-local unless authors own a
  ;; stable cache key. This makes renderer cache behavior inspectable.
  (check-eq? (spatial-relation-cacheability segment) 'disabled)
  (define keyed
    (spatial-relation
     (point-mesh 'keyed origin3)
     #:cache-key '(example keyed v1)
     (lambda (_context template) template)))
  (check-eq? (spatial-relation-cacheability keyed) 'explicit-key)
  (check-equal? (spatial-relation-cache-key keyed) '(example keyed v1)))
