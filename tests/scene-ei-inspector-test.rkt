#lang racket/base

;; SCENE-EI-4 and EI-5: inspector paths are semantic, nested, and independent
;; of the preview bitmap; camera coordinate conversion is an exact inverse.

(require rackunit
         "../main.rkt"
         "../authoring.rkt")

(module+ test
  (define leaf (circle #:id 'leaf #:center (vec2 1 0) #:radius 1))
  (define nested (group (list leaf) #:id 'nested #:center (vec2 0 2)))
  (define outer (group (list nested) #:id 'outer #:center (vec2 3 0)))
  (define scene (scene-add (make-scene) outer))
  (define tree (scene-inspection-tree scene 0))
  (check-equal? (map visual-inspection-path tree)
                '((outer) (outer nested) (outer nested leaf)))
  (define leaf-inspection
    (scene-inspect-path scene '(outer nested leaf) 0 #:source-block 'setup))
  (check-true (visual-inspection? leaf-inspection))
  (check-equal? (visual-inspection-depth leaf-inspection) 2)
  (check-equal? (visual-inspection-drawing-index leaf-inspection) 0)
  (check-equal? (visual-inspection-world-position leaf-inspection) (vec2 4 2))
  (check-equal? (visual-inspection-source-block leaf-inspection) 'setup)
  (check-true (hash-has-key? (visual-inspection-anchors leaf-inspection) 'center))
  (check-equal? (scene-paths-at scene 0)
                '((outer) (outer nested) (outer nested leaf)))

  (define inspection-camera (make-camera #:width 1000 #:height 500 #:world-width 20))
  (define-values (hit-x hit-y)
    (camera-world->pixel inspection-camera (vec2 4 2)))
  (define candidates
    (scene-hit-candidates scene 0 hit-x hit-y #:camera inspection-camera))
  (check-equal? (map visual-inspection-path candidates)
                '((outer nested leaf) (outer nested) (outer)))
  (check-equal? (visual-inspection-path
                 (scene-hit-test scene 0 hit-x hit-y #:camera inspection-camera))
                '(outer nested leaf))
  (check-equal? (visual-inspection-path
                 (scene-hit-test scene 0 hit-x hit-y #:camera inspection-camera
                                 #:after-path '(outer nested leaf)))
                '(outer nested))

  (define camera (make-camera #:width 1000 #:height 500 #:world-width 20
                              #:center (vec2 3 -2)))
  (define point (vec2 7 1))
  (define-values (pixel-x pixel-y) (camera-world->pixel camera point))
  (check-equal? (camera-pixel->world camera pixel-x pixel-y) point))
