#lang racket/base

;;; SCENE-3D-T5: Poincare Section Crossings

;; The four gold points are extracted from one prepared dense orbit.  They are
;; not guessed from display samples, and the rendered curve never reevaluates
;; its original ODE field.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define orbit
  (prepare-ode-trajectory3d
   (lambda (x y _z) (vec3 (- y) x 0)) (vec3 2 0 0)
   #:time-range (cons 0 (* 4 pi)) #:step-size 1/40))

(define section-plane (plane3 origin3 x-axis3))
(define crossings (poincare-section3d orbit section-plane #:trajectory-id 'orbit))

(define orbit-curve
  (polyline3d
   (for/list ([index (in-range 321)])
     (ode-trajectory3d-position orbit (* 4 pi (/ index 320))))
   #:id 'orbit #:style (stroke3d #:color "royalblue" #:width 3)))

(define (make-demo-scene)
  (define world
    (view3d
     (list
      (coordinate-plane3d 'xy #:id 'xy #:u-range (list -5/2 5/2)
                          #:v-range (list -5/2 5/2) #:color "aliceblue")
      (axes3d #:id 'axes #:x-range (list -5/2 5/2) #:y-range (list -5/2 5/2)
              #:z-range (list -1 1)
              #:stroke-style (stroke3d #:color "lightsteelblue" #:width 1))
      orbit-curve
      (poincare-hits3d crossings #:id 'crossings
                       #:style (point-style3d #:size 12 #:color "gold")))
     #:id 'world #:center (vec2 0 0) #:width 7 #:height 5
     #:background "aliceblue" #:render-mode 'opaque
     #:camera (perspective-camera3d #:position (vec3 7 5 8)
                                    #:look-at origin3
                                    #:vertical-field-of-view (/ pi 7))))
  (scene-play
   (scene-add
    (make-scene) world
    (plain-text "SCENE-3D-T5: dense Poincare crossings"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "gold: x = 0 crossings from the stored trajectory, not display samples"
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:center origin3 #:azimuth (/ pi 3) #:elevation (/ pi 22))
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "poincare-section.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory)
                (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30 #:workers 2))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
