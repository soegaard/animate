#lang racket/base

;;;
;;; Deferred semantic mapped-composition example
;;;

;; `children-of` is a query, not an author-time list. It resolves after the
;; preceding enter has established the panel, and the template sees one
;; target-ref with separate source and scheduled indexes.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960 #:height 540 #:world-width 18 #:background "white"))
  (define first
    (circle #:id 'first #:radius 3/5 #:center (vec2 -4 1)
            #:fill "royalblue" #:stroke "midnightblue" #:stroke-width 3))
  (define second
    (circle #:id 'second #:radius 3/5 #:center (vec2 -4 -1)
            #:fill "seagreen" #:stroke "darkgreen" #:stroke-width 3))
  (define panel (group (list first second) #:id 'panel))
  (define title
    (fixed-in-frame
     (plain-text "FX-R: semantic local-start mapping"
                 #:id 'title #:font-size 2/5 #:font-family 'swiss
                 #:font-weight 'bold #:color "navy")
     #:camera camera #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "children-of resolves after enter; reverse changes schedule, not source index"
                 #:id 'note #:font-size 7/20 #:font-family 'swiss #:color "dimgray")
     #:camera camera #:at (vec2 0 -4)))
  (define base (scene-add (make-scene #:camera camera) title note))
  (define animated
    (scene-play
     (scene-wait base 1)
     (succession
      (enter panel #:translation-offset (vec2 -2 0) #:opacity-factor 0)
      (stagger-map
       (children-of 'panel)
       (lambda (reference)
         (move-to (target-ref-path reference)
                  (vec2 (+ 1 (target-ref-source-index reference))
                        (vec2-y (visual-position (target-ref-value reference))))))
       #:order 'reverse
       #:lag-ratio 1/2))
     #:duration 5))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "semantic-mapped-composition.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
