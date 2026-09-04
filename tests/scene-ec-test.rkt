#lang racket/base

;;;
;;; SCENE-EC semantic paint tests
;;;

(require racket/class
         rackunit
         "../main.rkt")

(define (bitmap-rgb-at bitmap x y)
  (define width (send bitmap get-width))
  (define pixels (make-bytes (* 4 width (send bitmap get-height))))
  (send bitmap get-argb-pixels 0 0 width (send bitmap get-height) pixels)
  (define offset (* 4 (+ x (* y width))))
  (list (bytes-ref pixels (+ offset 1))
        (bytes-ref pixels (+ offset 2))
        (bytes-ref pixels (+ offset 3))))

(define (redder? rgb)
  (> (car rgb) (caddr rgb)))

(define (bluer? rgb)
  (> (caddr rgb) (car rgb)))

(module+ test
  (define source-gradient
    (linear-gradient
     (vec2 -1 0) (vec2 1 0)
     (list (paint-stop 0 "red")
           (paint-stop 1 "blue"))))
  (define destination-gradient
    (linear-gradient
     (vec2 0 -1) (vec2 0 1)
     (list (paint-stop 0 "gold")
           (paint-stop 1 "darkgreen"))))

  ;; Paint values are immutable semantic data, not backend brushes. Their
  ;; exact endpoint values survive an interpolation unchanged.
  (check-true (paint? source-gradient))
  (check-eq? (paint-lerp source-gradient destination-gradient 0)
             source-gradient)
  (check-eq? (paint-lerp source-gradient destination-gradient 1)
             destination-gradient)
  (define middle-gradient (paint-lerp source-gradient destination-gradient 1/2))
  (check-true (linear-gradient-paint? middle-gradient))
  (check-equal? (linear-gradient-paint-start middle-gradient) (vec2 -1/2 -1/2))
  (check-equal? (linear-gradient-paint-end middle-gradient) (vec2 1/2 1/2))

  (define camera
    (make-camera #:width 240 #:height 120 #:world-width 4 #:background "white"))
  (define painted-rectangle
    (rectangle #:id 'painted-rectangle #:width 2 #:height 1
               #:fill source-gradient #:stroke #f))
  (define painted-circle
    (circle #:id 'painted-circle #:center (vec2 -1 0)
            #:radius 1/2 #:fill source-gradient #:stroke #f))
  (define painted-path
    (polygon (list (vec2 1/2 -1/2) (vec2 3/2 -1/2)
                   (vec2 3/2 1/2) (vec2 1/2 1/2))
             #:id 'painted-path #:fill source-gradient #:stroke #f))
  (define static-scene
    (scene-wait
     (scene-add (make-scene #:camera camera)
                painted-rectangle)
     1))
  (define static-bitmap (scene-frame->bitmap static-scene 0 #:fps 1))
  ;; Both native closed primitives and ordinary paths use the same semantic
  ;; local coordinate endpoints: the left is redder and the right bluer.
  (check-true (redder? (bitmap-rgb-at static-bitmap 65 60)))
  (check-true (bluer? (bitmap-rgb-at static-bitmap 175 60)))
  (check-not-exn
   (lambda ()
     (scene-frame->bitmap
      (scene-wait
       (scene-add (make-scene #:camera camera) painted-circle painted-path)
       1)
      0 #:fps 1)))

  ;; Compatible structured paints animate through semantic intermediate data.
  (define animated-scene
    (scene-play
     (scene-add (make-scene #:camera camera) painted-rectangle)
     (fill-color-to 'painted-rectangle destination-gradient)
     #:duration 1))
  (define animated-middle
    (visual-fill-color
     (scene-state-ref (scene-sample animated-scene 1/2) 'painted-rectangle)))
  (check-true (linear-gradient-paint? animated-middle))
  (check-equal?
   (visual-fill-color
    (scene-state-ref (scene-sample animated-scene 1) 'painted-rectangle))
   destination-gradient)

  ;; A solid-to-gradient transition needs an explicit fade-transform or two
  ;; overlapping Visuals; inventing an interior gradient would be ambiguous.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene #:camera camera)
                 (rectangle #:id 'incompatible #:fill "red"))
      (fill-color-to 'incompatible source-gradient)
      #:duration 1)))

  ;; The deterministic checker pattern is also a semantic paint and renders as
  ;; a repeated fill rather than an image Visual.
  (define checker-scene
    (scene-wait
     (scene-add
      (make-scene #:camera camera)
      (rectangle #:id 'checker #:width 2 #:height 1 #:stroke #f
                 #:fill (checker-pattern "black" "white" #:cell-size 1/2)))
     1))
  (define checker-bitmap (scene-frame->bitmap checker-scene 0 #:fps 1))
  (check-false
   (equal? (bitmap-rgb-at checker-bitmap 80 60)
           (bitmap-rgb-at checker-bitmap 110 60))))
