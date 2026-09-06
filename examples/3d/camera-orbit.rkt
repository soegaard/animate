#lang racket/base

;;; SCENE-3D-D: Deterministic Cube and Camera Orbit

;; A cube and its camera are both ordinary finite Scene requests.  Rendering
;; frame 90 directly therefore produces the same value as reaching it through
;; frames 0 through 89; neither request stores an integration history.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

;; Each physical cube corner occurs once for each incident face.  That lets
;; this diagnostic example give every face a stable, locally attached colour:
;; a camera orbit can then never make several faces look like one flat polygon
;; merely because their lighting happens to match.  The geometry is still the
;; same closed unit cube, with two consistently wound triangles per face.
(define cube-vertices
  (vector
   ;; +z
   (vec3 -1 -1 1) (vec3 1 -1 1) (vec3 1 1 1) (vec3 -1 1 1)
   ;; -z
   (vec3 -1 -1 -1) (vec3 1 1 -1) (vec3 1 -1 -1) (vec3 -1 1 -1)
   ;; -x
   (vec3 -1 -1 -1) (vec3 -1 -1 1) (vec3 -1 1 1) (vec3 -1 1 -1)
   ;; +x
   (vec3 1 -1 -1) (vec3 1 1 -1) (vec3 1 1 1) (vec3 1 -1 1)
   ;; +y
   (vec3 -1 1 -1) (vec3 -1 1 1) (vec3 1 1 1) (vec3 1 1 -1)
   ;; -y
   (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 1 -1 1) (vec3 -1 -1 1)))

(define cube-triangles
  (vector (vector 0 1 2) (vector 0 2 3)
          (vector 4 5 6) (vector 4 7 5)
          (vector 8 9 10) (vector 8 10 11)
          (vector 12 13 14) (vector 12 14 15)
          (vector 16 17 18) (vector 16 18 19)
          (vector 20 21 22) (vector 20 22 23)))

(define cube-colors
  (vector "lightskyblue" "lightskyblue" "lightskyblue" "lightskyblue"
          "midnightblue" "midnightblue" "midnightblue" "midnightblue"
          "slateblue" "slateblue" "slateblue" "slateblue"
          "cornflowerblue" "cornflowerblue" "cornflowerblue" "cornflowerblue"
          "royalblue" "royalblue" "royalblue" "royalblue"
          "steelblue" "steelblue" "steelblue" "steelblue"))

(define (make-demo-scene)
  (define world
    (view3d
     (list
      (mesh3d #:id 'cube #:vertices cube-vertices #:triangles cube-triangles
              #:colors cube-colors
              ;; This probe is about geometry and camera motion, not a lighting
              ;; study.  Face colours make its orientation legible at every
              ;; orbit phase, including the otherwise ambiguous corner-on view.
              #:material (material3d #:color "cornflowerblue" #:shading 'unlit)))
     #:id 'world #:center (vec2 2 -1/3) #:width 6 #:height 4
     #:camera (perspective-camera3d #:position (vec3 4 3 7) #:look-at origin3
                                    #:vertical-field-of-view (/ pi 5))
     #:background "aliceblue" #:render-mode 'opaque))
  ;; This stays a regular, crisp formula Visual.  Its one declared source unit
  ;; remains selectable in the existing formula inspector while the camera
  ;; moves independently.
  (define matrix-source
    "R_y(\\theta) = \\left[\\begin{array}{cc} \\cos\\theta & \\sin\\theta \\\\ -\\sin\\theta & \\cos\\theta \\end{array}\\right]")
  (define matrix
    (visual-with-position
     (math-tex #:id 'matrix #:font-size 1/3 #:source-map 'declared
               #:parts (list (source-part 'rotation-matrix matrix-source))
               matrix-source)
     (vec2 -4 -1/3)))
  (define title
    (plain-text "SCENE-3D-D: spatial and camera animation"
                #:id 'title #:center (vec2 0 15/4)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define caption
    (plain-text "The cube rotates locally while the immutable camera orbits."
                #:id 'caption #:center (vec2 0 -29/10)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene) world title matrix caption)
   (rotate3d-by '(world cube) (axis-angle y-axis3 (* 2 pi)))
   (camera3d-orbit-by 'world #:azimuth (* 2 pi) #:elevation (/ pi 12))
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "camera-orbit.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
