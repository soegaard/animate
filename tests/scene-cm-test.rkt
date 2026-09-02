#lang racket/base

;;;
;;; SCENE-CM Live Anchor Constraint Tests
;;;

;; A layout attachment is resolved only after a scene sample has supplied the
;; moving target and the active renderer/camera.  These pixel comparisons prove
;; it matches the equivalent explicit placement at both a static and a scaled,
;; translated interior sample.

(require rackunit
         racket/class
         (only-in pict pict->bitmap)
         "../main.rkt")

(define (bitmap->argb-bytes bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define result (make-bytes (* width height 4)))
  (send bitmap get-argb-pixels 0 0 width height result)
  result)

(define (scene-bytes scene time)
  (bitmap->argb-bytes
   (pict->bitmap (scene->pict scene time) 'aligned)))

(module+ test
  (define camera
    (make-camera #:width 240 #:height 160 #:world-width 20 #:background "white"))
  (define target
    (rectangle #:id 'target #:center origin #:width 2 #:height 1
               #:fill "aliceblue" #:stroke #f #:stroke-width 0))
  (define attached-marker
    (attach-to
     (circle #:id 'marker #:center origin #:radius 1/5
             #:fill "crimson" #:stroke #f #:stroke-width 0)
     'target
     #:target-anchor 'right
     #:self-anchor 'left
     #:offset (vec2 1/10 0)))

  ;; Centre-to-centre remains SCENE-CD's pure derived-Visual convenience, while
  ;; an edge anchor selects SCENE-CM's renderer-aware layout wrapper.
  (check-true (derived-visual?
               (attach-to
                (circle #:id 'centre-marker #:radius 1/5)
                'target)))
  (check-true (layout-attached-visual? attached-marker))
  (check-equal? (layout-attached-visual-target-anchor attached-marker) 'right)
  (check-equal? (layout-attached-visual-self-anchor attached-marker) 'left)

  ;; The target's right edge is x = 1; placing the marker's left edge one tenth
  ;; beyond it puts the marker centre at x = 13/10.
  (define attached-static
    (scene-wait
     (scene-add (make-scene #:camera camera) target attached-marker)
     1))
  (define explicit-static
    (scene-wait
     (scene-add
      (make-scene #:camera camera)
      target
      (circle #:id 'marker #:center (vec2 13/10 0) #:radius 1/5
              #:fill "crimson" #:stroke #f #:stroke-width 0))
     1))
  (check-equal? (scene-bytes attached-static 0)
                (scene-bytes explicit-static 0))

  ;; At one-half progress of the second clip (time 3/2) the target is centred
  ;; at x = 1 and has width 3, so
  ;; its live right edge is x = 5/2.  The same marker centre is then 14/5.
  (define animated
    (scene-play attached-static
                (move-to 'target (vec2 2 0))
                (scale-to 'target 2)
                #:duration 1))
  (define explicit-middle
    (scene-wait
     (scene-add
      (make-scene #:camera camera)
      (rectangle #:id 'target #:center (vec2 1 0) #:width 2 #:height 1
                 #:scale 3/2
                 #:fill "aliceblue" #:stroke #f #:stroke-width 0)
      (circle #:id 'marker #:center (vec2 14/5 0) #:radius 1/5
              #:fill "crimson" #:stroke #f #:stroke-width 0))
     1))
  (define sampled-middle-target
    (scene-state-ref (scene-sample animated 3/2) 'target))
  (check-equal? (visual-position sampled-middle-target) (vec2 1 0))
  (check-equal? (visual-scale sampled-middle-target) (vec2 3/2 3/2))
  (check-true (bytes=? (scene-bytes animated 3/2)
                       (scene-bytes explicit-middle 0)))
  ;; Rendering the same arbitrary sample twice does not depend on a prior
  ;; rendered frame.
  (check-true (bytes=? (scene-bytes animated 3/2)
                       (scene-bytes animated 3/2)))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (attach-to target 'target #:target-anchor 'right)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (attach-to
      (circle #:id 'bad-anchor #:radius 1/5)
      'target
      #:target-anchor 'diagonal)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-state->pict
      (scene-current-state
       (scene-add
        (make-scene #:camera camera)
        target
        (attach-to
         (circle #:id 'bad-frame-target #:radius 1/5)
         (fixed-in-frame (plain-text "fixed" #:id 'overlay) #:camera camera)
         #:target-anchor 'top)))
      #:camera camera)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-state->pict
      (scene-current-state
       (scene-add
        (make-scene #:camera camera)
        target
        attached-marker
        (attach-to
         (circle #:id 'chained-marker #:radius 1/5)
         'marker
         #:target-anchor 'right)))
      #:camera camera))))
