#lang racket/base
(require (only-in rackunit test-suite test-case check-equal? check-true
                  check-false check-not-equal?)
         rackunit/text-ui racket/class
         (only-in pict pict->bitmap)
         (only-in racket/math pi)
         animate animate/3d animate/slides/render animate/slides/pict
         "examples/first-spatial-picture.rkt"
         "examples/spatial-motion.rkt"
         "examples/spatial-slides.rkt")
(define (view-at sc time) (scene-state-ref (scene-sample sc time) 'model))
(define (brick-at sc time)
  (view3d-spatial-ref (view-at sc time) '(model brick)))
(define (pixels picture)
  (define bm (pict->bitmap picture))
  (define bytes (make-bytes (* 4 (send bm get-width) (send bm get-height))))
  (send bm get-argb-pixels 0 0 (send bm get-width) (send bm get-height) bytes)
  bytes)
(define small-camera (make-camera #:width 320 #:height 180 #:world-width 14))
(define tests
  (test-suite "3D manual examples"
    (test-case "spatial objects and ordinary views have different protocols"
      (check-true (spatial-visual? brick))
      (check-false (visual? brick))
      (check-true (visual? model))
      (check-true (view3d? model)))
    (test-case "a still Scene has no invented duration"
      (check-equal? (scene-duration still) 0)
      (check-equal? (brick-at still 0) brick))
    (test-case "spatial movement leaves the view and camera alone"
      (check-equal? (spatial-position (brick-at translated-object 2)) (vec3 1 0 0))
      (check-equal? (visual-position (view-at translated-object 2)) (visual-position model))
      (check-equal? (view3d-camera (view-at translated-object 2)) (view3d-camera model)))
    (test-case "rotation changes the box, not the spatial camera"
      (check-not-equal? (spatial-rotation (brick-at object-motion 1)) (spatial-rotation brick))
      (check-equal? (view3d-camera (view-at object-motion 1)) (view3d-camera model)))
    (test-case "orbit changes the camera, not the box"
      (check-equal? (brick-at camera-motion 1) brick)
      (check-not-equal? (view3d-camera (view-at camera-motion 1)) (view3d-camera model)))
    (test-case "ordinary movement moves the containing 2D view"
      (check-equal? (visual-position (view-at panel-motion 2)) (vec2 2 0))
      (check-equal? (brick-at panel-motion 2) brick)
      (check-equal? (view3d-camera (view-at panel-motion 2)) (view3d-camera model)))
    (test-case "composed lesson has its two holds"
      (check-equal? (scene-duration lesson) 6)
      (check-equal? (scene-sample lesson 2) (scene-sample lesson 5/2))
      (check-equal? (scene-sample lesson 5) (scene-sample lesson 6)))
    (test-case "heading and projected label stay in the normal Scene"
      (check-equal? (scene-duration captioned-lesson) 8)
      (for ([time '(0 2 8)])
        (define state (scene-sample captioned-lesson time))
        (check-true (scene-state-has? state 'heading))
        (check-true (scene-state-has? state 'box-label)))
      (check-equal? (spatial-position (brick-at captioned-lesson 2)) (vec3 1 0 0))
      (check-true
       (positive? (bytes-length
                   (pixels (scene-state->pict (scene-sample captioned-lesson 1)
                                               #:camera small-camera))))))
    (test-case "software pictures are repeatable under reverse seeking"
      (define (frame time)
        (pixels (scene-state->pict (scene-sample lesson time) #:camera small-camera)))
      (define expected (map frame '(0 1 3 4 6)))
      (check-equal? (map frame '(6 4 3 1 0)) (reverse expected)))
    (test-case "slide holds and plays the six-second child"
      (define board (prepare-storyboard! film))
      (check-equal? (prepared-duration board) 9)
      (define (frame time) (pixels (storyboard->pict board #:at time #:size '(320 180))))
      (check-equal? (frame 0) (frame 1/2))
      (check-not-equal? (frame 1) (frame 4))
      (check-equal? (frame 7) (frame 9)))))
(module+ main (exit (if (zero? (run-tests tests)) 0 1)))
(module+ test
  (unless (zero? (run-tests tests))
    (error '3d-manual "3D example tests failed")))
