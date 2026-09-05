#lang racket/base

;;;
;;; Curved Paths Example
;;;

;; Renders the canonical SCENE-G cubic Bézier animation as PNG frames and
;; optionally assembles them as an MP4 file.


;;;
;;; Imports
;;;

(require racket/cmdline
         animate
         animate/render)


;;;
;;; Scene Definition
;;;

; make-wave-path : -> path-geometry?
;;   Creates a symmetric open wave from two cubic segments.
(define (make-wave-path)
  (cubic-bezier-path
   (vec2 -4 0)
   (list
    (cubic-bezier-path-segment (vec2 -3 2)
                               (vec2 -1 2)
                               origin)
    (cubic-bezier-path-segment (vec2 1 -2)
                               (vec2 3 -2)
                               (vec2 4 0)))))

; make-loop-path : -> path-geometry?
;;   Creates a closed rounded loop from four cubic segments.
(define (make-loop-path)
  (cubic-bezier-path
   (vec2 0 2)
   (list
    (cubic-bezier-path-segment (vec2 2 2)
                               (vec2 3 1)
                               (vec2 3 0))
    (cubic-bezier-path-segment (vec2 3 -1)
                               (vec2 2 -2)
                               (vec2 0 -2))
    (cubic-bezier-path-segment (vec2 -2 -2)
                               (vec2 -3 -1)
                               (vec2 -3 0))
    (cubic-bezier-path-segment (vec2 -3 1)
                               (vec2 -2 2)
                               (vec2 0 2)))
   #:closed? #t))

; make-demo-scene : -> scene?
;;   Creates two curves, transforms them, removes one, and holds the result.
(define (make-demo-scene)
  (define wave
    (make-path-visual (make-wave-path)
                      #:id 'wave
                      #:center (vec2 0 2)
                      #:stroke "crimson"
                      #:stroke-width 5))
  (define loop
    (make-path-visual (make-loop-path)
                      #:id 'loop
                      #:center (vec2 0 -2)
                      #:fill "cornflowerblue"
                      #:stroke "navy"
                      #:stroke-width 3))
  (define created
    (scene-play (make-scene)
                (create wave)
                (create loop)
                #:duration 2))
  (define transformed
    (scene-play created
                (move-to wave (vec2 0 -2))
                (rotate-by wave 1/2)
                (move-to loop (vec2 0 2))
                (rotate-by loop -1/2)
                (scale-to loop (vec2 3/4 5/4))
                #:duration 3/2))
  (define removed
    (scene-play transformed
                (uncreate wave)
                #:duration 1))
  (scene-wait removed 1/2))


;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ; output-directory : path-string?
  ;;   Gives the directory that receives numbered PNG frames.
  (define output-directory
    "frames")

  ; output-video : (or/c path-string? false/c)
  ;;   Gives the optional MP4 output path.
  (define output-video
    #f)

  (command-line
   #:program "curved-paths.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))

  ; frame-paths : (listof path?)
  ;;   Gives the numbered PNG paths written for the demo.
  (define frame-paths
    (render-frames! (make-demo-scene)
                    output-directory
                    #:fps 30))

  (printf "Rendered ~a frames to ~a\n"
          (length frame-paths)
          output-directory)

  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
