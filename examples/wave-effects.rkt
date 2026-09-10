#lang racket/base

;;;
;;; Target-Local Wave Effect
;;;

;; The displacement coordinate and direction are local to the grid, so the
;; curve is sampled from its immutable source rather than accumulated frame by
;; frame. It returns to the exact authored grid at the clip endpoint.

(require racket/cmdline
         racket/math
         animate
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960 #:height 540 #:world-width 18 #:background "white"))
  (define curve
    (make-path-visual
     (polyline-path
      (for/list ([index (in-range 49)])
        (define t (/ index 48))
        (vec2 (* 5 (- (* 2 t) 1)) (/ (sin (* 4 pi t)) 2))))
     #:id 'curve #:fill #f #:stroke "mediumorchid" #:stroke-width 5))
  (define title
    (fixed-in-frame
     (plain-text "FX-D: target-local wave"
                 #:id 'title #:font-size 2/5 #:font-family 'swiss
                 #:font-weight 'bold #:color "navy")
     #:camera camera #:at (vec2 0 3)))
  (define note
    (fixed-in-frame
     (plain-text "direct source sampling; zero displacement and exact source restoration at both ends"
                 #:id 'note #:font-size 7/20 #:font-family 'swiss #:color "dimgray")
     #:camera camera #:at (vec2 0 -3)))
  (define base (scene-add (make-scene #:camera camera) title note curve))
  (define animated
    (scene-play
     (scene-wait base 1/2)
     (apply-wave 'curve #:direction (vec2 0 1)
                 #:amplitude 3/5 #:wavelength 1 #:cycles 2)
     #:duration 3))
  (scene-wait animated 1/2))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "wave-effects.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
