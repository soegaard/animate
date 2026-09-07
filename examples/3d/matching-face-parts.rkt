#lang racket/base

;;; SCENE-3D-U: Explicit Spatial Face-Part Matching

;; Three direct mesh children are intentionally named as mathematical faces.
;; Their destination names differ, so the request receives an explicit
;; spatial-correspondence3d list. Each face follows its own arc while its mesh
;; data stays topology-safe; the enclosing group is exact at both endpoints.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define local-triangle
  (vector (vec3 -4/5 -2/3 0) (vec3 4/5 -2/3 0) (vec3 0 3/4 0)))

(define (face id color transform)
  (mesh3d #:id id #:vertices local-triangle #:triangles (vector (vector 0 1 2))
          #:vertex-ids '#(left right peak) #:face-ids '#(panel)
          #:colors (vector color color color)
          #:material (material3d #:color color #:shading 'smooth #:double-sided? #t)
          #:wireframe-color "midnightblue" #:wireframe-width 2
          #:transform transform))

(define source-faces
  (group3d
   (list
    (face 'front "#4c78a8" (make-transform3 #:translation (vec3 0 -1/3 1/2)))
    (face 'left "#f58518"
          (make-transform3 #:translation (vec3 -3/5 0 0)
                           #:rotation (axis-angle y-axis3 (- (/ pi 3)))))
    (face 'right "#54a24b"
          (make-transform3 #:translation (vec3 3/5 0 0)
                           #:rotation (axis-angle y-axis3 (/ pi 3)))))
   #:id 'polyhedron))

(define destination-faces
  (group3d
   (list
    (face 'front-flat "#4c78a8" (make-transform3 #:translation (vec3 0 3/2 0)))
    (face 'left-flat "#f58518" (make-transform3 #:translation (vec3 -9/5 -1 0)))
    (face 'right-flat "#54a24b" (make-transform3 #:translation (vec3 9/5 -1 0))))
   #:id 'polyhedron))

(define face-matches
  (list
   (spatial-correspondence3d 'front 'front-flat 'explicit 'face-parts
                             (spatial-line-route3d) (hasheq))
   (spatial-correspondence3d 'left 'left-flat 'explicit 'face-parts
                             (spatial-arc-route3d #:axis z-axis3 #:angle (/ pi 3))
                             (hasheq))
   (spatial-correspondence3d 'right 'right-flat 'explicit 'face-parts
                             (spatial-arc-route3d #:axis z-axis3 #:angle (- (/ pi 3)))
                             (hasheq))))

(define (make-demo-scene)
  (define world
    (view3d (list source-faces) #:id 'world #:width 9 #:height 8
            #:camera (orthographic-camera3d #:position (vec3 0 0 10)
                                           #:look-at origin3 #:vertical-size 7)
            #:background "aliceblue" #:render-mode 'opaque))
  (define title
    (plain-text "SCENE-3D-U: explicit face-part matching"
                #:id 'title #:center (vec2 0 34/10) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define caption
    (plain-text "Named faces take independent routes; no mesh topology is guessed."
                #:id 'caption #:center (vec2 0 -31/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene) world title caption)
   (transform-matching-spatial '(world polyhedron) destination-faces
                               #:matches face-matches)
   #:duration 4))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "matching-face-parts.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
