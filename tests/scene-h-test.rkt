#lang racket/base

;;;
;;; SCENE-H Model Tests
;;;

;; Tests structural path compatibility, pointwise path interpolation, morph-to
;; compilation, simultaneous transform components, and deterministic sampling.


;;;
;;; Imports
;;;

(require rackunit
         "../main.rkt")


(module+ test
  ; exception-message-matches? : regexp? -> (-> any/c boolean?)
  ;;   Creates an exception predicate that checks a contract-error message.
  (define (exception-message-matches? pattern)
    (lambda (exception)
      (and (exn:fail:contract? exception)
           (regexp-match? pattern (exn-message exception)))))

  ; square-path : path-geometry?
  ;;   Gives one centered closed four-vertex line path.
  (define square-path
    (polygon-path
     (list (vec2 -2 -1)
           (vec2 2 -1)
           (vec2 2 1)
           (vec2 -2 1))))

  ; diamond-path : path-geometry?
  ;;   Gives a compatible centered closed four-vertex line path.
  (define diamond-path
    (polygon-path
     (list (vec2 0 -2)
           (vec2 3 0)
           (vec2 0 2)
           (vec2 -3 0))))

  ; trapezoid-path : path-geometry?
  ;;   Gives another compatible centered closed four-vertex line path.
  (define trapezoid-path
    (polygon-path
     (list (vec2 -3 -1)
           (vec2 3 -1)
           (vec2 2 2)
           (vec2 -2 2))))

  ;; Compatible paths have the same subpath count, closure values, segment
  ;; counts, and segment kinds in the same order.

  (check-true
   (path-geometry-morph-compatible? square-path diamond-path))
  (check-true
   (path-geometry-morph-compatible? empty-path-geometry
                                    empty-path-geometry))

  ; point-path-a : path-geometry?
  ;;   Gives one point-only open subpath.
  (define point-path-a
    (path-geometry
     (list (path-subpath (vec2 -1 0) '() #f))))

  ; point-path-b : path-geometry?
  ;;   Gives a compatible point-only open subpath.
  (define point-path-b
    (path-geometry
     (list (path-subpath (vec2 3 2) '() #f))))

  (check-true
   (path-geometry-morph-compatible? point-path-a point-path-b))
  (check-equal?
   (path-geometry-lerp point-path-a point-path-b 1/2)
   (path-geometry
    (list (path-subpath (vec2 1 1) '() #f))))

  ; triangle-path : path-geometry?
  ;;   Gives an incompatible closed path with fewer line segments.
  (define triangle-path
    (polygon-path
     (list (vec2 -2 -1)
           (vec2 2 -1)
           (vec2 0 2))))

  ; open-square-path : path-geometry?
  ;;   Gives the square vertices as an incompatible open subpath.
  (define open-square-path
    (polyline-path
     (list (vec2 -2 -1)
           (vec2 2 -1)
           (vec2 2 1)
           (vec2 -2 1))))

  ; extra-subpath-path : path-geometry?
  ;;   Gives two point-only subpaths instead of one.
  (define extra-subpath-path
    (path-geometry
     (list (path-subpath origin '() #f)
           (path-subpath (vec2 1 1) '() #f))))

  ; cubic-single-path : path-geometry?
  ;;   Gives one cubic segment for a segment-kind mismatch test.
  (define cubic-single-path
    (cubic-bezier-path
     origin
     (list
      (cubic-bezier-path-segment (vec2 1 1)
                                 (vec2 2 1)
                                 (vec2 3 0)))))

  ; line-single-path : path-geometry?
  ;;   Gives one line segment for a segment-kind mismatch test.
  (define line-single-path
    (polyline-path
     (list origin (vec2 3 0))))

  (check-false
   (path-geometry-morph-compatible? square-path triangle-path))
  (check-false
   (path-geometry-morph-compatible? square-path open-square-path))
  (check-false
   (path-geometry-morph-compatible? point-path-a extra-subpath-path))
  (check-false
   (path-geometry-morph-compatible? line-single-path cubic-single-path))

  (check-exn
   (exception-message-matches? #rx"different segment counts")
   (lambda ()
     (path-geometry-lerp square-path triangle-path 1/2)))
  (check-exn
   (exception-message-matches? #rx"different closure values")
   (lambda ()
     (path-geometry-lerp square-path open-square-path 1/2)))
  (check-exn
   (exception-message-matches? #rx"different subpath counts")
   (lambda ()
     (path-geometry-lerp point-path-a extra-subpath-path 1/2)))
  (check-exn
   (exception-message-matches? #rx"different kinds")
   (lambda ()
     (path-geometry-lerp line-single-path cubic-single-path 1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-lerp square-path diamond-path -1/10)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-lerp square-path diamond-path 11/10)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-lerp square-path diamond-path +inf.0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-lerp square-path diamond-path +nan.0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-morph-compatible? square-path 'not-a-path)))

  ;; Endpoint interpolation preserves the original path values. Interior
  ;; interpolation preserves subpath order, closure, and segment kinds.

  (check-eq? (path-geometry-lerp square-path diamond-path 0)
             square-path)
  (check-eq? (path-geometry-lerp square-path diamond-path 1)
             diamond-path)

  ; line-midpoint-path : path-geometry?
  ;;   Gives the midpoint between square-path and diamond-path.
  (define line-midpoint-path
    (path-geometry-lerp square-path diamond-path 1/2))

  ; line-midpoint-subpath : path-subpath?
  ;;   Gives the sole midpoint subpath.
  (define line-midpoint-subpath
    (car (path-geometry-subpaths line-midpoint-path)))

  (check-true (path-subpath-closed? line-midpoint-subpath))
  (check-equal?
   (path-subpath-points line-midpoint-subpath)
   (list (vec2 -1 -3/2)
         (vec2 5/2 -1/2)
         (vec2 1 3/2)
         (vec2 -5/2 1/2)))
  (check-true
   (andmap line-path-segment?
           (path-subpath-segments line-midpoint-subpath)))

  ;; Cubic controls and endpoints interpolate independently.

  ; cubic-from-path : path-geometry?
  ;;   Gives a two-segment cubic wave.
  (define cubic-from-path
    (cubic-bezier-path
     (vec2 -3 0)
     (list
      (cubic-bezier-path-segment (vec2 -2 2)
                                 (vec2 -1 2)
                                 origin)
      (cubic-bezier-path-segment (vec2 1 -2)
                                 (vec2 2 -2)
                                 (vec2 3 0)))))

  ; cubic-to-path : path-geometry?
  ;;   Gives a compatible two-segment cubic arch.
  (define cubic-to-path
    (cubic-bezier-path
     (vec2 -3 -1)
     (list
      (cubic-bezier-path-segment (vec2 -2 -1)
                                 (vec2 -1 3)
                                 (vec2 0 3))
      (cubic-bezier-path-segment (vec2 1 3)
                                 (vec2 2 -1)
                                 (vec2 3 -1)))))

  ; cubic-midpoint-path : path-geometry?
  ;;   Gives the pointwise midpoint of the two cubic paths.
  (define cubic-midpoint-path
    (path-geometry-lerp cubic-from-path cubic-to-path 1/2))

  ; cubic-midpoint-subpath : path-subpath?
  ;;   Gives the sole midpoint cubic subpath.
  (define cubic-midpoint-subpath
    (car (path-geometry-subpaths cubic-midpoint-path)))

  ; cubic-midpoint-first-segment : cubic-bezier-path-segment?
  ;;   Gives the first interpolated cubic segment.
  (define cubic-midpoint-first-segment
    (car (path-subpath-segments cubic-midpoint-subpath)))

  (check-equal? (path-subpath-start cubic-midpoint-subpath)
                (vec2 -3 -1/2))
  (check-equal?
   (cubic-bezier-path-segment-control1 cubic-midpoint-first-segment)
   (vec2 -2 1/2))
  (check-equal?
   (cubic-bezier-path-segment-control2 cubic-midpoint-first-segment)
   (vec2 -1 5/2))
  (check-equal?
   (cubic-bezier-path-segment-end cubic-midpoint-first-segment)
   (vec2 0 3/2))

  ;; Compound paths preserve corresponding subpath order and segment kinds.

  ; compound-from-path : path-geometry?
  ;;   Gives an open line subpath followed by an open cubic subpath.
  (define compound-from-path
    (path-geometry
     (list
      (path-subpath (vec2 -4 0)
                    (list (line-path-segment (vec2 -2 0)))
                    #f)
      (path-subpath origin
                    (list
                     (cubic-bezier-path-segment (vec2 1 1)
                                                (vec2 2 1)
                                                (vec2 3 0)))
                    #f))))

  ; compound-to-path : path-geometry?
  ;;   Gives compatible line and cubic subpaths at new local points.
  (define compound-to-path
    (path-geometry
     (list
      (path-subpath (vec2 -2 2)
                    (list (line-path-segment (vec2 0 2)))
                    #f)
      (path-subpath (vec2 0 -2)
                    (list
                     (cubic-bezier-path-segment (vec2 1 -1)
                                                (vec2 2 -1)
                                                (vec2 3 -2)))
                    #f))))

  ; compound-midpoint-path : path-geometry?
  ;;   Gives the midpoint with the original subpath order intact.
  (define compound-midpoint-path
    (path-geometry-lerp compound-from-path compound-to-path 1/2))

  (check-true
   (path-geometry-morph-compatible? compound-from-path compound-to-path))
  (check-equal?
   (path-geometry-subpath-points compound-midpoint-path)
   (list (list (vec2 -3 1) (vec2 -1 1))
         (list (vec2 0 -1) (vec2 3 -1))))
  (check-true
   (line-path-segment?
    (car
     (path-subpath-segments
      (car (path-geometry-subpaths compound-midpoint-path))))))
  (check-true
   (cubic-bezier-path-segment?
    (car
     (path-subpath-segments
      (cadr (path-geometry-subpaths compound-midpoint-path))))))

  ;; morph-to changes only local path geometry. Identity, style, affine
  ;; placement, and drawing order are preserved.

  ; panel : path-visual?
  ;;   Gives the initial styled path Visual.
  (define panel
    (make-path-visual square-path
                      #:id 'panel
                      #:center (vec2 -2 1)
                      #:rotation 1/4
                      #:scale (vec2 1 2)
                      #:fill "cornflowerblue"
                      #:stroke "navy"
                      #:stroke-width 5))

  (check-true (morph-to-request? (morph-to panel diamond-path)))
  (check-true (morph-to-request? (morph-to 'panel diamond-path)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to (circle #:id 'not-a-path)
                         diamond-path)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to panel 'not-path-geometry)))

  ; backdrop : rectangle-visual?
  ;;   Gives an unrelated Visual behind panel.
  (define backdrop
    (rectangle #:id 'backdrop
               #:center (vec2 0 0)
               #:width 8
               #:height 6
               #:fill "whitesmoke"))

  ; morph-start-scene : scene?
  ;;   Gives a scene with backdrop behind panel.
  (define morph-start-scene
    (scene-add (make-scene) backdrop panel))

  ; morph-scene : scene?
  ;;   Gives a two-second path morph with simultaneous affine changes.
  (define morph-scene
    (scene-play
     morph-start-scene
     (morph-to panel diamond-path)
     (move-to panel (vec2 2 -1))
     (rotate-to panel 5/4)
     (scale-to panel (vec2 2 1/2))
     #:duration 2))

  ; morph-midpoint : path-visual?
  ;;   Gives panel halfway through all four animation components.
  (define morph-midpoint
    (scene-state-ref (scene-sample morph-scene 1)
                     'panel))

  (check-equal? (visual-id morph-midpoint) 'panel)
  (check-equal? (path-visual-path morph-midpoint)
                line-midpoint-path)
  (check-equal? (visual-position morph-midpoint)
                origin)
  (check-equal? (visual-rotation morph-midpoint)
                3/4)
  (check-equal? (visual-scale morph-midpoint)
                (vec2 3/2 5/4))
  (check-equal? (path-visual-fill morph-midpoint)
                "cornflowerblue")
  (check-equal? (path-visual-stroke morph-midpoint)
                "navy")
  (check-equal? (path-visual-stroke-width morph-midpoint)
                5)
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order
         (scene-sample morph-scene 1)))
   '(backdrop panel))
  (check-eq?
   (scene-state-ref (scene-sample morph-scene 1) 'backdrop)
   backdrop)

  ; reordered-morph-scene : scene?
  ;;   Gives the same disjoint requests in a different order.
  (define reordered-morph-scene
    (scene-play
     morph-start-scene
     (scale-to panel (vec2 2 1/2))
     (rotate-to panel 5/4)
     (move-to panel (vec2 2 -1))
     (morph-to panel diamond-path)
     #:duration 2))

  (check-equal?
   (scene-state-ref (scene-sample reordered-morph-scene 1) 'panel)
   morph-midpoint)

  ; morph-endpoint : path-visual?
  ;;   Gives panel at the structural scene endpoint.
  (define morph-endpoint
    (scene-state-ref (scene-sample morph-scene 2)
                     'panel))

  (check-eq? (path-visual-path morph-endpoint)
             diamond-path)
  (check-equal? (visual-position morph-endpoint)
                (vec2 2 -1))
  (check-equal? (visual-rotation morph-endpoint)
                5/4)
  (check-equal? (visual-scale morph-endpoint)
                (vec2 2 1/2))

  ;; A later morph compiles from the complete current path, not from the
  ;; Visual value originally passed to the earlier request.

  ; second-morph-scene : scene?
  ;;   Gives a later morph from diamond-path to trapezoid-path.
  (define second-morph-scene
    (scene-play morph-scene
                (morph-to 'panel trapezoid-path)
                #:duration 1))

  (check-equal?
   (path-visual-path
    (scene-state-ref (scene-sample second-morph-scene 5/2)
                     'panel))
   (path-geometry-lerp diamond-path trapezoid-path 1/2))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample second-morph-scene 3)
                     'panel))
   trapezoid-path)

  ;; Path morphs share one animation component with Create and Uncreate.

  (check-exn exn:fail?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to panel diamond-path)
                (morph-to panel trapezoid-path))))
  (check-exn exn:fail?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to panel diamond-path)
                (uncreate panel))))
  (check-exn exn:fail?
             (lambda ()
               (scene-play
                (make-scene)
                (create panel)
                (morph-to 'panel diamond-path))))

  ;; Compilation rejects missing, non-path, and incompatible targets.

  (check-exn exn:fail?
             (lambda ()
               (scene-play (make-scene)
                           (morph-to 'missing diamond-path))))
  (check-exn
   (exception-message-matches? #rx"morph-to requires a path Visual")
   (lambda ()
     (scene-play
      (scene-add (make-scene)
                 (circle #:id 'dot))
      (morph-to 'dot diamond-path))))
  (check-exn
   (exception-message-matches? #rx"different segment counts")
   (lambda ()
     (scene-play
      (scene-add (make-scene) panel)
      (morph-to panel triangle-path))))

  ;; Like translation, rotation, and scale, a morph follows the easing result.
  ;; An unusual easing that returns zero leaves the path at its start value.

  ; held-morph-scene : scene?
  ;;   Gives a morph whose easing never advances.
  (define held-morph-scene
    (scene-play (scene-add (make-scene) panel)
                (morph-to panel diamond-path)
                #:duration 1
                #:easing (lambda (_progress) 0)))

  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample held-morph-scene 1)
                     'panel))
   square-path))
