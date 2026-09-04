#lang racket/base

;;;
;;; SCENE-CO Mathematical Annotation Geometry Tests
;;;

(require rackunit
         racket/class
         racket/list
         racket/runtime-path
         (only-in pict pict->bitmap)
         (only-in racket/math pi)
         "../main.rkt")

(define-runtime-path mathematical-annotations-example
  "../examples/mathematical-annotations.rkt")

(define (close? actual expected [tolerance 1e-8])
  (<= (abs (- actual expected)) tolerance))

(define (scene-bytes scene time)
  (define bitmap (pict->bitmap (scene->pict scene time) 'aligned))
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define result (make-bytes (* width height 4)))
  (send bitmap get-argb-pixels 0 0 width height result)
  result)

(module+ test
  ;; Circular arcs retain exact cardinal endpoints through cubic geometry and
  ;; store their center as their ordinary Visual reference position.
  (define quarter-arc
    (arc #:id 'quarter #:center (vec2 2 3) #:radius 2
         #:start-angle 0 #:angle (/ pi 2) #:stroke "navy"))
  (check-equal? (visual-position quarter-arc) (vec2 2 3))
  (define quarter-subpath
    (car (path-geometry-subpaths (path-visual-path quarter-arc))))
  (check-equal? (path-subpath-start quarter-subpath) (vec2 2 0))
  (check-true (cubic-bezier-path-segment?
               (car (path-subpath-segments quarter-subpath))))
  (define quarter-end
    (cubic-bezier-path-segment-end
     (car (path-subpath-segments quarter-subpath))))
  (check-true (close? (vec2-x quarter-end) 0))
  (check-true (close? (vec2-y quarter-end) 2))

  ;; Dashing selects arc-length intervals from the existing semantic path;
  ;; it neither flattens the path nor makes a renderer-specific line pattern.
  (define dashes
    (dashed-line (vec2 0 0) (vec2 2 0) #:id 'dashes
                 #:dash-length 2/5 #:gap-length 1/5))
  (define dash-geometry (path-visual-path dashes))
  (check-equal? (length (path-geometry-subpaths dash-geometry)) 4)
  (check-true (close? (path-geometry-length dash-geometry) 7/5))

  ;; Angle and right-angle marks use the two author-provided rays. They do not
  ;; pretend to infer a theorem about the enclosing diagram.
  (define angle-mark
    (angle (vec2 1 0) origin (vec2 0 1) #:id 'angle #:radius 1/2))
  (check-true (path-visual? angle-mark))
  (check-exn exn:fail:contract?
             (lambda ()
               (angle (vec2 1 0) origin (vec2 2 0) #:id 'flat)))
  (define right-mark
    (right-angle (vec2 1 0) origin (vec2 0 1) #:id 'right #:size 1/2))
  (check-equal?
   (length
    (path-subpath-segments
     (car (path-geometry-subpaths (path-visual-path right-mark)))))
   2)

  ;; A Manim-style brace is one open stroked path with outer curls and a narrow,
  ;; unfilled central cusp; brace-label groups it with a separately addressable
  ;; text child using stable, derived child identities.
  (define curly
    (brace-between (vec2 -2 0) (vec2 2 0) #:id 'curly #:offset 1/2))
  (check-equal?
   (length
    (path-geometry-subpaths (path-visual-path curly)))
   1)
  (check-false
   (path-subpath-closed?
    (car (path-geometry-subpaths (path-visual-path curly)))))
  (check-equal? (length (path-subpath-segments
                         (car (path-geometry-subpaths
                               (path-visual-path curly)))))
                6)
  (check-false (path-visual-fill curly))
  ;; The two outer curls are exact horizontal mirrors, including both Bézier
  ;; handles. This prevents a visually subtle left/right mismatch at the tips.
  (define curly-segments
    (path-subpath-segments
     (car (path-geometry-subpaths (path-visual-path curly)))))
  (define left-curl (car curly-segments))
  (define right-curl (last curly-segments))
  (define (mirror-about-brace-midpoint point)
    (vec2 (- (vec2-x point)) (vec2-y point)))
  (check-equal?
   (cubic-bezier-path-segment-control1 right-curl)
   (mirror-about-brace-midpoint
    (cubic-bezier-path-segment-control2 left-curl)))
  (check-equal?
   (cubic-bezier-path-segment-control2 right-curl)
   (mirror-about-brace-midpoint
    (cubic-bezier-path-segment-control1 left-curl)))
  ;; Curl tips are exactly aligned with the annotated endpoints, rather than
  ;; extending beyond them. This is important for braces in geometric figures.
  (define-values (brace-minimum-x _brace-minimum-y brace-maximum-x _brace-maximum-y)
    (path-geometry-bounds (path-visual-path curly)))
  (check-true (close? brace-minimum-x -2))
  (check-true (close? brace-maximum-x 2))
  (define labelled
    (brace-label (vec2 -2 0) (vec2 2 0) "base"
                 #:id 'base-brace #:offset -1/2))
  (check-true (group-visual? labelled))
  (check-equal? (map visual-id (group-visual-children labelled))
                '(base-brace-brace base-brace-label))

  ;; An enclosure uses a target's current rendered bounds and world-space
  ;; padding. A simple static target therefore matches explicit geometry.
  (define camera
    (make-camera #:width 240 #:height 160 #:world-width 20 #:background "white"))
  (define target
    (rectangle #:id 'target #:center origin #:width 2 #:height 1
               #:fill "aliceblue" #:stroke #f #:stroke-width 0))
  (define enclosure
    (surrounding-rectangle 'target #:id 'outline #:padding 1/5
                           #:fill #f #:stroke "crimson" #:stroke-width 3))
  (check-true (relation-visual? enclosure))
  (check-eq? (relation-visual-phase enclosure) 'layout)
  (check-equal?
   (relation-visual-dependencies enclosure)
   (list (selection-dependency (visual-selection '(target) '(())))))
  (define live-scene
    (scene-wait (scene-add (make-scene #:camera camera) target enclosure) 1))
  (define explicit-scene
    (scene-wait
     (scene-add
     (make-scene #:camera camera)
     target
      (make-path-visual
       (polygon-path
        (list (vec2 -6/5 -7/10) (vec2 6/5 -7/10)
              (vec2 6/5 7/10) (vec2 -6/5 7/10)))
       #:id 'outline #:center origin #:fill #f #:stroke "crimson" #:stroke-width 3))
     1))
  (check-true (bytes=? (scene-bytes live-scene 0)
                       (scene-bytes explicit-scene 0)))

  ;; The enclosure is an ordinary layout relation, so its post-resolution
  ;; opacity envelope can animate independently of the renderer measurement.
  (define faded-enclosure-scene
    (scene-play live-scene (fade-to 'outline 1/2) #:duration 1))
  (check-=
   (visual-opacity (scene-visual-at faded-enclosure-scene 'outline 2))
   1/2
   1e-9)

  (check-exn exn:fail:contract?
             (lambda ()
               (arc #:id 'bad #:radius 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (dashed-line origin origin #:id 'bad)))
  (check-exn exn:fail:contract?
             (lambda ()
               (brace-between origin origin #:id 'bad)))
  (check-exn exn:fail:contract?
             (lambda ()
               (surrounding-rectangle 'target #:id 'target)))

  ;; The stage example preserves the theorem asserted by its right-angle mark:
  ;; AB stays horizontal while AC stays vertical during its deformation.
  (define make-mathematical-annotations-example
    (dynamic-require mathematical-annotations-example 'make-demo-scene))
  (define example-scene
    (make-mathematical-annotations-example))
  (define example-a (scene-visual-at example-scene 'A 3))
  (define example-b (scene-visual-at example-scene 'B 3))
  (define example-c (scene-visual-at example-scene 'C 3))
  (define ab
    (vec2- (visual-position example-b) (visual-position example-a)))
  (define ac
    (vec2- (visual-position example-c) (visual-position example-a)))
  (check-=
   (+ (* (vec2-x ab) (vec2-x ac))
      (* (vec2-y ab) (vec2-y ac)))
   0
   1e-9)

  ;; Symmetric base motion leaves the brace-label's model position fixed. This
  ;; avoids the one-pixel-at-a-time movement inherent in a bitmap text raster.
  (define base-label-at-start
    (scene-visual-at example-scene '(annotations base-brace base-brace-label) 0))
  (define base-label-at-end
    (scene-visual-at example-scene '(annotations base-brace base-brace-label) 3))
  (check-equal? (visual-position base-label-at-start)
                (visual-position base-label-at-end)))
