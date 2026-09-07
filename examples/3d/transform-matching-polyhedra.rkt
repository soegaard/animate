#lang racket/base

;;; SCENE-3D-U: Topology-safe Mesh Matching

;; The first clip has a complete semantic correspondence, so each source
;; vertex travels to one destination vertex while the original triangle index
;; array remains in use.  The second deliberately changes topology, so it uses
;; an explicit cross-fade instead of fabricating a vertex morph.

(require racket/cmdline
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define source-tetrahedron
  (mesh3d
   #:id 'solid
   #:vertices (vector (vec3 0 0 6/5)
                      (vec3 -1 -4/5 -3/5)
                      (vec3 1 -4/5 -3/5)
                      (vec3 0 1 -3/5))
   #:triangles (vector (vector 0 2 1) (vector 0 1 3)
                       (vector 0 3 2) (vector 1 2 3))
   #:vertex-ids '#(peak west east north)
   #:face-ids '#(front left right base)
   #:colors '#("gold" "#4c78a8" "#e45756" "#54a24b")
   #:material (material3d #:color "cornflowerblue" #:shading 'smooth
                          #:double-sided? #t)
   #:wireframe-color "midnightblue" #:wireframe-width 2
   #:transform (make-transform3 #:translation (vec3 -9/5 0 0))))

;; The index and semantic-part orders differ.  The semantic plan still gives
;; each source vertex an unambiguous destination, so this remains a genuine
;; same-topology transform rather than an index-order coincidence.
(define stretched-tetrahedron
  (mesh3d
   #:id 'solid
   #:vertices (vector (vec3 -1 -1 -4/5)
                      (vec3 0 1 7/5)
                      (vec3 0 5/4 -4/5)
                      (vec3 1 -1 -4/5))
   #:triangles (vector (vector 1 3 0) (vector 1 0 2)
                       (vector 1 2 3) (vector 0 3 2))
   #:vertex-ids '#(west peak north east)
   #:face-ids '#(front left right base)
   #:colors '#("#4c78a8" "gold" "#54a24b" "#e45756")
   #:material (material3d #:color "mediumorchid" #:shading 'smooth
                          #:double-sided? #t)
   #:wireframe-color "purple" #:wireframe-width 2
   #:transform (make-transform3 #:translation (vec3 9/5 0 0))))

;; An octahedron has a different vertex and triangle topology.  Giving it the
;; same *spatial* identity lets it replace the target at the exact endpoint;
;; the cross-fade's temporary children are never part of that endpoint scene.
(define octahedron
  (mesh3d
   #:id 'solid
   #:vertices (vector (vec3 0 0 7/5) (vec3 0 0 -7/5)
                      (vec3 -6/5 0 0) (vec3 0 -6/5 0)
                      (vec3 6/5 0 0) (vec3 0 6/5 0))
   #:triangles (vector (vector 0 2 3) (vector 0 3 4)
                       (vector 0 4 5) (vector 0 5 2)
                       (vector 1 3 2) (vector 1 4 3)
                       (vector 1 5 4) (vector 1 2 5))
   #:material (material3d #:color "tomato" #:shading 'smooth
                          #:double-sided? #t)
   #:wireframe-color "firebrick" #:wireframe-width 2))

(define (make-demo-scene)
  (define world
    (view3d (list source-tetrahedron)
            #:id 'world #:center origin #:width 9 #:height 8
            #:camera (perspective-camera3d #:position (vec3 0 2 10)
                                          #:look-at origin3)
            #:background "aliceblue" #:render-mode 'opaque))
  (define title
    (plain-text "SCENE-3D-U: topology-safe mesh matching"
                #:id 'title #:center (vec2 0 34/10) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define caption
    (plain-text "Semantic vertex match, then an explicit topology cross-fade."
                #:id 'caption #:center (vec2 0 -31/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
  (define planned
    (prepare-mesh-correspondence3d source-tetrahedron stretched-tetrahedron))
  (define deformed
    (scene-play
     (scene-add (make-scene) world title caption)
     (transform-matching-mesh3d
      '(world solid) stretched-tetrahedron #:correspondence planned
      #:route (spatial-bezier-route3d (vec3 -1 2 0) (vec3 1 -2 0)))
     (camera3d-orbit-by 'world #:center origin3 #:azimuth 1/3 #:elevation 1/12)
     #:duration 3))
  (scene-play
   deformed
   (transform-matching-mesh3d '(world solid) octahedron #:topology 'cross-fade
                              #:route (spatial-line-route3d))
   (camera3d-orbit-by 'world #:center origin3 #:azimuth 1/3 #:elevation -1/12)
   #:duration 3))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "transform-matching-polyhedra.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
