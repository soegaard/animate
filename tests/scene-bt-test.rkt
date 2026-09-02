#lang racket/base

;;;
;;; SCENE-BT/BU Animated Write Tests
;;;

;; Verifies the two-phase vector write model, Manim-style curve timing, reverse
;; writing/removal, SVG shape normalisation, and dvisvgm <defs>/<use> expansion
;; for tagged formulas.

(require rackunit
         racket/runtime-path
         (only-in pict pict?)
         "../main.rkt")

(define-runtime-path svg-fixture "scene-bg-fixture.svg")

(module+ test
  (define filled
    (polygon (list (vec2 -1 -1)
                   (vec2 1 -1)
                   (vec2 0 1))
             #:id 'filled
             #:fill "royalblue"
             #:stroke #f))
  (check-true (write-in-request? (write-in filled)))

  (define filled-scene
    (scene-play (make-scene) (write-in filled) #:duration 1))
  (define filled-start
    (scene-state-ref (scene-sample filled-scene 0) 'filled))
  (define filled-quarter
    (scene-state-ref (scene-sample filled-scene 1/4) 'filled))
  (define filled-three-quarters
    (scene-state-ref (scene-sample filled-scene 3/4) 'filled))
  (check-true (path-geometry-empty? (path-visual-path filled-start)))
  (check-false (path-geometry-empty? (path-visual-path filled-quarter)))
  ;; DrawBorderThenFill keeps the full outline, while the fill has begun an
  ;; alpha transition only in the second half of the leaf's interval.
  (check-true (rgba-color? (path-visual-fill filled-three-quarters)))
  (check-equal? (rgba-color-alpha (path-visual-fill filled-three-quarters))
                1/2)
  (check-eq? (scene-state-ref (scene-current-state filled-scene) 'filled)
             filled)

  ;; With no explicit #:duration, write-in follows Manim's leaf-count default:
  ;; one second for fewer than fifteen leaves and two seconds otherwise.
  (define many-leaves
    (group
     (for/list ([index (in-range 15)])
       (line (vec2 index 0)
             (vec2 (+ index 1/2) 0)
             #:id (string->symbol (format "stroke-~a" index))))
     #:id 'many-leaves))
  (check-equal? (scene-duration
                 (scene-play (make-scene) (write-in filled)))
                1)
  (check-equal? (scene-duration
                 (scene-play (make-scene) (write-in many-leaves)))
                2)
  (check-equal? (scene-duration
                 (scene-play (make-scene)
                             (write-in many-leaves)
                             #:duration 3))
                3)

  (define ordered-drawing
    (group
     (list (line (vec2 -3 0) (vec2 -1 0) #:id 'first)
           (circle #:id 'second #:center (vec2 2 0) #:radius 1))
     #:id 'ordered-drawing))
  (define ordered-scene
    (scene-play (make-scene)
                (write-in ordered-drawing #:lag-ratio 1/2)
                #:duration 1))
  (define early-drawing
    (scene-state-ref (scene-sample ordered-scene 1/10) 'ordered-drawing))
  (define early-children (group-visual-children early-drawing))
  (check-false (path-geometry-empty?
                (path-visual-path (car early-children))))
  (check-true (path-geometry-empty?
               (path-visual-path (cadr early-children))))
  ;; A circle is a temporary cubic path during writing, then the original
  ;; semantic circle is restored at the endpoint.
  (check-true (path-visual? (cadr early-children)))
  (check-eq? (scene-state-ref (scene-current-state ordered-scene)
                              'ordered-drawing)
             ordered-drawing)

  ;; The semantic SVG importer produces paths, rectangles, and circles.  All
  ;; three kinds are normalised into one write proxy and the original SVG tree
  ;; is restored exactly at completion.
  (define imported
    (svg->visual svg-fixture #:id 'imported))
  (define svg-scene
    (scene-play (make-scene) (write-in imported) #:duration 1))
  (check-true
   (group-visual?
    (scene-state-ref (scene-sample svg-scene 1/2) 'imported)))
  (check-true
   (pict?
    (scene->pict svg-scene 1/2
                 #:camera (make-camera #:width 240 #:height 135 #:world-width 16))))
  (check-eq? (scene-state-ref (scene-current-state svg-scene) 'imported)
             imported)

  ;; Tagged formulas are still typeset once at construction.  Their dvisvgm
  ;; defs/use glyphs become temporary paths only when write-in is compiled.
  (define formula
    (tagged-formula
     #:id 'formula
     #:font-size 2/5
     (formula-fragment 'a "a^2")
     (formula-fragment 'plus "+")
     (formula-fragment 'fraction "\\frac{b}{c}")))
  (define formula-scene
    (scene-play (make-scene) (write-in formula) #:duration 1))
  (check-true
   (group-visual?
    (scene-state-ref (scene-sample formula-scene 1/2) 'formula)))
  (check-true
   (pict?
    (scene->pict formula-scene 1/2
                 #:camera (make-camera #:width 240 #:height 135 #:world-width 16))))
  (check-eq? (scene-state-ref (scene-current-state formula-scene) 'formula)
             formula)

  ;; Manim reveals a VMobject by its ordered Bézier curves, not by physical
  ;; arc length.  These two straight curve slots have very different lengths:
  ;; halfway through the outline phase the default write ends exactly at their
  ;; boundary, while the explicit arc-length mode is well into the second one.
  (define uneven-path
    (polyline-path
     (list (vec2 0 0)
           (vec2 1 0)
           (vec2 10 0))))
  (define uneven
    (make-path-visual uneven-path
                      #:id 'uneven
                      #:stroke "black"
                      #:stroke-width 1))
  (define curve-write-scene
    (scene-play (make-scene) (write-in uneven) #:duration 1))
  (define arc-write-scene
    (scene-play (make-scene)
                (write-in uneven #:reveal 'arc-length)
                #:duration 1))
  (check-equal?
   (path-geometry-subpath-points
    (path-visual-path
     (scene-state-ref (scene-sample curve-write-scene 1/4) 'uneven)))
   (list (list (vec2 0 0) (vec2 1 0))))
  (check-equal?
   (path-geometry-subpath-points
    (path-visual-path
     (scene-state-ref (scene-sample arc-write-scene 1/4) 'uneven)))
   (list (list (vec2 0 0) (vec2 1 0) (vec2 5 0))))

  ;; Clip easing is evaluated after each leaf's offset.  At one half of this
  ;; two-leaf clip, the first leaf is already in its paint phase and the second
  ;; has begun its outline phase; globally easing the clock first would leave
  ;; the second leaf absent and the first still incomplete.
  (define (square progress) (* progress progress))
  (define locally-eased-scene
    (scene-play (make-scene)
                (write-in ordered-drawing #:lag-ratio 1/2)
                #:duration 1
                #:easing square))
  (define locally-eased-half
    (scene-state-ref (scene-sample locally-eased-scene 1/2) 'ordered-drawing))
  (check-equal?
   (path-visual-path (car (group-visual-children locally-eased-half)))
   (path-visual-path (car (group-visual-children ordered-drawing))))
  (check-false
   (path-geometry-empty?
    (path-visual-path (cadr (group-visual-children locally-eased-half)))))

  ;; Reversing starts with the last document leaf and traces each path from its
  ;; end.  The final scene nevertheless restores the caller's exact endpoint.
  (define reverse-scene
    (scene-play (make-scene)
                (write-in ordered-drawing #:lag-ratio 1/2 #:reverse? #t)
                #:duration 1))
  (define reverse-early
    (scene-state-ref (scene-sample reverse-scene 1/10) 'ordered-drawing))
  (check-true
   (path-geometry-empty?
    (path-visual-path (car (group-visual-children reverse-early)))))
  (check-false
   (path-geometry-empty?
    (path-visual-path (cadr (group-visual-children reverse-early)))))
  (check-eq? (scene-state-ref (scene-current-state reverse-scene)
                              'ordered-drawing)
             ordered-drawing)
  (define reversed-uneven-scene
    (scene-play (make-scene) (write-in uneven #:reverse? #t) #:duration 1))
  (check-equal?
   (path-geometry-subpath-points
   (path-visual-path
     (scene-state-ref (scene-sample reversed-uneven-scene 1/4) 'uneven)))
   (list (list (vec2 10 0) (vec2 1 0))))
  ;; Reversal applies to the temporary outline trace only.  Once paint begins,
  ;; use the source geometry unchanged, which preserves the orientation of a
  ;; glyph's closed contours and therefore its holes.
  (define reverse-filled-scene
    (scene-play (make-scene) (write-in filled #:reverse? #t) #:duration 1))
  (check-equal?
   (path-visual-path
    (scene-state-ref (scene-sample reverse-filled-scene 3/4) 'filled))
   (path-visual-path filled))

  ;; An unwrite starts from the exact current Visual, removes leaves in reverse
  ;; order, and structurally removes the target when its clip completes.
  (define unwrite-scene
    (scene-play (scene-add (make-scene) ordered-drawing)
                (unwrite 'ordered-drawing #:lag-ratio 1/2)
                #:duration 1))
  (check-true (unwrite-request? (unwrite ordered-drawing)))
  (check-eq? (scene-state-ref (scene-sample unwrite-scene 0)
                              'ordered-drawing)
             ordered-drawing)
  (define unwrite-early
    (scene-state-ref (scene-sample unwrite-scene 3/4) 'ordered-drawing))
  (check-true
   (path-geometry-empty?
    (path-visual-path (cadr (group-visual-children unwrite-early)))))
  (check-false
   (path-geometry-empty?
    (path-visual-path (car (group-visual-children unwrite-early)))))
  (check-false
   (scene-state-has? (scene-current-state unwrite-scene) 'ordered-drawing)))
