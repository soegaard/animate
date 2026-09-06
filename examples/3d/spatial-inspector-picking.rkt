#lang racket/base

;;; SCENE-3D-L: Exact Spatial Inspection and Picking

;; This is a deliberately small mesh with an asymmetric roof.  In the preview
;; window, click any visible facet: the selection overlay shows its world AABB,
;; exact tested triangle, ray pixel, normal, and local frame.  Those markings
;; are preview diagnostics, so the rendered movie below remains clean.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/preview
         animate/render)

(provide make-demo-scene
         make-inspection-probe)

(define roof-vertices
  (vector (vec3 -2 -1 -1) (vec3 2 -1 -1) (vec3 2 1 -1) (vec3 -2 1 -1)
          (vec3 -2 -1 1) (vec3 2 -1 1) (vec3 2 1 1) (vec3 -2 1 1)
          (vec3 1/2 0 5/2)))

;; The first ten triangles form the bottom and four vertical sides of a box;
;; the top is deliberately absent because the final four triangles replace it
;; with a closed, offset pyramid roof. Every triangle is CCW when viewed from
;; outside. The named object is one immutable indexed mesh, so the preview
;; picks a deterministic triangle index rather than a transient primitive.
(define roof-triangles
  (vector (vector 0 2 1) (vector 0 3 2) ; bottom (-z)
          (vector 0 5 4) (vector 0 1 5) ; front (-y)
          (vector 1 2 6) (vector 1 6 5) ; right (+x)
          (vector 2 3 7) (vector 2 7 6) ; back (+y)
          (vector 3 0 4) (vector 3 4 7) ; left (-x)
          (vector 4 5 8)                 ; roof at -y
          (vector 5 6 8)                 ; roof at +x
          (vector 6 7 8)                 ; roof at +y
          (vector 7 4 8)))               ; roof at -x

(define roof-colors
  ;; `mesh3d` colours belong to vertices.  Shared base colours and a warm roof
  ;; peak make the selected facets legible without duplicating geometry solely
  ;; for a diagnostic illustration.
  (vector "steelblue" "cornflowerblue" "royalblue" "slateblue"
          "midnightblue" "steelblue" "cornflowerblue" "slateblue"
          "goldenrod"))

(define (make-world)
  (view3d
   (list
    (mesh3d #:id 'roof
            #:vertices roof-vertices #:triangles roof-triangles #:colors roof-colors
            #:material (material3d #:color "steelblue" #:shading 'unlit)))
   #:id 'world #:center (vec2 0 -1/4) #:width 7 #:height 9/2
   #:camera (perspective-camera3d #:position (vec3 7 5 10)
                                 #:look-at (vec3 0 0 1/2)
                                 #:vertical-field-of-view (/ pi 5))
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-inspection-probe)
  ;; The centre pixel intersects a roof-side triangle in the initial camera
  ;; pose.  This pure value is useful in a REPL or test without opening a GUI.
  (view3d-pixel-pick (make-world) 320 180 #:width 640 #:height 360))

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-3D-L: exact spatial picking"
                #:id 'title #:center (vec2 0 15/4)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define caption
    (plain-text "In preview, click a facet to inspect its path, triangle, normal, and camera ray."
                #:id 'caption #:center (vec2 0 -29/10)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene) (make-world) title caption)
   (camera3d-orbit-by 'world #:azimuth (* 2 pi) #:elevation (/ pi 18))
   #:duration 5))

(module+ main
  ;; Running this file from GRacket is the useful first experience: it opens
  ;; the spatial picker.  Supplying a frames directory retains the batch
  ;; renderer used by the reproducible-video examples.
  (define output-directory #f)
  (define output-video #f)
  (define render? #f)
  (command-line
   #:program "spatial-inspector-picking.rkt"
   #:args arguments
   (cond
     [(null? arguments) (void)]
     [(<= (length arguments) 2)
      (set! render? #t)
      (set! output-directory (car arguments))
      (when (= (length arguments) 2)
        (set! output-video (cadr arguments)))]
     [else
      (raise-user-error
       'spatial-inspector-picking.rkt
       "expected no arguments for preview, or FRAMES-DIRECTORY [MP4-FILE] for rendering")]))
  (if render?
      (let ([paths (render-frames! (make-demo-scene) output-directory #:fps 30)])
        (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
        (when output-video
          (encode-mp4! output-directory output-video #:fps 30)
          (printf "Encoded ~a\n" output-video)))
      ;; Do not wait in a Racket-level loop here: in GRacket that would occupy
      ;; the eventspace that must paint and handle the preview controls.
      (void
       (open-scene-preview (make-demo-scene)
                           #:title "Animate: 3D spatial picking"))))
