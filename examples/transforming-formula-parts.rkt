#lang racket/base

;;;
;;; Transforming Formula Parts Example
;;;

;; Renders a two-step matched formula-part transformation as PNG frames and
;; optionally assembles them as an MP4 file.


;;;
;;; Imports
;;;

(require racket/cmdline
         "../main.rkt")


;;;
;;; Exports
;;;

(provide make-demo-scene)


;;;
;;; Formula Construction
;;;

; make-equation-part : symbol? string? real? -> formula-part?
;;   Creates one baseline-aligned inline part at local x.
(define (make-equation-part name source x)
  (latex-formula-part source
                      #:name name
                      #:center (vec2 x 0)
                      #:mode 'inline
                      #:font-size 2/5
                      #:vertical-alignment 'baseline))

; transition-pause-duration : positive-real?
;;   Gives the reading pause shown before each formula transformation.
(define transition-pause-duration
  1)

; equation-term-spacing : positive-real?
;;   Gives the compact center-to-center spacing between adjacent formula parts.
(define equation-term-spacing
  3/4)

; equation-slot : integer? -> real?
;;   Returns one compact local x position relative to the equality sign.
(define (equation-slot index)
  (* equation-term-spacing index))

; make-source-equation : -> formula-assembly-visual?
;;   Creates the source equation a squared plus b squared equals c squared.
(define (make-source-equation)
  (formula-assembly
   (list (make-equation-part 'a-square "a^2" (equation-slot -3))
         (make-equation-part 'plus     "+"   (equation-slot -2))
         (make-equation-part 'b-square "b^2" (equation-slot -1))
         (make-equation-part 'equals   "="    (equation-slot 0))
         (make-equation-part 'c-square "c^2" (equation-slot 1)))
   #:id 'equation
   #:center (vec2 -6 0)
   #:rotation -1/16
   #:scale 4/5
   #:opacity 4/5))

; make-rearranged-equation : [#:id symbol?] -> formula-assembly-visual?
;;   Creates the algebraic rearrangement b squared equals c squared minus a squared.
(define (make-rearranged-equation #:id [identifier 'rearranged-template])
  (formula-assembly
   (list (make-equation-part 'b-square "b^2" (equation-slot -1))
         (make-equation-part 'equals   "="    (equation-slot 0))
         (make-equation-part 'c-square "c^2" (equation-slot 1))
         (make-equation-part 'minus    "-"    (equation-slot 2))
         (make-equation-part 'a-square "a^2" (equation-slot 3)))
   #:id identifier))

; make-flipped-equation : -> formula-assembly-visual?
;;   Creates the equivalent equation c squared minus a squared equals b squared.
(define (make-flipped-equation)
  (formula-assembly
   (list (make-equation-part 'c-square "c^2" (equation-slot -3))
         (make-equation-part 'minus    "-"   (equation-slot -2))
         (make-equation-part 'a-square "a^2" (equation-slot -1))
         (make-equation-part 'equals   "="    (equation-slot 0))
         (make-equation-part 'b-square "b^2" (equation-slot 1)))
   #:id 'flipped-template))

; make-rearrangement-correspondence : formula-assembly-visual?
;                                      formula-assembly-visual?
;                                      -> formula-correspondence?
;;   Keeps the unaffected equation stationary while the subtraction terms
;;   fade out on the left and appear on the right.
(define (make-rearrangement-correspondence source rearranged)
  (formula-correspondence
   source
   rearranged
   (list (formula-part-match 'b-square 'b-square)
         (formula-part-match 'equals   'equals)
         (formula-part-match 'c-square 'c-square))))

; make-side-swap-correspondence : formula-assembly-visual?
;                                  formula-assembly-visual?
;                                  -> formula-correspondence?
;;   Matches every part while moving the two equation sides past each other.
(define (make-side-swap-correspondence rearranged flipped)
  (formula-correspondence
   rearranged
   flipped
   (list (formula-part-match 'b-square 'b-square)
         (formula-part-match 'equals   'equals)
         (formula-part-match 'c-square 'c-square)
         (formula-part-match 'minus    'minus)
         (formula-part-match 'a-square 'a-square))))


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Introduces one equation, rearranges it, and then swaps its sides.
(define (make-demo-scene)
  (define source
    (make-source-equation))
  (define rearranged
    (make-rearranged-equation))
  (define rearranged-source
    (make-rearranged-equation #:id 'equation))
  (define flipped
    (make-flipped-equation))
  (define rearrangement-correspondence
    (make-rearrangement-correspondence source rearranged))
  (define side-swap-correspondence
    (make-side-swap-correspondence rearranged-source flipped))
  (define background
    (rectangle #:id 'background
               #:width 9
               #:height 3
               #:fill "aliceblue"
               #:stroke "navy"
               #:stroke-width 3))
  (define title
    (plain-text "Subtract a², then swap equation sides"
                #:id 'title
                #:center (vec2 0 1)
                #:font-size 1/3
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define initial
    (scene-add (make-scene) background title))
  (define entrance
    (scene-play initial
                (move-to source (vec2 0 -1/3))
                (rotate-to source 0)
                (scale-to source 1)
                (fade-in source)
                #:duration 2))
  (define source-pause
    (scene-wait entrance transition-pause-duration))
  (define rearrangement
    (scene-play source-pause
                (transform-formula-parts rearrangement-correspondence)
                #:duration 2))
  (define rearrangement-pause
    (scene-wait rearrangement transition-pause-duration))
  (define side-swap
    (scene-play rearrangement-pause
                (transform-formula-parts side-swap-correspondence)
                #:duration 2))
  (scene-wait side-swap 1/2))


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
   #:program "transforming-formula-parts.rkt"
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
