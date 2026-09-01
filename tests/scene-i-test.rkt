#lang racket/base

;;;
;;; SCENE-I Model Tests
;;;

;; Tests deterministic cubic path normalization, limited incompatible morphs,
;; normalized timeline requests, exact endpoints, and component conflicts.


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

  ; first-subpath : path-geometry? -> path-subpath?
  ;;   Returns the first subpath of nonempty geometry.
  (define (first-subpath geometry)
    (car (path-geometry-subpaths geometry)))

  ; subpath-segments : path-geometry? -> (listof path-segment?)
  ;;   Returns the first subpath's ordered segments.
  (define (subpath-segments geometry)
    (path-subpath-segments (first-subpath geometry)))

  ; all-cubic-segments? : path-geometry? -> boolean?
  ;;   Reports whether every stored segment is cubic Bézier geometry.
  (define (all-cubic-segments? geometry)
    (andmap
     (lambda (subpath)
       (andmap cubic-bezier-path-segment?
               (path-subpath-segments subpath)))
     (path-geometry-subpaths geometry)))

  ;; Straight lines convert to exact equivalent cubic Bézier segments.

  ; straight-line : path-geometry?
  ;;   Gives one horizontal line of length three.
  (define straight-line
    (polyline-path
     (list origin (vec2 3 0))))

  ; cubic-line : path-geometry?
  ;;   Gives straight-line after semantic cubic conversion.
  (define cubic-line
    (path-geometry->cubic straight-line))

  ; cubic-line-segment : cubic-bezier-path-segment?
  ;;   Gives the converted straight segment.
  (define cubic-line-segment
    (car (subpath-segments cubic-line)))

  (check-true (cubic-bezier-path-segment? cubic-line-segment))
  (check-equal?
   (cubic-bezier-path-segment-control1 cubic-line-segment)
   (vec2 1 0))
  (check-equal?
   (cubic-bezier-path-segment-control2 cubic-line-segment)
   (vec2 2 0))
  (check-equal?
   (cubic-bezier-path-segment-end cubic-line-segment)
   (vec2 3 0))
  (check-false
   (cubic-bezier-path-segment?
    (car (subpath-segments straight-line))))
  (check-equal? (path-geometry-length cubic-line)
                (path-geometry-length straight-line))

  ; cubic-arch : path-geometry?
  ;;   Gives one already-cubic path.
  (define cubic-arch
    (cubic-bezier-path
     (vec2 -2 0)
     (list
      (cubic-bezier-path-segment (vec2 -2 2)
                                 (vec2 2 2)
                                 (vec2 2 0)))))

  (check-eq? (path-geometry->cubic cubic-arch)
             cubic-arch)
  (check-eq? (path-geometry->cubic empty-path-geometry)
             empty-path-geometry)
  (check-true
   (path-geometry-morph-normalizable? empty-path-geometry
                                      empty-path-geometry))

  (define-values (normalized-empty-left normalized-empty-right)
    (path-geometry-normalize-for-morph empty-path-geometry
                                       empty-path-geometry))

  (check-eq? normalized-empty-left empty-path-geometry)
  (check-eq? normalized-empty-right empty-path-geometry)
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry->cubic 'not-a-path)))

  ;; A triangle and a quadrilateral are not strictly compatible, but limited
  ;; normalization can cubicize and split their corresponding closed subpaths.

  ; triangle-path : path-geometry?
  ;;   Gives a closed three-edge line path with two stored segments.
  (define triangle-path
    (polygon-path
     (list (vec2 -3 -1)
           (vec2 3 -1)
           (vec2 0 2))))

  ; rectangle-path : path-geometry?
  ;;   Gives a closed four-edge line path with three stored segments.
  (define rectangle-path
    (polygon-path
     (list (vec2 -3 -2)
           (vec2 3 -2)
           (vec2 3 2)
           (vec2 -3 2))))

  (check-false
   (path-geometry-morph-compatible? triangle-path rectangle-path))
  (check-true
   (path-geometry-morph-normalizable? triangle-path rectangle-path))

  (define-values (normalized-triangle normalized-rectangle)
    (path-geometry-normalize-for-morph triangle-path rectangle-path))

  (check-true
   (path-geometry-morph-compatible? normalized-triangle
                                    normalized-rectangle))
  (check-true (all-cubic-segments? normalized-triangle))
  (check-true (all-cubic-segments? normalized-rectangle))
  (check-equal? (length (subpath-segments normalized-triangle))
                3)
  (check-equal? (length (subpath-segments normalized-rectangle))
                3)
  (check-true (path-subpath-closed? (first-subpath normalized-triangle)))
  (check-true (path-subpath-closed? (first-subpath normalized-rectangle)))
  (check-equal? (path-subpath-start (first-subpath normalized-triangle))
                (path-subpath-start (first-subpath triangle-path)))
  (check-= (path-geometry-length normalized-triangle)
           (path-geometry-length triangle-path)
           1e-8)
  (check-= (path-geometry-length normalized-rectangle)
           (path-geometry-length rectangle-path)
           1e-8)

  ;; The longest current segment is split at parameter one half. Equal-length
  ;; ties are resolved by the earliest segment in traversal order.

  ; unequal-source : path-geometry?
  ;;   Gives stored line segments of lengths four and one.
  (define unequal-source
    (polyline-path
     (list origin (vec2 4 0) (vec2 5 0))))

  ; three-segment-target : path-geometry?
  ;;   Gives three stored line segments for count normalization.
  (define three-segment-target
    (polyline-path
     (list origin (vec2 1 1) (vec2 3 1) (vec2 5 0))))

  (define-values (normalized-unequal _normalized-three-segment-target)
    (path-geometry-normalize-for-morph unequal-source
                                       three-segment-target))

  (check-equal?
   (map cubic-bezier-path-segment-end
        (subpath-segments normalized-unequal))
   (list (vec2 2 0)
         (vec2 4 0)
         (vec2 5 0)))

  ; equal-source : path-geometry?
  ;;   Gives two equal-length stored line segments.
  (define equal-source
    (polyline-path
     (list origin (vec2 2 0) (vec2 4 0))))

  ; equal-target : path-geometry?
  ;;   Gives three stored line segments.
  (define equal-target
    (polyline-path
     (list origin (vec2 1 1) (vec2 2 1) (vec2 4 0))))

  (define-values (normalized-equal _normalized-equal-target)
    (path-geometry-normalize-for-morph equal-source equal-target))

  (check-equal?
   (map cubic-bezier-path-segment-end
        (subpath-segments normalized-equal))
   (list (vec2 1 0)
         (vec2 2 0)
         (vec2 4 0)))

  ;; Repeated refinement always remeasures the current curves. Splitting one
  ;; line into four pieces therefore produces four equal consecutive cubics.

  ; four-segment-target : path-geometry?
  ;;   Gives four stored line segments for repeated count normalization.
  (define four-segment-target
    (polyline-path
     (list origin
           (vec2 1 1)
           (vec2 2 1)
           (vec2 3 1)
           (vec2 4 0))))

  (define-values (normalized-four-piece-line _normalized-four-target)
    (path-geometry-normalize-for-morph
     (polyline-path (list origin (vec2 4 0)))
     four-segment-target))

  (check-equal?
   (map cubic-bezier-path-segment-end
        (subpath-segments normalized-four-piece-line))
   (list (vec2 1 0)
         (vec2 2 0)
         (vec2 3 0)
         (vec2 4 0)))

  ;; Already-cubic equal-count geometry can be reused without rebuilding it.

  (define-values (same-cubic-left same-cubic-right)
    (path-geometry-normalize-for-morph cubic-arch cubic-arch))

  (check-eq? same-cubic-left cubic-arch)
  (check-eq? same-cubic-right cubic-arch)

  ;; Equal counts may still need line-to-cubic conversion.

  (define-values (normalized-line normalized-arch)
    (path-geometry-normalize-for-morph straight-line cubic-arch))

  (check-true
   (path-geometry-morph-compatible? normalized-line normalized-arch))
  (check-true (all-cubic-segments? normalized-line))
  (check-eq? normalized-arch cubic-arch)

  ;; Limited normalization preserves subpath order and closure. It rejects
  ;; missing subpaths, closure mismatches, and point-only/nonempty pairings.

  ; point-path : path-geometry?
  ;;   Gives one point-only open subpath.
  (define point-path
    (path-geometry
     (list (path-subpath origin '() #f))))

  ; second-point-path : path-geometry?
  ;;   Gives another point-only open subpath.
  (define second-point-path
    (path-geometry
     (list (path-subpath (vec2 2 3) '() #f))))

  (check-true
   (path-geometry-morph-normalizable? point-path second-point-path))

  (define-values (normalized-point normalized-second-point)
    (path-geometry-normalize-for-morph point-path second-point-path))

  (check-eq? normalized-point point-path)
  (check-eq? normalized-second-point second-point-path)

  ;; Compound geometry is normalized pairwise without reordering subpaths.

  ; compound-source : path-geometry?
  ;;   Gives a point-only subpath followed by one open line segment.
  (define compound-source
    (path-geometry
     (list (path-subpath (vec2 -5 0) '() #f)
           (path-subpath origin
                         (list (line-path-segment (vec2 4 0)))
                         #f))))

  ; compound-destination : path-geometry?
  ;;   Gives a corresponding point and a two-segment open line path.
  (define compound-destination
    (path-geometry
     (list (path-subpath (vec2 5 0) '() #f)
           (path-subpath origin
                         (list (line-path-segment (vec2 2 2))
                               (line-path-segment (vec2 4 0)))
                         #f))))

  (define-values (normalized-compound-source
                  normalized-compound-destination)
    (path-geometry-normalize-for-morph compound-source
                                       compound-destination))

  (check-true
   (path-geometry-morph-compatible? normalized-compound-source
                                    normalized-compound-destination))
  (check-equal?
   (map path-subpath-start
        (path-geometry-subpaths normalized-compound-source))
   (list (vec2 -5 0) origin))
  (check-equal?
   (map path-subpath-start
        (path-geometry-subpaths normalized-compound-destination))
   (list (vec2 5 0) origin))
  (check-equal?
   (map (lambda (subpath)
          (length (path-subpath-segments subpath)))
        (path-geometry-subpaths normalized-compound-source))
   '(0 2))

  ; open-triangle-path : path-geometry?
  ;;   Gives triangle vertices without closure.
  (define open-triangle-path
    (polyline-path
     (list (vec2 -3 -1)
           (vec2 3 -1)
           (vec2 0 2))))

  ; extra-subpath-path : path-geometry?
  ;;   Gives two point-only open subpaths.
  (define extra-subpath-path
    (path-geometry
     (list (path-subpath origin '() #f)
           (path-subpath (vec2 1 1) '() #f))))

  (check-false
   (path-geometry-morph-normalizable? triangle-path open-triangle-path))
  (check-false
   (path-geometry-morph-normalizable? point-path extra-subpath-path))
  (check-false
   (path-geometry-morph-normalizable? point-path straight-line))

  (check-exn
   (exception-message-matches? #rx"different closure values")
   (lambda ()
     (path-geometry-normalize-for-morph triangle-path open-triangle-path)))
  (check-exn
   (exception-message-matches? #rx"different subpath counts")
   (lambda ()
     (path-geometry-normalize-for-morph point-path extra-subpath-path)))
  (check-exn
   (exception-message-matches? #rx"point-only subpath")
   (lambda ()
     (path-geometry-normalize-for-morph point-path straight-line)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-morph-normalizable? triangle-path 'not-a-path)))

  ;; The strict request remains strict. The normalized request accepts the
  ;; limited count and segment-kind differences.

  ; panel : path-visual?
  ;;   Gives the triangle source with visible style and affine placement.
  (define panel
    (make-path-visual triangle-path
                      #:id 'panel
                      #:center (vec2 -2 1)
                      #:rotation 1/4
                      #:scale (vec2 1 2)
                      #:fill "cornflowerblue"
                      #:stroke "navy"
                      #:stroke-width 5))

  ; backdrop : rectangle-visual?
  ;;   Gives an unrelated Visual behind panel.
  (define backdrop
    (rectangle #:id 'backdrop
               #:width 10
               #:height 7
               #:fill "whitesmoke"))

  ; start-scene : scene?
  ;;   Gives backdrop behind panel.
  (define start-scene
    (scene-add (make-scene) backdrop panel))

  (check-true
   (morph-to-normalized-request?
    (morph-to-normalized panel rectangle-path)))
  (check-true
   (morph-to-normalized-request?
    (morph-to-normalized 'panel rectangle-path)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-normalized (circle #:id 'not-a-path)
                                    rectangle-path)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-normalized panel 'not-path-geometry)))
  (check-exn
   (exception-message-matches? #rx"different segment counts")
   (lambda ()
     (scene-play start-scene
                 (morph-to panel rectangle-path))))

  ; normalized-scene : scene?
  ;;   Gives a two-second normalized morph with simultaneous affine changes.
  (define normalized-scene
    (scene-play
     start-scene
     (morph-to-normalized panel rectangle-path)
     (move-to panel (vec2 2 -1))
     (rotate-to panel 5/4)
     (scale-to panel (vec2 2 1/2))
     #:duration 2))

  ; start-panel : path-visual?
  ;;   Gives panel at exact clip progress zero.
  (define start-panel
    (scene-state-ref (scene-sample normalized-scene 0)
                     'panel))

  ; midpoint-panel : path-visual?
  ;;   Gives panel halfway through all animation components.
  (define midpoint-panel
    (scene-state-ref (scene-sample normalized-scene 1)
                     'panel))

  ; endpoint-panel : path-visual?
  ;;   Gives panel at the complete scene endpoint.
  (define endpoint-panel
    (scene-state-ref (scene-sample normalized-scene 2)
                     'panel))

  (check-eq? (path-visual-path start-panel)
             triangle-path)
  (check-equal?
   (path-visual-path midpoint-panel)
   (path-geometry-lerp normalized-triangle normalized-rectangle 1/2))
  (check-true
   (all-cubic-segments? (path-visual-path midpoint-panel)))
  (check-eq? (path-visual-path endpoint-panel)
             rectangle-path)
  (check-equal? (visual-position midpoint-panel)
                origin)
  (check-equal? (visual-rotation midpoint-panel)
                3/4)
  (check-equal? (visual-scale midpoint-panel)
                (vec2 3/2 5/4))
  (check-equal? (path-visual-fill midpoint-panel)
                "cornflowerblue")
  (check-equal? (path-visual-stroke midpoint-panel)
                "navy")
  (check-equal? (path-visual-stroke-width midpoint-panel)
                5)
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order
         (scene-sample normalized-scene 1)))
   '(backdrop panel))
  (check-eq?
   (scene-state-ref (scene-sample normalized-scene 1) 'backdrop)
   backdrop)

  ; reordered-scene : scene?
  ;;   Gives the same disjoint requests in another order.
  (define reordered-scene
    (scene-play
     start-scene
     (scale-to panel (vec2 2 1/2))
     (rotate-to panel 5/4)
     (move-to panel (vec2 2 -1))
     (morph-to-normalized panel rectangle-path)
     #:duration 2))

  (check-equal?
   (scene-state-ref (scene-sample reordered-scene 1) 'panel)
   midpoint-panel)

  ;; Endpoint representation follows easing. Progress zero and one preserve the
  ;; exact source and destination objects; interior progress uses cubic paths.

  ; held-source-scene : scene?
  ;;   Gives a completed clip whose easing always returns zero.
  (define held-source-scene
    (scene-play start-scene
                (morph-to-normalized panel rectangle-path)
                #:duration 1
                #:easing (lambda (_progress) 0)))

  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample held-source-scene 1) 'panel))
   triangle-path)

  ;; A later normalized morph compiles from the exact preceding destination.

  ; later-scene : scene?
  ;;   Gives a later normalized morph from rectangle back to triangle.
  (define later-scene
    (scene-play normalized-scene
                (morph-to-normalized 'panel triangle-path)
                #:duration 1))

  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample later-scene 3) 'panel))
   triangle-path)

  ;; All path-changing requests share one path-geometry component.

  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play start-scene
                           (morph-to-normalized panel rectangle-path)
                           (morph-to-normalized panel rectangle-path))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play start-scene
                           (morph-to-normalized panel rectangle-path)
                           (morph-to panel triangle-path))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play start-scene
                           (morph-to-normalized panel rectangle-path)
                           (uncreate panel))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play (make-scene)
                           (morph-to-normalized panel rectangle-path)
                           (create panel))))

  ;; Compilation rejects unsupported normalization and non-path targets.

  (check-exn
   (exception-message-matches? #rx"different closure values")
   (lambda ()
     (scene-play start-scene
                 (morph-to-normalized panel open-triangle-path))))
  (check-exn
   (exception-message-matches? #rx"morph-to-normalized requires a path Visual")
   (lambda ()
     (scene-play
      (scene-add (make-scene)
                 (circle #:id 'circle-target))
      (morph-to-normalized 'circle-target rectangle-path)))))
