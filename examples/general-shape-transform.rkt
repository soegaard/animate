#lang racket/base

;;;
;;; SCENE-CG General Shape Transform
;;;

;; `transform-shape` swaps one scene identity for another. A single built-in
;; shape uses topology-aware outline correspondence; a composite diagram has no
;; one-outline interpretation, so auto mode deliberately uses a cross-fade.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)


;;; Scene Definition

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-CG: general shape transforms"
                #:id 'title
                #:center (vec2 0 3)
                #:font-size 2/5
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "A primitive morphs by its outline; a composite falls back to a cross-fade."
                #:id 'explanation
                #:center (vec2 0 5/2)
                #:font-size 1/5
                #:font-family 'swiss
                #:color "darkslategray"))
  (define primitive-caption
    (plain-text "one primitive: geometric morph"
                #:id 'primitive-caption
                #:center (vec2 -3 -2)
                #:font-size 1/5
                #:font-family 'swiss
                #:color "midnightblue"))
  (define composite-caption
    (plain-text "composite diagram: cross-fade"
                #:id 'composite-caption
                #:center (vec2 3 -2)
                #:font-size 1/5
                #:font-family 'swiss
                #:color "midnightblue"))
  (define square
    (rectangle #:id 'square
               #:center (vec2 -3 0)
               #:width 2
               #:height 2
               #:fill "cornflowerblue"
               #:stroke "navy"
               #:stroke-width 3))
  (define disk
    (circle #:id 'disk
            #:center (vec2 -3 0)
            #:radius 1
            #:fill "seagreen"
            #:stroke "darkgreen"
            #:stroke-width 3))
  (define box
    (rectangle #:id 'box
               #:width 2
               #:height 3/2
               #:fill "aliceblue"
               #:stroke "navy"
               #:stroke-width 3))
  (define dot
    (circle #:id 'dot
            #:center (vec2 1/2 1/4)
            #:radius 1/5
            #:fill "crimson"
            #:stroke "white"
            #:stroke-width 2))
  (define composite
    (group (list box dot)
           #:id 'composite
           #:center (vec2 3 0)))
  (define target
    (circle #:id 'target
            #:center (vec2 3 0)
            #:radius 1
            #:fill "goldenrod"
            #:stroke "darkorange"
            #:stroke-width 3))
  (define initial
    (scene-add (make-scene)
               title explanation primitive-caption composite-caption square composite))
  (define morphed
    (scene-play initial
                (transform-shape square disk #:mode 'morph)
                #:duration 2))
  (define replaced
    (scene-play morphed
                (transform-shape composite target)
                #:duration 3/2))
  (scene-wait replaced 2))


;;; Command-Line Entry Point

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "general-shape-transform.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
