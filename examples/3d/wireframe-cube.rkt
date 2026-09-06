#lang racket/base

;;;
;;; SCENE-3D-B: Perspective Wireframe Cube
;;;

;; A `view3d` is an ordinary 2D Visual in the established Scene timeline.  It
;; owns a separate immutable spatial tree, which the B-stage renderer projects
;; as clipped wireframe segments.  The formula and title remain ordinary 2D
;; Visuals deliberately: they demonstrate that no competing `scene3d` exists.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide cube-vertices
         cube-edges
         make-wireframe-cube
         make-demo-scene)


;;;
;;; Reusable Cube Geometry
;;;

(define cube-vertices
  (vector (vec3 -1 -1 -1) (vec3 1 -1 -1)
          (vec3 1 1 -1) (vec3 -1 1 -1)
          (vec3 -1 -1 1) (vec3 1 -1 1)
          (vec3 1 1 1) (vec3 -1 1 1)))

(define cube-edges
  (vector (vector 0 1) (vector 1 2) (vector 2 3) (vector 3 0)
          (vector 4 5) (vector 5 6) (vector 6 7) (vector 7 4)
          (vector 0 4) (vector 1 5) (vector 2 6) (vector 3 7)))

; make-wireframe-cube : symbol? [#:transform transform3?]
;                       [#:color color-spec?] -> mesh3d?
;;   Creates the example's deterministic twelve-edge cube.
(define (make-wireframe-cube id
                             #:transform [transform identity-transform3]
                             #:color [color "navy"])
  (mesh3d #:id id
          #:vertices cube-vertices
          #:edges cube-edges
          #:transform transform
          #:wireframe-color color
          #:wireframe-width 3))


;;;
;;; Scene
;;;

; make-demo-scene : -> scene?
;;   Places a perspective wireframe cube below an ordinary 2D formula.
(define (make-demo-scene)
  (define camera
    (perspective-camera3d
     #:position (vec3 4 3 7)
     #:look-at origin3
     #:vertical-field-of-view (/ pi 5)
     #:near 1/10
     #:far 30))
  (define cube
    (make-wireframe-cube
     'cube
     #:transform
     (make-transform3 #:rotation (axis-angle (vec3 1 1 0) (/ pi 9)))))
  (define world
    (view3d (list cube)
            #:id 'world
            #:center (vec2 0 -1/4)
            #:width 6
            #:height 4
            #:camera camera
            #:background "aliceblue"))
  (define title
    (plain-text "SCENE-3D-B: a wireframe cube in an ordinary Scene"
                #:id 'title
                #:center (vec2 0 15/4)
                #:font-size 1/3
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define formula
    (latex-formula "x^2+y^2+z^2=1"
                   #:id 'formula
                   #:center (vec2 0 27/10)
                   #:font-size 1/2))
  (scene-wait (scene-add (make-scene) world title formula) 4))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "wireframe-cube.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define scene (make-demo-scene))
  (define paths (render-frames! scene output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
