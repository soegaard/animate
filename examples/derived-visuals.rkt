#lang racket/base

;;;
;;; Pure Derived Visual Example
;;;

;; SCENE-AW resolves a concrete Visual from immutable sampled scalar values.
;; The resolver is pure; this SCENE-AW example reads only scalar context entries.

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)

(define (smoothstep progress)
  (* progress progress (- 3 (* 2 progress))))

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960
                 #:height 540
                 #:world-width 18
                 #:background "white"))
  (define reactive-dot
    (derived-visual
     (circle #:id 'dot
             #:center (vec2 -5 0)
             #:radius 3/4
             #:fill "royalblue"
             #:stroke "midnightblue"
             #:stroke-width 4)
     (lambda (context template)
       (define x (derived-context-value-ref context 'x))
       (define pulse (derived-context-value-ref context 'pulse))
       (circle #:id (visual-id template)
               #:center (vec2 x (* 3/2 pulse))
               #:radius (+ 3/4 (* 1/2 pulse))
               #:fill "royalblue"
               #:stroke "midnightblue"
               #:stroke-width 4))))
  (define guide
    (line (vec2 -6 0) (vec2 6 0)
          #:id 'guide
          #:stroke "lightgray"
          #:stroke-width 2))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AW: pure derived Visuals"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 4)))
  (define initial
    (scene-add
     (scene-set-value
      (scene-set-value (make-scene #:camera camera) 'x -5)
      'pulse 0)
     guide
     reactive-dot
     title))
  (define intro (scene-wait initial 1))
  (define animated
    (scene-play
     intro
     (animation-group
      (value-to 'x 5)
      (succession
       (value-to 'pulse 1)
       (value-to 'pulse 0)))
     #:duration 5
     #:easing smoothstep))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "derived-visuals.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n"
          (length frame-paths)
          output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
