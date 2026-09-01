#lang racket/base

;;;
;;; Normalized Morphs Example
;;;

;; Renders the canonical SCENE-I limited path-normalization example as PNG
;; frames and optionally assembles them as an MP4 file.


;;;
;;; Imports
;;;

(require racket/cmdline
         "../main.rkt")


;;;
;;; Path Definitions
;;;

; make-panel-source-path : -> path-geometry?
;;   Creates a closed triangle with two stored line segments.
(define (make-panel-source-path)
  (polygon-path
   (list (vec2 -3 -1)
         (vec2 3 -1)
         (vec2 0 2))))

; make-panel-destination-path : -> path-geometry?
;;   Creates a closed quadrilateral with three stored line segments.
(define (make-panel-destination-path)
  (polygon-path
   (list (vec2 -3 -2)
         (vec2 3 -2)
         (vec2 3 2)
         (vec2 -3 2))))

; make-wave-source-path : -> path-geometry?
;;   Creates one open straight line segment.
(define (make-wave-source-path)
  (polyline-path
   (list (vec2 -3 0)
         (vec2 3 0))))

; make-wave-destination-path : -> path-geometry?
;;   Creates an open two-segment cubic wave.
(define (make-wave-destination-path)
  (cubic-bezier-path
   (vec2 -3 0)
   (list
    (cubic-bezier-path-segment (vec2 -2 2)
                               (vec2 -1 2)
                               origin)
    (cubic-bezier-path-segment (vec2 1 -2)
                               (vec2 2 -2)
                               (vec2 3 0)))))


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Morphs paths with different segment kinds and counts.
(define (make-demo-scene)
  (define panel
    (make-path-visual (make-panel-source-path)
                      #:id 'panel
                      #:center (vec2 0 2)
                      #:fill "cornflowerblue"
                      #:stroke "navy"
                      #:stroke-width 3))
  (define wave
    (make-path-visual (make-wave-source-path)
                      #:id 'wave
                      #:center (vec2 0 -2)
                      #:stroke "crimson"
                      #:stroke-width 5))
  (define morphed
    (scene-play
     (scene-add (make-scene) panel wave)
     (morph-to-normalized panel (make-panel-destination-path))
     (rotate-by panel 1/2)
     (morph-to-normalized wave (make-wave-destination-path))
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
   #:program "normalized-morphs.rkt"
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
