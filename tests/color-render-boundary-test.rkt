#lang racket/base

;;;
;;; Color Render-Boundary Characterization Tests
;;;

;; Verifies one small literal-color path from immutable scene data to a
;; headless bitmap. Theme support must later preserve this literal result.

(require racket/class
         rackunit
         "../main.rkt"
         (only-in "../colors.rkt" aqua-c))

(define (bitmap-argb-at bitmap x y)
  (define width (send bitmap get-width))
  (define bytes (make-bytes (* 4 width (send bitmap get-height))))
  (send bitmap get-argb-pixels 0 0 width (send bitmap get-height) bytes)
  (define offset (* 4 (+ x (* y width))))
  (for/list ([index (in-range offset (+ offset 4))])
    (bytes-ref bytes index)))

(module+ test
  (define camera
    (make-camera #:width 32 #:height 24 #:world-width 4 #:background "white"))
  (define literal-scene
    (scene-wait
     (scene-add
      (make-scene #:camera camera)
      (circle #:id 'literal #:radius 1 #:fill (rgba-color 16 32 48 1) #:stroke #f))
     1))
  (define literal-frame (scene-frame->bitmap literal-scene 0 #:fps 1))
  ;; The corner is the literal camera background. The center is fully inside
  ;; the circle and therefore records its exact opaque semantic channels.
  (check-equal? (bitmap-argb-at literal-frame 0 0) '(255 255 255 255))
  (check-equal? (bitmap-argb-at literal-frame 16 12) '(255 16 32 48))

  ;; A Visual with no fill and no stroke contributes no paint; it does not turn
  ;; #f into transparent black and alter the established background result.
  (define absent-paint-scene
    (scene-wait
     (scene-add
      (make-scene #:camera camera)
      (circle #:id 'absent #:radius 1 #:fill #f #:stroke #f))
     1))
  (check-equal?
   (bitmap-argb-at (scene-frame->bitmap absent-paint-scene 0 #:fps 1) 16 12)
   '(255 255 255 255))

  ;; An authored token now resolves through the frame renderer's explicit
  ;; default theme context.  The token is not passed through to racket/draw,
  ;; and the familiar literal rendering path still receives concrete ARGB.
  (define unresolved-token-scene
    (scene-wait
     (scene-add
      (make-scene #:camera camera)
      (circle #:id 'token #:radius 1 #:fill aqua-c #:stroke #f))
     1))
  (check-equal?
   (bitmap-argb-at (scene-frame->bitmap unresolved-token-scene 0 #:fps 1) 16 12)
   '(255 25 197 206)))
