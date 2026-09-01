#lang racket/base

;;;
;;; SCENE-BG/BI SVG Semantic Import Tests
;;;

(require rackunit
         racket/runtime-path
         (only-in pict pict-height pict-width)
         "../main.rkt")

(define-runtime-path fixture "scene-bg-fixture.svg")

(module+ test
  (define imported
    (svg->visual fixture
                 #:id 'diagram
                 #:center (vec2 2 1)
                 #:scale 1/2))
  (check-true (group-visual? imported))
  (check-equal? (visual-id imported) 'diagram)
  (check-equal? (visual-position imported) (vec2 2 1))
  ;; Imported DOM IDs remain stable nested Visual paths, while element geometry
  ;; becomes ordinary built-in Visuals and styles.
  (check-equal? (map visual-id (group-visual-children imported))
                '(orbit label-box))
  (check-equal? (visual-position (car (group-visual-children imported)))
                (vec2 1 -2))
  (define scene
    (scene-add (make-scene) imported))
  (define triangle
    (scene-ref scene '(diagram orbit triangle)))
  (define curve
    (scene-ref scene '(diagram orbit curve)))
  (define planet
    (scene-ref scene '(diagram orbit planet)))
  (check-true (path-visual? triangle))
  (check-true (path-visual? curve))
  (check-true (circle-visual? planet))
  (check-equal? (path-visual-stroke triangle) "navy")
  (check-equal? (path-visual-stroke-width triangle) 2)
  (check-equal? (circle-visual-fill planet) "gold")
  (check-true
   (path-subpath-closed?
    (car (path-geometry-subpaths (path-visual-path triangle)))))
  (check-true
   (cubic-bezier-path-segment?
    (car (path-subpath-segments
          (car (path-geometry-subpaths (path-visual-path curve)))))))
  ;; SVG y coordinates are converted from screen-down to semantic world-up.
  (check-equal? (visual-position planet) (vec2 4 -6))
  ;; Existing nested targeting and style animation work on imported element IDs.
  (define animated
    (scene-play scene
                (stroke-color-to '(diagram orbit triangle) "red")
                #:duration 2))
  (check-equal? (visual-stroke-color
                 (scene-visual-at animated '(diagram orbit triangle) 1))
                (rgba-color 255/2 0 64 1))
  (define rendered
    (scene->pict scene 0
                 #:camera (make-camera #:width 120 #:height 80 #:world-width 20)))
  (check-true (positive? (pict-width rendered)))
  (check-true (positive? (pict-height rendered)))
  (check-exn exn:fail?
             (lambda ()
               (svg->visual "missing.svg" #:id 'missing))))
