#lang racket/base

;;;
;;; SCENE-DK Singular Reflection Rendering Tests
;;;

;; A two-dimensional identity-to-reflection interpolation has a rank-one
;; midpoint. Closed filled paths must render that midpoint as the exact open
;; geometric image rather than growing miter spikes past its endpoints.

(require racket/class
         rackunit
         "../main.rkt")

(define (nonwhite-pixel-bounds bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define pixels (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height pixels)
  (define coordinates
    (for*/list ([y (in-range height)]
                [x (in-range width)]
                #:when
                (let ([offset (* 4 (+ x (* y width)))])
                  (not (and (= (bytes-ref pixels (+ offset 1)) 255)
                            (= (bytes-ref pixels (+ offset 2)) 255)
                            (= (bytes-ref pixels (+ offset 3)) 255)))))
      (cons x y)))
  (values (apply min (map car coordinates))
          (apply max (map car coordinates))
          (apply min (map cdr coordinates))
          (apply max (map cdr coordinates))))

(module+ test
  (define camera
    (make-camera #:width 400 #:height 400 #:world-width 4
                 #:center origin #:background "white"))
  (define unit-square
    (polygon (list origin
                   (vec2 1 0)
                   (vec2 1 1)
                   (vec2 0 1))
             #:id 'unit-square #:fill "gold" #:stroke "goldenrod"
             #:stroke-width 2))
  (define reflected
    (scene-play
     (scene-add (make-scene) unit-square)
     (apply-matrix 'unit-square
                   (linear2 -1 0
                            0 1))
     #:duration 2))

  ;; The same midpoint must be exact when the square is addressed inside an
  ;; already sheared group.  This is the situation used by SCENE-DK itself.
  (define nested-reflected
    (scene-play
     (scene-play
      (scene-add (make-scene)
                 (group (list unit-square) #:id 'diagram))
      (apply-matrix 'diagram
                    (linear2 1 3/5
                             0 1))
      #:duration 2)
     (apply-matrix '(diagram unit-square)
                   (linear2 -1 0
                            0 1))
     #:duration 2))

  ;; At halfway, the map is [0 0; 0 1]. The square's image is exactly the
  ;; y=0 through y=1 segment at x=0, with only its two-pixel round stroke.
  (define-values (minimum-x maximum-x minimum-y maximum-y)
    (nonwhite-pixel-bounds
     (scene-frame->bitmap reflected 1 #:fps 1 #:camera camera)))
  (check-true (<= 198 minimum-x 200))
  (check-true (<= 199 maximum-x 201))
  (check-true (<= 98 minimum-y 101))
  (check-true (<= 199 maximum-y 202))
  (check-true (<= (- maximum-y minimum-y) 104))

  ;; After the parent shear and halfway through the child reflection, the
  ;; composed map is [0 0; 0 1], so this is the same exact vertical segment.
  (define-values (nested-minimum-x nested-maximum-x
                 nested-minimum-y nested-maximum-y)
    (nonwhite-pixel-bounds
     (scene-frame->bitmap nested-reflected 3 #:fps 1 #:camera camera)))
  (check-true (<= 198 nested-minimum-x 200))
  (check-true (<= 199 nested-maximum-x 201))
  (check-true (<= 98 nested-minimum-y 101))
  (check-true (<= 199 nested-maximum-y 202))
  (check-true (<= (- nested-maximum-y nested-minimum-y) 104)))
