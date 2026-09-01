#lang racket/base

;;;
;;; SCENE-E Model Tests
;;;

;; Tests semantic path geometry, path Visuals, line and polygon construction,
;; and use of path Visuals with the existing affine timeline operations.


;;;
;;; Imports
;;;

(require rackunit
         "../main.rkt")


(module+ test
  ;; Straight segment values preserve their directed endpoint.

  ; segment : line-path-segment?
  ;;   Gives one local straight path segment.
  (define segment
    (line-path-segment (vec2 2 1)))
  (check-true (path-segment? segment))
  (check-equal? (line-path-segment-end segment)
                (vec2 2 1))
  (check-exn exn:fail:contract?
             (lambda ()
               (line-path-segment 'not-a-point)))
  (check-false (path-segment? 'not-a-segment))

  ;; A subpath stores one start point and traversal-ordered segment endpoints.

  ; open-subpath : path-subpath?
  ;;   Gives an open three-point subpath.
  (define open-subpath
    (path-subpath (vec2 -2 0)
                  (list (line-path-segment (vec2 0 1))
                        (line-path-segment (vec2 2 0)))
                  #f))
  (check-equal? (path-subpath-points open-subpath)
                (list (vec2 -2 0)
                      (vec2 0 1)
                      (vec2 2 0)))
  (check-false (path-subpath-closed? open-subpath))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-subpath origin
                             (list 'not-a-segment)
                             #f)))

  ;; Path geometry preserves subpath order and supports an explicit empty path.

  ; open-geometry : path-geometry?
  ;;   Gives path geometry containing open-subpath.
  (define open-geometry
    (path-geometry (list open-subpath)))
  (check-equal? (path-geometry-subpaths open-geometry)
                (list open-subpath))
  (check-equal? (path-geometry-subpath-points open-geometry)
                (list (list (vec2 -2 0)
                            (vec2 0 1)
                            (vec2 2 0))))
  (check-false (path-geometry-empty? open-geometry))
  (check-true (path-geometry-empty? empty-path-geometry))
  (check-equal? (path-geometry-subpaths empty-path-geometry)
                '())
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry (list 'not-a-subpath))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-bounds empty-path-geometry)))

  ; point-only-subpath : path-subpath?
  ;;   Gives an open subpath containing only its start point.
  (define point-only-subpath
    (path-subpath (vec2 3 -2) '() #f))

  ; point-only-geometry : path-geometry?
  ;;   Gives nonempty geometry containing one point-only subpath.
  (define point-only-geometry
    (path-geometry (list point-only-subpath)))
  (check-equal? (path-subpath-points point-only-subpath)
                (list (vec2 3 -2)))
  (check-false (path-geometry-empty? point-only-geometry))
  (check-equal?
   (call-with-values
    (lambda ()
      (path-geometry-bounds point-only-geometry))
    list)
   '(3 -2 3 -2))
  (check-equal? (path-geometry-center point-only-geometry)
                (vec2 3 -2))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-subpath origin '() 'not-a-boolean)))

  ;; Polyline and polygon helpers establish open and closed path structure.

  ; open-path : path-geometry?
  ;;   Gives a three-point open polyline.
  (define open-path
    (polyline-path (list (vec2 -2 0)
                         (vec2 0 1)
                         (vec2 2 0))))

  ; closed-path : path-geometry?
  ;;   Gives a closed four-vertex polygon path.
  (define closed-path
    (polygon-path (list (vec2 -2 -1)
                        (vec2 2 -1)
                        (vec2 2 1)
                        (vec2 -2 1))))
  (check-false
   (path-subpath-closed?
    (car (path-geometry-subpaths open-path))))
  (check-true
   (path-subpath-closed?
    (car (path-geometry-subpaths closed-path))))
  (check-equal? (path-geometry-subpath-points closed-path)
                (list (list (vec2 -2 -1)
                            (vec2 2 -1)
                            (vec2 2 1)
                            (vec2 -2 1))))
  (check-exn exn:fail:contract?
             (lambda ()
               (polyline-path (list origin))))
  (check-exn exn:fail:contract?
             (lambda ()
               (polygon-path (list origin
                                   (vec2 1 0)))))
  (check-exn exn:fail:contract?
             (lambda ()
               (polyline-path (list origin 'not-a-point))))

  ;; Bounds, centers, point mapping, and translation remain pure.

  (check-equal?
   (call-with-values
    (lambda ()
      (path-geometry-bounds closed-path))
    list)
   '(-2 -1 2 1))
  (check-equal? (path-geometry-center closed-path)
                origin)

  ; translated-path : path-geometry?
  ;;   Gives closed-path shifted by three units right and two units up.
  (define translated-path
    (path-geometry-translate closed-path
                             (vec2 3 2)))
  (check-equal? (path-geometry-subpath-points translated-path)
                (list (list (vec2 1 1)
                            (vec2 5 1)
                            (vec2 5 3)
                            (vec2 1 3))))
  (check-equal? (path-geometry-center translated-path)
                (vec2 3 2))
  (check-equal? (path-geometry-subpath-points closed-path)
                (list (list (vec2 -2 -1)
                            (vec2 2 -1)
                            (vec2 2 1)
                            (vec2 -2 1))))

  ; doubled-path : path-geometry?
  ;;   Gives open-path after doubling every local coordinate.
  (define doubled-path
    (path-geometry-map-points
     open-path
     (lambda (point)
       (vec2-scale 2 point))))
  (check-equal? (path-geometry-subpath-points doubled-path)
                (list (list (vec2 -4 0)
                            (vec2 0 2)
                            (vec2 4 0))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (path-geometry-map-points open-path 'not-a-procedure)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (path-geometry-map-points open-path
                               (lambda (_a _b)
                                 origin))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (path-geometry-map-points open-path
                               (lambda (_point)
                                 'not-a-point))))

  ;; A general path Visual stores local geometry and participates in both
  ;; semantic Visual protocols.

  ; general-path-visual : path-visual?
  ;;   Gives an affine path Visual with explicit local geometry.
  (define general-path-visual
    (make-path-visual open-path
                      #:id 'general-path
                      #:center (vec2 1 2)
                      #:rotation 1/4
                      #:scale (vec2 2 1/2)
                      #:fill #f
                      #:stroke "navy"
                      #:stroke-width 3))
  (check-true (visual? general-path-visual))
  (check-true (affine-visual? general-path-visual))
  (check-equal? (visual-id general-path-visual)
                'general-path)
  (check-equal? (visual-position general-path-visual)
                (vec2 1 2))
  (check-equal? (visual-rotation general-path-visual)
                1/4)
  (check-equal? (visual-scale general-path-visual)
                (vec2 2 1/2))
  (check-equal? (path-visual-path general-path-visual)
                open-path)
  (check-false (path-visual-fill general-path-visual))
  (check-equal? (path-visual-stroke general-path-visual)
                "navy")
  (check-equal? (path-visual-stroke-width general-path-visual)
                3)

  ; closed-general-path-visual : path-visual?
  ;;   Gives general-path-visual with only its local geometry replaced.
  (define closed-general-path-visual
    (path-visual-with-path general-path-visual
                           closed-path))
  (check-equal? (visual-id closed-general-path-visual)
                'general-path)
  (check-equal? (visual-transform closed-general-path-visual)
                (visual-transform general-path-visual))
  (check-equal? (path-visual-path closed-general-path-visual)
                closed-path)
  (check-equal? (path-visual-stroke closed-general-path-visual)
                "navy")
  (check-exn exn:fail:contract?
             (lambda ()
               (make-path-visual 'not-path
                                 #:id 'bad)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-visual-with-path general-path-visual
                                      'not-path)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-visual-with-path 'not-a-visual
                                      open-path)))

  ;; The line constructor derives its reference position from its world points
  ;; and stores a centered local path.

  ; diagonal : path-visual?
  ;;   Gives a line whose midpoint is (3, 2).
  (define diagonal
    (line (vec2 1 1)
          (vec2 5 3)
          #:id 'diagonal
          #:stroke "crimson"
          #:stroke-width 4))
  (check-equal? (visual-position diagonal)
                (vec2 3 2))
  (check-equal? (path-geometry-subpath-points
                 (path-visual-path diagonal))
                (list (list (vec2 -2 -1)
                            (vec2 2 1))))
  (check-false (path-visual-fill diagonal))
  (check-equal? (path-visual-stroke diagonal)
                "crimson")
  (check-exn exn:fail:contract?
             (lambda ()
               (line origin origin #:id 'zero-line)))

  ;; The polygon constructor centers world vertices at their axis-aligned
  ;; bounding-box center and stores one closed local subpath.

  ; panel : path-visual?
  ;;   Gives a rectangular polygon centered at (3, 2).
  (define panel
    (polygon (list (vec2 1 1)
                   (vec2 5 1)
                   (vec2 5 3)
                   (vec2 1 3))
             #:id 'panel
             #:fill "goldenrod"
             #:stroke "saddlebrown"))
  (check-equal? (visual-position panel)
                (vec2 3 2))
  (check-equal? (path-geometry-subpath-points
                 (path-visual-path panel))
                (list (list (vec2 -2 -1)
                            (vec2 2 -1)
                            (vec2 2 1)
                            (vec2 -2 1))))
  (check-true
   (path-subpath-closed?
    (car (path-geometry-subpaths
          (path-visual-path panel)))))
  (check-equal? (path-visual-fill panel)
                "goldenrod")

  ;; Existing transform requests operate on path Visuals without knowing their
  ;; concrete geometry representation.

  ; initial-scene : scene?
  ;;   Gives a polygon behind a line in back-to-front order.
  (define initial-scene
    (scene-add (make-scene)
               panel
               diagonal))
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order
         (scene-current-state initial-scene)))
   '(panel diagonal))

  ; transformed-scene : scene?
  ;;   Moves, rotates, and scales both path Visuals over two seconds.
  (define transformed-scene
    (scene-play initial-scene
                (move-to panel origin)
                (rotate-by panel 1)
                (scale-to panel (vec2 1/2 2))
                (move-to diagonal (vec2 -1 0))
                (rotate-to diagonal -1/2)
                (scale-by diagonal 2)
                #:duration 2))

  ; midpoint-state : scene-state?
  ;;   Gives the exact midpoint of the path animation.
  (define midpoint-state
    (scene-sample transformed-scene 1))

  ; midpoint-panel : path-visual?
  ;;   Gives panel halfway through all three affine components.
  (define midpoint-panel
    (scene-state-ref midpoint-state 'panel))

  ; midpoint-diagonal : path-visual?
  ;;   Gives diagonal halfway through all three affine components.
  (define midpoint-diagonal
    (scene-state-ref midpoint-state 'diagonal))
  (check-equal? (visual-position midpoint-panel)
                (vec2 3/2 1))
  (check-equal? (visual-rotation midpoint-panel)
                1/2)
  (check-equal? (visual-scale midpoint-panel)
                (vec2 3/4 3/2))
  (check-equal? (visual-position midpoint-diagonal)
                (vec2 1 1))
  (check-equal? (visual-rotation midpoint-diagonal)
                -1/4)
  (check-equal? (visual-scale midpoint-diagonal)
                (vec2 3/2 3/2))
  (check-equal? (path-visual-path midpoint-panel)
                (path-visual-path panel))
  (check-equal? (path-visual-path midpoint-diagonal)
                (path-visual-path diagonal)))
