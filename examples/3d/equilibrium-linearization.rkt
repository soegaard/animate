#lang racket/base

;;; SCENE-3D-T6: Saddle Equilibrium and Linearization

;; The diagram lines are derived from one immutable linearization.  The vector
;; field is only a contextual display; no camera frame recomputes an
;; eigensystem or a numerical Jacobian.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define saddle-field
  (ode-field3d
   (lambda (x y z) (vec3 x (* -2 y) (* -1/2 z)))
   #:cache-key 'diagonal-saddle))

(define saddle-linearization
  (linearize3d saddle-field origin3
               #:jacobian (lambda (_x _y _z) (linear3 1 0 0 0 -2 0 0 0 -1/2))))

(define (make-demo-scene)
  (define world
    (view3d
     (list
      (axes3d #:id 'axes #:x-range (list -2 2) #:y-range (list -2 2) #:z-range (list -2 2)
              #:stroke-style (stroke3d #:color "lightsteelblue" #:width 1))
      (vector-field3d saddle-field #:id 'field
                      #:x-range (list -3/2 3/2) #:y-range (list -3/2 3/2) #:z-range (list -3/2 3/2)
                      #:x-count 3 #:y-count 3 #:z-count 3 #:normalize? #t #:scale 1/3
                      #:shaft-style (stroke3d #:color "slategray" #:width 1)
                      #:tip-style (arrow-style3d #:color "slategray"))
      (linearization-diagram3d saddle-linearization #:id 'eigendirections #:scale 7/4
                               #:stable-style (stroke3d #:color "royalblue" #:width 4)
                               #:unstable-style (stroke3d #:color "tomato" #:width 4))
      (point3d origin3 #:id 'equilibrium
               #:style (point-style3d #:size 15 #:color "gold")))
     #:id 'world #:center (vec2 0 0) #:width 7 #:height 5
     #:background "aliceblue" #:render-mode 'opaque
     #:camera (perspective-camera3d #:position (vec3 6 5 8)
                                    #:look-at origin3
                                    #:vertical-field-of-view (/ pi 7))))
  (scene-play
   (scene-add
    (make-scene) world
    (plain-text "SCENE-3D-T6: a deterministic saddle linearization"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "gold: equilibrium       red: unstable eigendirection       blue: stable eigendirections"
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:center origin3 #:azimuth (/ pi 3) #:elevation (/ pi 28))
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "equilibrium-linearization.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory)
                (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30 #:workers 2))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
