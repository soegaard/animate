#lang racket/base

;;;
;;; SCENE-CV Composable Camera Tests
;;;

;; Camera leaves now use the ordinary local scheduler. These tests cover the
;; public timing/composition vocabulary, exact handoffs, component conflicts,
;; and clip-local follow against scheduled Visual motion.

(require rackunit
         "../main.rkt")

(module+ test
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center origin
                 #:background "ivory"))

  (define dot
    (circle #:id 'dot
            #:center (vec2 -4 2)
            #:radius 1/2
            #:fill "royalblue"))

  (define base
    (scene-add (make-scene #:camera test-camera) dot))

  ;; A timed camera leaf is stationary before its local start and reaches the
  ;; exact requested endpoint independently of how frames are sampled.
  (define delayed-pan
    (scene-play
     base
     (timed (camera-pan-to (vec2 8 0))
            #:start 1
            #:duration 2)
     #:duration 4))
  (for ([time (in-list '(0 1))])
    (check-equal? (scene-camera-at delayed-pan time) test-camera))
  (check-equal? (camera-center (scene-camera-at delayed-pan 2))
                (vec2 4 0))
  (check-equal? (camera-center (scene-camera-at delayed-pan 3))
                (vec2 8 0))
  (check-equal? (scene-current-camera delayed-pan)
                (scene-camera-at delayed-pan 4))

  ;; Camera leaves occupy succession spans just like Visual leaves. The zoom
  ;; starts from the pan's exact endpoint rather than the enclosing camera.
  (define camera-succession
    (scene-play
     base
     (succession
      (camera-pan-to (vec2 8 0))
      (camera-zoom-by 2))
     #:duration 4))
  (check-equal? (camera-center (scene-camera-at camera-succession 1))
                (vec2 4 0))
  (check-equal? (camera-center (scene-camera-at camera-succession 2))
                (vec2 8 0))
  (check-equal? (camera-world-width (scene-camera-at camera-succession 2))
                20)
  (check-equal? (camera-world-width (scene-camera-at camera-succession 3))
                15)
  (check-equal? (camera-world-width (scene-camera-at camera-succession 4))
                10)

  ;; Disjoint center and width components may run in parallel.
  (define parallel-camera
    (scene-play
     base
     (animation-group
      (camera-pan-to (vec2 8 0))
      (camera-zoom-by 2))
     #:duration 4))
  (check-equal? (camera-center (scene-camera-at parallel-camera 2))
                (vec2 4 0))
  (check-equal? (camera-world-width (scene-camera-at parallel-camera 2))
                15)

  ;; Positive-measure overlap on one camera component is invalid, while the
  ;; touching boundary in camera-succession above is deliberately valid.
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"same camera component" (exn-message value))))
   (lambda ()
     (scene-play
      base
      (animation-group
       (camera-pan-to (vec2 4 0))
       (camera-pan-by (vec2 2 0)))
      #:duration 2)))

  ;; Follow has the same local lifetime as its timed wrapper. It samples the
  ;; matching Visual schedule while active, then freezes at that interval's
  ;; final camera state instead of tracking later movement.
  (define locally-followed
    (scene-play
     base
     (timed (move-to dot (vec2 4 2))
            #:start 1
            #:duration 2)
     (timed (camera-follow dot)
            #:start 1
            #:duration 2)
     #:duration 4))
  (check-equal? (camera-center (scene-camera-at locally-followed 1))
                origin)
  (check-equal? (camera-center (scene-camera-at locally-followed 2))
                (vec2 4 0))
  (check-equal? (camera-center (scene-camera-at locally-followed 3))
                (vec2 8 0))
  (check-equal? (camera-center (scene-camera-at locally-followed 4))
                (vec2 8 0))

  ;; A lagged composition uses its established span calculation for cameras as
  ;; well: with lag ratio one, the second camera request starts at the boundary.
  (define lagged-camera
    (scene-play
     base
     (lagged-start
      #:lag-ratio 1
      (camera-pan-to (vec2 4 0))
      (camera-zoom-by 2))
     #:duration 4))
  (check-equal? (camera-center (scene-camera-at lagged-camera 2))
                (vec2 4 0))
  (check-equal? (camera-world-width (scene-camera-at lagged-camera 2))
                20)
  (check-equal? (camera-world-width (scene-camera-at lagged-camera 3))
                15))
