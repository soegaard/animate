#lang racket/base

;;;
;;; Named Formula Parts Example
;;;

;; Renders the canonical SCENE-N named-part and manual-correspondence example as
;; PNG frames and optionally assembles them as an MP4 file.


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
                      #:font-size 1/3
                      #:vertical-alignment 'baseline))

; make-source-equation : -> formula-assembly-visual?
;;   Creates the named source equation a squared plus b squared equals c squared.
(define (make-source-equation)
  (formula-assembly
   (list (make-equation-part 'a-square "a^2" -2)
         (make-equation-part 'plus "+" -1)
         (make-equation-part 'b-square "b^2" 0)
         (make-equation-part 'equals "=" 1)
         (make-equation-part 'c-square "c^2" 2))
   #:id 'source-equation
   #:center (vec2 0 -1/4)))

; make-destination-equation : -> formula-assembly-visual?
;;   Creates the named destination equation c squared minus a squared equals b squared.
(define (make-destination-equation)
  (formula-assembly
   (list (make-equation-part 'c-square "c^2" -2)
         (make-equation-part 'minus "-" -1)
         (make-equation-part 'a-square "a^2" 0)
         (make-equation-part 'equals "=" 1)
         (make-equation-part 'b-square "b^2" 2))
   #:id 'destination-equation
   #:center (vec2 0 -1/4)))

; make-correspondence : formula-assembly-visual?
;                       formula-assembly-visual?
;                       -> formula-correspondence?
;;   Creates the explicit one-to-one mapping between preserved terms.
(define (make-correspondence source destination)
  (formula-correspondence
   source
   destination
   (list (formula-part-match 'a-square 'a-square)
         (formula-part-match 'b-square 'b-square)
         (formula-part-match 'c-square 'c-square)
         (formula-part-match 'equals 'equals))))

; make-equation-card : symbol? string? formula-assembly-visual? vec2?
;                      -> group-visual?
;;   Places one named equation and label over a card background.
(define (make-equation-card id label equation center)
  (group
   (list
    (rectangle #:id (string->symbol (format "~a-background" id))
               #:width 6
               #:height 5/2
               #:fill "aliceblue"
               #:stroke "navy"
               #:stroke-width 3)
    (plain-text label
                #:id (string->symbol (format "~a-label" id))
                #:center (vec2 0 3/4)
                #:font-size 1/3
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy")
    equation)
   #:id id
   #:center center
   #:opacity 9/10))


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Animates two named formula assemblies and records their manual mapping.
(define (make-demo-scene)
  (define source-equation
    (make-source-equation))
  (define destination-equation
    (make-destination-equation))
  (define correspondence
    (make-correspondence source-equation destination-equation))
  (define source-card
    (make-equation-card 'source-card
                        "Source"
                        source-equation
                        (vec2 -8 5/4)))
  (define destination-card
    (make-equation-card 'destination-card
                        "Destination"
                        destination-equation
                        (vec2 8 -5/4)))
  (define summary
    (plain-text
     (format "~a explicit matches; ~a source-only; ~a destination-only"
             (length (formula-correspondence-matches correspondence))
             (length
              (formula-correspondence-unmatched-source-names correspondence))
             (length
              (formula-correspondence-unmatched-destination-names
               correspondence)))
     #:id 'correspondence-summary
     #:center (vec2 0 -7/2)
     #:font-size 1/4
     #:font-family 'swiss
     #:color "dimgray"))
  (define entrance
    (scene-play (make-scene)
                (move-to source-card (vec2 -7/2 5/4))
                (move-to destination-card (vec2 7/2 -5/4))
                (fade-in source-card)
                (fade-in destination-card)
                (fade-in summary)
                #:duration 2))
  (define emphasis
    (scene-play entrance
                (rotate-to source-card -1/24)
                (rotate-to destination-card 1/24)
                (scale-to source-card 11/10)
                (scale-to destination-card 11/10)
                (fade-to summary 1/2)
                #:duration 1))
  (define exit
    (scene-play emphasis
                (fade-out source-card)
                (fade-out destination-card)
                (fade-out summary)
                #:duration 3/2))
  (scene-wait exit 1/2))


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
   #:program "named-formula-parts.rkt"
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
