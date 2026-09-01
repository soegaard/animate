#lang racket/base

;;;
;;; Morphing Paths Example
;;;

;; Renders the canonical SCENE-H compatible path morph as PNG frames and
;; optionally assembles them as an MP4 file.


;;;
;;; Imports
;;;

(require racket/cmdline
         "../main.rkt")


;;;
;;; Path Definitions
;;;

; make-panel-source-path : -> path-geometry?
;;   Creates a centered rectangular closed line path.
(define (make-panel-source-path)
  (polygon-path
   (list (vec2 -2 -1)
         (vec2 2 -1)
         (vec2 2 1)
         (vec2 -2 1))))

; make-panel-destination-path : -> path-geometry?
;;   Creates a compatible centered diamond-shaped line path.
(define (make-panel-destination-path)
  (polygon-path
   (list (vec2 0 -2)
         (vec2 3 0)
         (vec2 0 2)
         (vec2 -3 0))))

; make-wave-source-path : -> path-geometry?
;;   Creates a two-segment cubic wave.
(define (make-wave-source-path)
  (cubic-bezier-path
   (vec2 -3 0)
   (list
    (cubic-bezier-path-segment (vec2 -2 2)
                               (vec2 -1 2)
                               origin)
    (cubic-bezier-path-segment (vec2 1 -2)
                               (vec2 2 -2)
                               (vec2 3 0)))))

; make-wave-destination-path : -> path-geometry?
;;   Creates a compatible two-segment cubic arch.
(define (make-wave-destination-path)
  (cubic-bezier-path
   (vec2 -3 -1)
   (list
    (cubic-bezier-path-segment (vec2 -2 -1)
                               (vec2 -1 3)
                               (vec2 0 3))
    (cubic-bezier-path-segment (vec2 1 3)
                               (vec2 2 -1)
                               (vec2 3 -1)))))


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Morphs line and cubic paths while applying disjoint affine changes.
(define (make-demo-scene)
  (define panel-source-path
    (make-panel-source-path))
  (define panel-destination-path
    (make-panel-destination-path))
  (define wave-source-path
    (make-wave-source-path))
  (define wave-destination-path
    (make-wave-destination-path))
  (define panel
    (make-path-visual panel-source-path
                      #:id 'panel
                      #:center (vec2 0 2)
                      #:fill "cornflowerblue"
                      #:stroke "navy"
                      #:stroke-width 3))
  (define wave
    (make-path-visual wave-source-path
                      #:id 'wave
                      #:center (vec2 0 -2)
                      #:stroke "crimson"
                      #:stroke-width 5))
  (define morphed
    (scene-play
     (scene-add (make-scene) panel wave)
     (morph-to panel panel-destination-path)
     (rotate-by panel 1/2)
     (morph-to wave wave-destination-path)
     (scale-to wave (vec2 4/3 3/4))
     #:duration 2))
  (scene-wait morphed 1/2))


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
   #:program "morphing-paths.rkt"
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
