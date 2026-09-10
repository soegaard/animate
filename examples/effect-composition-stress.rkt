#lang racket/base

;;;
;;; Effect Composition Stress Scene
;;;

(require racket/cmdline
         racket/math
         animate
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960 #:height 540 #:world-width 18 #:background "white"))
  (define title
    (fixed-in-frame
     (plain-text "FX-G: deterministic effect composition"
                 #:id 'title #:font-size 2/5 #:font-family 'swiss
                 #:font-weight 'bold #:color "navy")
     #:camera camera #:at (vec2 0 3)))
  (define note
    (fixed-in-frame
     (plain-text "independent targets keep lifecycle, transient helpers, and source sampling composable"
                 #:id 'note #:font-size 7/20 #:font-family 'swiss #:color "dimgray")
     #:camera camera #:at (vec2 0 -3)))
  (define panel
    (rectangle #:id 'panel #:width 8 #:height 3 #:center origin
               #:fill "aliceblue" #:stroke "steelblue" #:stroke-width 4))
  (define badge
    (circle #:id 'badge #:radius 3/5 #:center (vec2 -2 0)
            #:fill "mediumorchid" #:stroke "indigo" #:stroke-width 3))
  (define curve
    (make-path-visual
     (polyline-path
      (for/list ([index (in-range 25)])
        (define fraction (/ index 24))
        (vec2 (+ 1 (* 5 fraction))
              (/ (sin (* 4 pi fraction)) 3))))
     #:id 'curve #:fill #f #:stroke "tomato" #:stroke-width 4))
  (define caption
    ;; Keep the stress scene renderable by the documented conservative Pict
    ;; typewrite subset. Rich/wrapped partial text is a capability diagnostic,
    ;; not a visual-probe fallback.
    (plain-text "sable layout" #:id 'caption #:center (vec2 1 1)
                #:font-size 1/2 #:font-family 'swiss #:color "navy"))
  (define base (scene-add (make-scene #:camera camera) title note curve))
  (define introduced
    (scene-play
     (scene-wait base 1/2)
     (animation-group
      (reveal-in panel (linear-reveal-front (vec2 1 0)))
      (enter badge #:translation-offset (vec2 -2 0) #:scale-factor 1/5)
      (typewrite caption #:unit 'run))
     #:duration 2))
  (define active
    (scene-play
     (scene-wait introduced 1/2)
     (animation-group
      (pulse 'badge #:scale-factor 7/5 #:cycles 2)
      (ripple 'panel #:rings 3 #:color "gold")
      (apply-wave 'curve #:direction (vec2 0 1) #:amplitude 2/5 #:cycles 2))
     #:duration 3))
  (define celebrated
    (scene-play
     (scene-wait active 1/2)
     (confetti 'badge #:count 32 #:seed 20260909 #:spread 3 #:height 3 #:gravity 5)
     #:duration 2))
  (scene-wait celebrated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "effect-composition-stress.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
