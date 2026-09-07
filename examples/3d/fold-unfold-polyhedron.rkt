#lang racket/base

;;; SCENE-3D-U: Cube Net Hinge Rotations

;; The cube is split into six independent spatial children by
;; `polyhedron-net3d-group`.  The unfold/fold clips therefore move whole faces
;; around their shared hinges; no triangle or vertex correspondence is used as
;; an animation shortcut.

(require racket/cmdline
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define cube-vertices
  (vector (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 1 1 -1) (vec3 -1 1 -1)
          (vec3 -1 -1 1) (vec3 1 -1 1) (vec3 1 1 1) (vec3 -1 1 1)))

;; Each pair is an outward, coplanar mathematical face.  Shared vertices are
;; essential here: they give the topology layer its actual cube hinges.
(define cube-triangles
  (vector (vector 4 5 6) (vector 4 6 7)       ; +z, the net root
          (vector 0 2 1) (vector 0 3 2)       ; -z
          (vector 0 4 7) (vector 0 7 3)       ; -x
          (vector 1 2 6) (vector 1 6 5)       ; +x
          (vector 3 7 6) (vector 3 6 2)       ; +y
          (vector 0 1 5) (vector 0 5 4)))     ; -y

(define face-materials
  (for/vector ([color (in-vector
                       (vector "#4c78a8" "#f58518" "#54a24b"
                               "#e45756" "#b279a2" "#eeca3b"))])
    (material3d #:color color #:shading 'flat)))

(define (make-demo-scene)
  (define source
    (mesh3d #:id 'cube-source
            #:vertices cube-vertices #:triangles cube-triangles
            #:material (material3d #:color "lightskyblue" #:shading 'flat)
            #:wireframe-color "midnightblue" #:wireframe-width 3))
  (define complex (polyhedral-complex3d source))
  (define net (prepare-polyhedron-net3d complex #:strategy 'minimum-overlap))
  (define world
    (view3d
     (list (polyhedron-net3d-group complex net #:id 'net
                                   #:face-materials face-materials))
     #:id 'world #:center origin #:width 8 #:height 9
     #:camera (orthographic-camera3d #:position (vec3 4 3 9)
                                    #:look-at origin3 #:vertical-size 9)
     #:background "aliceblue" #:render-mode 'opaque))
  (define title
    (plain-text "SCENE-3D-U: cube net hinge rotations"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define caption
    (plain-text "Faces stay joined along their hinges at every sampled frame."
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
  (define unfolded
    (scene-play (scene-add (make-scene) world title caption)
                (unfold-polyhedron3d '(world net) net)
                (camera3d-move-to 'world (vec3 0 0 10))
                (camera3d-look-at-to 'world origin3)
                #:duration 3))
  (scene-play unfolded
              (fold-polyhedron3d '(world net) net)
              (camera3d-move-to 'world (vec3 4 3 9))
              (camera3d-look-at-to 'world origin3)
              #:duration 3))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "fold-unfold-polyhedron.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
