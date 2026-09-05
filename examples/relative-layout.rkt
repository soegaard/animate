#lang racket/base

;;;
;;; Relative Layout Example
;;;

;; Measures rendered text and formula boxes, arranges them without overlap,
;; fits a background card around their union, and renders an animated scene.


;;;
;;; Imports
;;;

(require racket/cmdline
         animate
         animate/render)


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Builds and animates one renderer-aware formula card.
(define (make-demo-scene)
  ; content : (listof visual?)
  ;;   Gives four initially coincident text and formula Visuals.
  (define content
    (list
     (plain-text "Renderer-aware layout"
                 #:id 'title
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:font-weight 'bold
                 #:color "navy")
     (latex-formula "e^{i\\pi}+1=0"
                    #:id 'identity
                    #:font-size 1/2)
     (latex-formula
      "\\sum_{k=1}^{n} k = \\frac{n(n+1)}{2}"
      #:id 'series
      #:font-size 1/3)
     (latex-formula "f'(x)=2x"
                    #:id 'derivative
                    #:mode 'inline
                    #:font-size 2/5)))

  ; arranged-content : (listof visual?)
  ;;   Gives top-to-bottom content with measured gaps and centered union.
  (define arranged-content
    (arrange-visuals-vertically
     content
     #:gap 1/3
     #:center origin
     #:camera default-camera
     #:renderers default-pict-renderers))

  ; content-box : layout-box?
  ;;   Gives the union of the measured content render boxes.
  (define content-box
    (visuals-layout-box arranged-content
                        #:camera default-camera
                        #:renderers default-pict-renderers))

  ; background : rectangle-visual?
  ;;   Gives a fitted card with three-quarter-unit padding on every side.
  (define background
    (rectangle #:id 'background
               #:center (layout-box-center content-box)
               #:width (+ (layout-box-width content-box) 3/2)
               #:height (+ (layout-box-height content-box) 3/2)
               #:fill "aliceblue"
               #:stroke "navy"
               #:stroke-width 4))

  ; card : group-visual?
  ;;   Gives the fitted background and content as one animated Visual.
  (define card
    (group (cons background arranged-content)
           #:id 'layout-card
           #:center (vec2 -6 1)
           #:rotation -1/10
           #:scale 4/5
           #:opacity 4/5))

  ; entrance : scene?
  ;;   Moves the card into the frame while restoring its transform and opacity.
  (define entrance
    (scene-play (make-scene)
                (move-to card origin)
                (rotate-to card 0)
                (scale-to card 1)
                (fade-in card)
                #:duration 2))

  ; emphasis : scene?
  ;;   Gives the laid-out card a small final movement and rotation.
  (define emphasis
    (scene-play entrance
                (move-to card (vec2 0 1/4))
                (rotate-to card 1/48)
                (scale-to card 21/20)
                (fade-to card 1)
                #:duration 1))

  (scene-wait emphasis 1/2))


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
   #:program "relative-layout.rkt"
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
