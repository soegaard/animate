#lang racket/base

;;;
;;; SCENE-3D-U Matching Animation Tests
;;;

(require rackunit
         (only-in racket/math pi)
         "../3d.rkt"
         "../main.rkt")

(define source
  (mesh3d
   #:id 'shape
   #:vertices (vector origin3 (vec3 2 0 0) (vec3 0 2 0))
   #:triangles (vector (vector 0 1 2))
   #:vertex-ids '#(origin east north)
   #:face-ids '#(face)
   #:colors '#("tomato" "gold" "steelblue")
   #:transform (make-transform3 #:translation (vec3 -2 0 0))))

;; Reordered local indexes make the correspondence real rather than merely a
;; convenient identity map.  The destination preserves `shape`, because that
;; is the stable path identity in the scene.
(define destination
  (mesh3d
   #:id 'shape
   #:vertices (vector (vec3 4 0 0) (vec3 1 3 0) (vec3 1 0 0))
   #:triangles (vector (vector 2 0 1))
   #:vertex-ids '#(east north origin)
   #:face-ids '#(face)
   #:colors '#("gold" "steelblue" "tomato")
   #:transform (make-transform3 #:translation (vec3 2 0 0))))

(define source-scene
  (scene-add (make-scene) (view3d (list source) #:id 'world)))

(define (mesh-at scene time)
  (view3d-spatial-ref (scene-state-ref (scene-sample scene time) 'world)
                      '(world shape)))

(module+ test
  (define plan (prepare-mesh-correspondence3d source destination))
  (check-equal? (mesh-correspondence3d-vertex-map plan) '#(2 0 1))
  (check-true (mesh3d-correspondence-compatible? source destination plan))

  ;; Samplers retain exact endpoint object values, while the interior carries
  ;; source index arrays and correspondence-directed geometry.
  (check-eq? (mesh3d-matching-sample source destination plan
                                      (spatial-line-route3d) 0)
             source)
  (check-eq? (mesh3d-matching-sample source destination plan
                                      (spatial-line-route3d) 1)
             destination)
  (define halfway
    (mesh3d-matching-sample source destination plan (spatial-line-route3d) 1/2))
  (check-equal? (mesh3d-triangles halfway) (mesh3d-triangles source))
  (check-equal? (vector-ref (mesh3d-vertices halfway) 0) (vec3 1/2 0 0))
  (check-equal? (transform3-translation (spatial-transform halfway)) origin3)

  ;; The scene request installs the exact same endpoint values even after an
  ;; arbitrary middle sample, proving no incremental frame state is involved.
  (define matched
    (scene-play source-scene
                (transform-matching-mesh3d '(world shape) destination
                                           #:correspondence plan)
                #:duration 1))
  (check-eq? (mesh-at matched 0) source)
  (check-equal? (mesh-at matched 1) destination)
  (check-true (mesh3d? (mesh-at matched 1/2)))
  (check-equal? (mesh3d-triangles (mesh-at matched 1/2))
                (mesh3d-triangles source))

  ;; A topology change needs an explicit cross-fade.  Its middle sample owns
  ;; two legal mesh arrays beneath a temporary wrapper; neither is ever
  ;; interpolated into the other.
  (define changed-topology
    (mesh3d #:id 'shape
            #:vertices (vector origin3 (vec3 2 0 0) (vec3 0 2 0) (vec3 1 1 2))
            #:triangles (vector (vector 0 1 3) (vector 1 2 3))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play source-scene
                           (transform-matching-mesh3d '(world shape)
                                                      changed-topology)
                           #:duration 1)))
  (define faded
    (scene-play source-scene
                (transform-matching-mesh3d '(world shape) changed-topology
                                           #:topology 'cross-fade)
                #:duration 1))
  (check-true (group3d? (mesh-at faded 1/2)))
  (check-equal? (length (group3d-children (mesh-at faded 1/2))) 2)
  (check-equal? (mesh-at faded 1) changed-topology)

  ;; Routes alter only the reference translation and retain exact endpoints.
  (define arc (spatial-arc-route3d #:axis z-axis3 #:angle (/ pi 2)))
  (check-eq? (spatial-route3d-sample arc origin3 (vec3 2 0 0) 0) origin3)
  (check-equal? (spatial-route3d-sample arc origin3 (vec3 2 0 0) 1)
                (vec3 2 0 0))
  (check-true (not (zero? (vec3-y (spatial-route3d-sample arc origin3
                                                          (vec3 2 0 0) 1/2)))))
  (check-exn exn:fail:contract?
             (lambda ()
               (spatial-route3d-sample
                arc origin3 (vec3 0 0 2) 1/2))))
