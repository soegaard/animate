#lang racket/base

;;;
;;; Automatic Morph Correspondence Example
;;;

;; Compares stored-order normalized morphing with SCENE-AC automatic cyclic
;; phase/direction correspondence on the same source and destination loops.


;;;
;;; Imports and Exports
;;;

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)


;;;
;;; Path Definitions
;;;

; make-source-path : -> path-geometry?
;;   Creates one asymmetric six-vertex source loop.
(define (make-source-path)
  (polygon-path
   (list (vec2 -4 -1)
         (vec2 -2 2)
         (vec2 1 3)
         (vec2 4 1)
         (vec2 3 -2)
         (vec2 -1 -3))))

; make-stored-destination-path : -> path-geometry?
;;   Stores the destination from a different start in the opposite direction.
(define (make-stored-destination-path)
  (polygon-path
   (list (vec2 4 2)
         (vec2 0 7/2)
         (vec2 -5/2 3/2)
         (vec2 -7/2 -3/2)
         (vec2 0 -5/2)
         (vec2 4 -1))))


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Constructs the canonical SCENE-AC comparison animation.
(define (make-demo-scene)
  (define source
    (make-source-path))
  (define stored-destination
    (make-stored-destination-path))
  (define camera
    (make-camera #:world-width 26
                 #:center origin
                 #:background "white"))

  ;; Both panels begin with identical local source geometry. The destination
  ;; also describes one common visible loop; only its semantic start/direction
  ;; are deliberately inconvenient for correspondence.
  (define stored-order-panel
    (make-path-visual source
                      #:id 'stored-order-panel
                      #:center (vec2 0 3)
                      #:fill "lightsteelblue"
                      #:stroke "navy"
                      #:stroke-width 4))
  (define aligned-panel
    (make-path-visual source
                      #:id 'aligned-panel
                      #:center (vec2 0 -7/2)
                      #:fill "honeydew"
                      #:stroke "seagreen"
                      #:stroke-width 4))
  (define stored-label
    (plain-text "normalized only: stored order"
                #:id 'stored-label
                #:center (vec2 0 69/10)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "navy"))
  (define aligned-label
    (plain-text "SCENE-AC: automatic phase + direction"
                #:id 'aligned-label
                #:center (vec2 0 2/5)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "darkgreen"))
  (define scene
    (scene-add (make-scene #:camera camera)
               stored-order-panel
               aligned-panel
               stored-label
               aligned-label))

  ;; The upper panel pairs stored vertices directly and therefore twists across
  ;; the figure. The lower panel first selects the low-distance reverse/phase
  ;; correspondence, then uses exactly the same normalized cubic morph engine.
  (define morphed
    (scene-play scene
                (morph-to-normalized stored-order-panel stored-destination)
                (morph-to-aligned aligned-panel stored-destination)
                #:duration 4))
  (scene-wait morphed 1))


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
   #:program "automatic-morph-correspondence.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))

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
