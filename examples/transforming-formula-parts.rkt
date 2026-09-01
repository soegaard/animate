#lang racket/base

;;;
;;; Transforming Formula Parts Example
;;;

;; Renders the canonical SCENE-O matched formula-part transformation as PNG
;; frames and optionally assembles them as an MP4 file.


;;;
;;; Imports
;;;

(require racket/cmdline
         "../main.rkt")


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

; make-source-equation : -> formula-assembly-visual?
;;   Creates the source equation a squared plus b squared equals c squared.
(define (make-source-equation)
  (formula-assembly
   (list (make-equation-part 'a-square "a^2" -12/5)
         (make-equation-part 'plus "+" -6/5)
         (make-equation-part 'b-square "b^2" 0)
         (make-equation-part 'equals "=" 6/5)
         (make-equation-part 'c-square "c^2" 12/5))
   #:id 'equation
   #:center (vec2 -6 0)
   #:rotation -1/16
   #:scale 4/5
   #:opacity 4/5))

; make-destination-equation : -> formula-assembly-visual?
;;   Creates the destination layout c squared minus a squared equals b squared.
(define (make-destination-equation)
  (formula-assembly
   (list (make-equation-part 'c-square "c^2" -12/5)
         (make-equation-part 'minus "-" -6/5)
         (make-equation-part 'a-square "a^2" 0)
         (make-equation-part 'equals "=" 6/5)
         (make-equation-part 'b-square "b^2" 12/5))
   #:id 'destination-template))

; make-correspondence : formula-assembly-visual?
;                       formula-assembly-visual?
;                       -> formula-correspondence?
;;   Matches moving terms and cross-fades plus into minus.
(define (make-correspondence source destination)
  (formula-correspondence
   source
   destination
   (list (formula-part-match 'a-square 'a-square)
         (formula-part-match 'plus 'minus)
         (formula-part-match 'b-square 'b-square)
         (formula-part-match 'equals 'equals))))


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Introduces one equation and transforms its explicitly matched parts.
(define (make-demo-scene)
  (define source
    (make-source-equation))
  (define destination
    (make-destination-equation))
  (define correspondence
    (make-correspondence source destination))
  (define background
    (rectangle #:id 'background
               #:width 9
               #:height 3
               #:fill "aliceblue"
               #:stroke "navy"
               #:stroke-width 3))
  (define title
    (plain-text "Transform corresponding formula parts"
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
  (define transformation
    (scene-play entrance
                (transform-formula-parts correspondence)
                (move-to source (vec2 0 -1/2))
                (rotate-to source 1/24)
                (scale-to source 6/5)
                (fade-to source 1)
                #:duration 2))
  (scene-wait transformation 1/2))


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
