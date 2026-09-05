#lang racket/base

;;;
;;; Open Morph Correspondence Example
;;;

;; Compares stored-order normalized morphing with SCENE-AE automatic open-path
;; endpoint-direction correspondence.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (make-source-path)
  (cubic-bezier-path
   (vec2 -5 -2)
   (list
    (cubic-bezier-path-segment
     (vec2 -4 3)
     (vec2 -1 3)
     (vec2 0 1))
    (cubic-bezier-path-segment
     (vec2 2 -3)
     (vec2 4 -2)
     (vec2 5 2)))))

(define (make-canonical-destination-path)
  (cubic-bezier-path
   (vec2 -5 2)
   (list
    (cubic-bezier-path-segment
     (vec2 -3 4)
     (vec2 -1 -2)
     (vec2 0 -1))
    (cubic-bezier-path-segment
     (vec2 2 3)
     (vec2 4 4)
     (vec2 5 1)))))

(define (make-demo-scene)
  (define source
    (make-source-path))
  ;; The visible destination is stored from right to left on purpose. The upper
  ;; panel therefore cross-maps endpoints; SCENE-AE may reverse only its
  ;; interior correspondence in the lower panel.
  (define destination
    (path-geometry-reverse
     (make-canonical-destination-path)))
  (define camera
    (make-camera #:world-width 28
                 #:center origin
                 #:background "white"))
  (define stored-order-panel
    (make-path-visual source
                      #:id 'stored-order-panel
                      #:center (vec2 0 7/2)
                      #:scale 4/5
                      #:stroke "navy"
                      #:stroke-width 5))
  (define open-aligned-panel
    (make-path-visual source
                      #:id 'open-aligned-panel
                      #:center (vec2 0 -7/2)
                      #:scale 4/5
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define stored-label
    (plain-text "normalized only: endpoints cross by stored direction"
                #:id 'stored-label
                #:center (vec2 0 13/2)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "navy"))
  (define aligned-label
    (plain-text "SCENE-AE: automatic open-path endpoint correspondence"
                #:id 'aligned-label
                #:center (vec2 0 -1/2)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "darkgreen"))
  (define scene
    (scene-add (make-scene #:camera camera)
               stored-order-panel
               open-aligned-panel
               stored-label
               aligned-label))
  (define morphed
    (scene-play
     scene
     (morph-to-normalized stored-order-panel destination)
     (morph-to-open-aligned open-aligned-panel destination)
     #:duration 4))
  (scene-wait morphed 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "open-morph-correspondence.rkt"
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
