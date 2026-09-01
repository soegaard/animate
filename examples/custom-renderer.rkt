#lang racket/base

;;;
;;; Custom Renderer Example
;;;

;; Demonstrates a third-party semantic Visual with an independent Pict renderer.


;;;
;;; Imports
;;;

(require (only-in pict cc-superimpose filled-rectangle)
         "../main.rkt")


;;;
;;; Custom Visual
;;;

(struct cross-visual (id center size fill)
  #:transparent
  #:methods gen:visual
  [(define (visual-id cross)
     (cross-visual-id cross))
   (define (visual-position cross)
     (cross-visual-center cross))
   (define (visual-with-position cross position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy cross-visual cross [center position]))])

;; cross-visual represents a semantic cross marker in world coordinates.
;;  - id      symbol?                 stable visual identity.
;;  - center  vec2?                   center in world coordinates.
;;  - size    positive finite real?   total width and height in world units.
;;  - fill    any/c                   opaque fill style for the Pict adapter.


;;;
;;; Custom Pict Renderer
;;;

(struct cross-pict-renderer ()
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (cross-visual? visual))
   (define (pict-renderer-render _renderer visual camera)
     (cross-visual->pict visual camera))])

;; cross-pict-renderer renders cross-visual values without changing the core
;; Visual model or the built-in renderer set.

; cross-visual->pict : cross-visual? camera? -> pict?
;;   Converts cross to two camera-scaled overlapping rectangle picts.
(define (cross-visual->pict cross camera)
  (define size
    (camera-length->pixels camera
                           (cross-visual-size cross)))
  (define thickness
    (/ size 4))
  (cc-superimpose
   (filled-rectangle size
                     thickness
                     #:draw-border? #f
                     #:color (cross-visual-fill cross))
   (filled-rectangle thickness
                     size
                     #:draw-border? #f
                     #:color (cross-visual-fill cross))))


;;;
;;; Scene Definition
;;;

; custom-renderers : (listof pict-renderer?)
;;   Gives the custom renderer before the immutable built-in renderer set.
(define custom-renderers
  (cons (cross-pict-renderer)
        default-pict-renderers))

; marker : cross-visual?
;;   Gives the custom Visual animated by the example.
(define marker
  (cross-visual 'marker (vec2 -3 0) 1 "crimson"))

; demo : scene?
;;   Gives a custom Visual movement with a visible endpoint wait.
(define demo
  (scene-wait
   (scene-play
    (scene-add (make-scene) marker)
    (move-to marker (vec2 3 0))
    #:duration 1)
   1/2))


;;;
;;; Entry Point
;;;

(module+ main
  ; frame-paths : (listof path?)
  ;;   Gives the numbered frames rendered through custom-renderers.
  (define frame-paths
    (render-frames! demo
                    "frames-custom"
                    #:fps 30
                    #:renderers custom-renderers))
  (printf "Rendered ~a custom-Visual frames\n"
          (length frame-paths)))
