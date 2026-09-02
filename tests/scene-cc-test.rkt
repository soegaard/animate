#lang racket/base

;;;
;;; SCENE-CC Named Layout-Anchor Tests
;;;

;; Tests the common nine-point layout-anchor vocabulary and immutable generic
;; placement/alignment built on renderer-aware layout boxes.


;;;
;;; Imports
;;;

(require rackunit
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed ten-pixels-per-world-unit measurement camera.
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20))

  ; box : layout-box?
  ;;   Gives an asymmetric box, so every named anchor has a distinct point.
  (define box
    (layout-box -2 -3 6 5))

  (for ([anchor (in-list '(bottom-left bottom bottom-right
                           left center right
                           top-left top top-right))])
    (check-true (layout-box-anchor? anchor)))
  (check-false (layout-box-anchor? 'baseline))
  (check-false (layout-box-anchor? "top-left"))

  (check-equal? (layout-box-anchor box 'bottom-left) (vec2 -2 -3))
  (check-equal? (layout-box-anchor box 'bottom) (vec2 2 -3))
  (check-equal? (layout-box-anchor box 'bottom-right) (vec2 6 -3))
  (check-equal? (layout-box-anchor box 'left) (vec2 -2 1))
  (check-equal? (layout-box-anchor box 'center) (vec2 2 1))
  (check-equal? (layout-box-anchor box 'right) (vec2 6 1))
  (check-equal? (layout-box-anchor box 'top-left) (vec2 -2 5))
  (check-equal? (layout-box-anchor box 'top) (vec2 2 5))
  (check-equal? (layout-box-anchor box 'top-right) (vec2 6 5))
  (check-exn exn:fail:contract?
             (lambda () (layout-box-anchor box 'baseline)))

  ; reference : rectangle-visual?
  ;;   Gives a four-by-two box spanning x 0..4 and y 0..2.
  (define reference
    (rectangle #:id 'reference
               #:center (vec2 2 1)
               #:width 4
               #:height 2
               #:stroke #f
               #:stroke-width 0))

  ; moving : rectangle-visual?
  ;;   Gives a two-by-four box spanning x -4..-2 and y -4..0.
  (define moving
    (rectangle #:id 'moving
               #:center (vec2 -3 -2)
               #:width 2
               #:height 4
               #:stroke #f
               #:stroke-width 0))

  (check-equal?
   (visual-layout-anchor moving 'top-right #:camera test-camera)
   (vec2 -2 0))
  (check-equal?
   (visual-layout-anchor reference 'bottom-left #:camera test-camera)
   origin)

  ;; Place any selected measured anchor at one explicit point.
  (define placed
    (visual-place-at moving
                     (vec2 10 6)
                     #:anchor 'top-right
                     #:camera test-camera))
  (check-equal? (visual-id placed) 'moving)
  (check-equal? (visual-position placed) (vec2 9 4))
  (check-equal?
   (visual-layout-anchor placed 'top-right #:camera test-camera)
   (vec2 10 6))

  ;; Align different anchors in both axes with one immutable operation.
  (define aligned
    (visual-align-to moving
                     reference
                     #:anchor 'bottom-left
                     #:reference-anchor 'top-right
                     #:camera test-camera))
  (check-equal? (visual-id aligned) 'moving)
  (check-equal? (visual-position aligned) (vec2 5 4))
  (check-equal?
   (visual-layout-anchor aligned 'bottom-left #:camera test-camera)
   (visual-layout-anchor reference 'top-right #:camera test-camera))

  ;; Defaults align box centers, while the original values remain immutable.
  (define centered
    (visual-align-to moving reference #:camera test-camera))
  (check-equal? (visual-position centered) (vec2 2 1))
  (check-equal? (visual-position moving) (vec2 -3 -2))
  (check-equal? (visual-position reference) (vec2 2 1))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (visual-place-at moving origin #:anchor 'baseline #:camera test-camera)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (visual-align-to moving
                      reference
                      #:reference-anchor 'north-west
                      #:camera test-camera))))
