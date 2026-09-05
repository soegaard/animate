#lang racket/base

;;;
;;; Affine-degeneracy gallery
;;;

;; Exercises the renderer at the rank-one midpoint of a reflection.  Each
;; subject reflects about its own vertical centre line, so the midpoint keeps
;; the gallery layout and exposes the renderer's zero-width behaviour.

(require racket/runtime-path
         animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define-runtime-path assets-directory "assets")

(define (reflection-about-vertical x)
  ;; (x, y) maps to (2x - x-coordinate, y).
  (affine2 -1 0 (* 2 x)
           0 1 0))

(define (reflection-request visual)
  (apply-affine visual
                (reflection-about-vertical
                 (vec2-x (visual-position visual)))))

(define (height-guides id center-x bottom top half-width)
  ;; These stay behind the subject and are deliberately not transformed.  A
  ;; correct zero-width midpoint should retain the same vertical span between
  ;; them.
  (list
   (line (vec2 (- center-x half-width) bottom)
         (vec2 (+ center-x half-width) bottom)
         #:id (string->symbol (format "~a-bottom-guide" id))
         #:stroke "lightsteelblue" #:stroke-width 1)
   (line (vec2 (- center-x half-width) top)
         (vec2 (+ center-x half-width) top)
         #:id (string->symbol (format "~a-top-guide" id))
         #:stroke "lightsteelblue" #:stroke-width 1)))

(define (make-demo-scene)
  (define camera
    (make-camera #:width 1280 #:height 720 #:world-width 14
                 #:center origin #:background "white"))
  (define title
    (plain-text "Affine-degeneracy renderer gallery"
                #:id 'title #:center (vec2 0 16/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Every subject reflects through its own vertical centre line."
                #:id 'explanation #:center (vec2 0 29/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))

  (define a-circle
    (circle #:id 'circle #:center (vec2 -9/2 1)
            #:radius 3/5 #:fill "lightskyblue" #:stroke "steelblue"))
  (define a-rectangle
    (rectangle #:id 'rectangle #:center (vec2 -3/2 1)
               #:width 7/5 #:height 6/5
               #:fill "gold" #:stroke "goldenrod"))
  (define an-arrow
    (vector-arrow (vec2 5/2 8/5) #:start (vec2 3/2 2/5)
                  #:id 'arrow #:stroke "crimson"))
  (define some-axes
    (axes #:id 'axes #:center (vec2 9/2 1)
          #:x-range (axis-range -1 1 1) #:y-range (axis-range -1 1 1)
          #:x-length 2 #:y-length 2 #:stroke "darkorchid"))
  (define an-svg
    (svg-image (build-path assets-directory "roadmap-rocket.svg")
               #:id 'svg #:center (vec2 -5/2 -7/4)
               #:width 7/5 #:height 2))
  (define a-formula
    (latex-formula "\\displaystyle\\int_0^1 x^2\\,dx"
                   #:id 'formula #:center (vec2 5/2 -7/4)
                   #:font-size 2/5))
  ;; Formula rendering is an optional system capability: on a Racket build
  ;; without compatible latex-pict/Poppler libraries, retain the same affine
  ;; test slot with a normal Pict text fallback.  The regression suite records
  ;; this as an unavailable optional case rather than hiding the environment
  ;; limitation behind a render failure.
  (define rendered-formula?
    (with-handlers ([exn:fail? (lambda (_) #f)])
      (visual->pict a-formula camera)
      #t))
  (define formula-subject
    (if rendered-formula?
        a-formula
        (plain-text "LaTeX unavailable"
                    #:id 'formula #:center (vec2 5/2 -7/4)
                    #:font-size 2/5 #:color "firebrick")))
  (define subjects
    (list a-circle a-rectangle an-arrow some-axes an-svg formula-subject))
  (define guides
    (append
     (height-guides 'circle -9/2 2/5 8/5 4/5)
     (height-guides 'rectangle -3/2 2/5 8/5 4/5)
     (height-guides 'arrow 2 2/5 8/5 4/5)
     (height-guides 'axes 9/2 0 2 4/5)
     (height-guides 'svg -5/2 -11/4 -3/4 4/5)
     (height-guides 'formula 5/2 -9/4 -5/4 1)))
  (define labels
    (list
     (plain-text "circle" #:id 'circle-label #:center (vec2 -9/2 -1/10)
                 #:font-size 1/5 #:color "dimgray")
     (plain-text "rectangle" #:id 'rectangle-label #:center (vec2 -3/2 -1/10)
                 #:font-size 1/5 #:color "dimgray")
     (plain-text "arrow" #:id 'arrow-label #:center (vec2 2 -1/10)
                 #:font-size 1/5 #:color "dimgray")
     (plain-text "axes" #:id 'axes-label #:center (vec2 9/2 -1/10)
                 #:font-size 1/5 #:color "dimgray")
     (plain-text "SVG" #:id 'svg-label #:center (vec2 -5/2 -3)
                 #:font-size 1/5 #:color "dimgray")
     (plain-text (if rendered-formula? "formula" "formula (unavailable)")
                 #:id 'formula-label #:center (vec2 5/2 -3)
                 #:font-size 1/5 #:color "dimgray")))
  (define initial
    (apply scene-add (make-scene #:camera camera)
           (append (list title explanation) guides labels subjects)))
  (scene-wait
   (scene-play initial
               (apply animation-group (map reflection-request subjects))
               #:duration 3)
   2))

(module+ main
  (run-demo "affine-degeneracy-gallery.rkt" make-demo-scene))
