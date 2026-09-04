#lang racket/base

;;;
;;; SCENE-DY: General Boolean Geometry and Clipping
;;;

;; This demo deliberately strokes the results. If Boolean results were exposed
;; as their internal ear-clipping triangles, diagonal seams would be visible.
;; The rendered result instead has just exterior and hole boundaries.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (caption id text center)
  (plain-text text #:id id #:center center
              #:font-size 1/4 #:font-family 'swiss #:font-weight 'bold
              #:color "midnightblue"))

(define (polygon-subpath points)
  (car (path-geometry-subpaths (polygon-path points))))

(define (compound-path . contours)
  (path-geometry (map polygon-subpath contours)))

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-DY: compound Boolean geometry"
                #:id 'title #:center (vec2 0 18/5)
                #:font-size 2/5 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Concave paths, compound holes, and geometric clipping all keep clean outlines."
                #:id 'explanation #:center (vec2 0 3)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))

  ;; A concave L is clipped by a disk. The result below is stroked, so a
  ;; triangulation seam would be immediately visible inside its filled region.
  (define concave
    (polygon-path
     (list (vec2 -4 -2) (vec2 -7/5 -2) (vec2 -7/5 -6/5)
           (vec2 -13/5 -6/5) (vec2 -13/5 6/5) (vec2 -4 6/5))))
  (define clip-disk
    (path-geometry-translate
     (path-visual-path
      (ellipse #:id 'clip-disk-proxy #:center origin #:width 12/5 #:height 12/5))
     (vec2 -13/5 -2/5)))
  (define concave-source
    (make-path-visual concave #:id 'concave-source #:fill "aliceblue"
                      #:stroke "steelblue" #:stroke-width 3))
  (define clip-outline
    (make-path-visual clip-disk #:id 'clip-outline #:fill #f
                      #:stroke "indianred" #:stroke-width 2))
  (define clipped-result
    ;; This overload clips the complete vector Visual at render time. It does
    ;; not convert the L shape to a Boolean result or a bitmap first.
    (clip-to
     (make-path-visual concave #:id 'clipped-content #:fill "mediumseagreen"
                       #:stroke "darkgreen" #:stroke-width 3)
     clip-disk
     #:id 'clipped-result))

  ;; The right panel starts as one compound odd-even path. It is intersected
  ;; with an enclosing viewport solely to demonstrate a compound input. Its
  ;; inner loop remains a real hole, not a stack of filled triangles.
  (define outer
    (list (vec2 1 -2) (vec2 4 -2) (vec2 4 6/5) (vec2 1 6/5)))
  (define hole
    (list (vec2 9/5 -6/5) (vec2 16/5 -6/5)
          (vec2 16/5 2/5) (vec2 9/5 2/5)))
  (define ring (compound-path outer hole))
  (define viewport
    (polygon-path
     (list (vec2 3/5 -12/5) (vec2 22/5 -12/5)
           (vec2 22/5 8/5) (vec2 3/5 8/5))))
  (define ring-result (mask-with ring viewport))
  (define ring-source
    (make-path-visual ring #:id 'ring-source #:fill "lavender"
                      #:stroke "mediumpurple" #:stroke-width 3))
  (define viewport-outline
    (make-path-visual viewport #:id 'viewport-outline #:fill #f
                      #:stroke "goldenrod" #:stroke-width 2))
  (define ring-result-visual
    (make-path-visual ring-result #:id 'ring-result #:fill "plum"
                      #:stroke "indigo" #:stroke-width 3))

  (define initial
    (scene-add (make-scene)
               title explanation
               concave-source clip-outline ring-source viewport-outline
               (caption 'clip-caption "concave ∩ disk" (vec2 -13/5 -14/5))
               (caption 'ring-caption "compound odd-even hole" (vec2 5/2 -14/5))))
  (define revealed
    (scene-play initial
                (fade-to 'concave-source 1/4)
                (fade-to 'clip-outline 1/4)
                (fade-in clipped-result)
                (fade-to 'ring-source 1/4)
                (fade-to 'viewport-outline 1/4)
                (fade-in ring-result-visual)
                #:duration 2))
  (scene-wait (scene-wait revealed 1) 2))

(module+ main
  (run-demo "general-boolean-clipping.rkt" make-demo-scene))
