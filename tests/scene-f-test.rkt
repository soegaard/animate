#lang racket/base

;;;
;;; SCENE-F Model Tests
;;;

;; Tests local arc length, partial-path extraction, and semantic Create and
;; Uncreate timeline behavior.


;;;
;;; Imports
;;;

(require rackunit
         "../main.rkt")


(module+ test
  ;; Arc length follows segment and subpath traversal order. A closed subpath
  ;; includes its implicit final edge back to the start point.

  ; open-right-path : path-geometry?
  ;;   Gives a three-four right-angle polyline with total length seven.
  (define open-right-path
    (polyline-path (list origin
                         (vec2 3 0)
                         (vec2 3 4))))

  ; open-right-subpath : path-subpath?
  ;;   Gives the only subpath in open-right-path.
  (define open-right-subpath
    (car (path-geometry-subpaths open-right-path)))
  (check-equal? (path-subpath-length open-right-subpath)
                7)
  (check-equal? (path-geometry-length open-right-path)
                7)

  ; closed-right-path : path-geometry?
  ;;   Gives the corresponding closed three-four-five triangle.
  (define closed-right-path
    (polygon-path (list origin
                        (vec2 3 0)
                        (vec2 3 4))))

  ; closed-right-subpath : path-subpath?
  ;;   Gives the only subpath in closed-right-path.
  (define closed-right-subpath
    (car (path-geometry-subpaths closed-right-path)))
  (check-equal? (path-subpath-length closed-right-subpath)
                12)
  (check-equal? (path-geometry-length closed-right-path)
                12)

  ; point-only-geometry : path-geometry?
  ;;   Gives one zero-length point-only subpath.
  (define point-only-geometry
    (path-geometry
     (list (path-subpath (vec2 2 -1) '() #f))))
  (check-equal?
   (path-subpath-length
    (car (path-geometry-subpaths point-only-geometry)))
   0)
  (check-equal? (path-geometry-length point-only-geometry)
                0)
  (check-equal? (path-geometry-length empty-path-geometry)
                0)

  ;; Partial extraction uses fractions of total local arc length.

  ; first-edge : path-geometry?
  ;;   Gives exactly the first three units of open-right-path.
  (define first-edge
    (path-geometry-partial open-right-path 0 3/7))
  (check-equal? (path-geometry-subpath-points first-edge)
                (list (list origin
                            (vec2 3 0))))
  (check-false
   (path-subpath-closed?
    (car (path-geometry-subpaths first-edge))))

  ; first-five-units : path-geometry?
  ;;   Gives the first edge and two units of the second edge.
  (define first-five-units
    (path-geometry-partial open-right-path 0 5/7))
  (check-equal? (path-geometry-subpath-points first-five-units)
                (list (list origin
                            (vec2 3 0)
                            (vec2 3 2))))
  (check-equal? (path-geometry-length first-five-units)
                5)

  ; middle-four-units : path-geometry?
  ;;   Gives the interval from local arc distance one through five.
  (define middle-four-units
    (path-geometry-partial open-right-path 1/7 5/7))
  (check-equal? (path-geometry-subpath-points middle-four-units)
                (list (list (vec2 1 0)
                            (vec2 3 0)
                            (vec2 3 2))))
  (check-equal? (path-geometry-length middle-four-units)
                4)

  (check-true
   (path-geometry-empty?
    (path-geometry-partial open-right-path 1/2 1/2)))
  (check-eq? (path-geometry-partial open-right-path 0 1)
             open-right-path)

  ;; A partial closed path is open unless the whole original subpath is
  ;; selected. The implicit closing edge participates in arc length.

  ; two-edges-of-triangle : path-geometry?
  ;;   Gives the first seven units of the closed triangle.
  (define two-edges-of-triangle
    (path-geometry-partial closed-right-path 0 7/12))
  (check-equal? (path-geometry-subpath-points two-edges-of-triangle)
                (list (list origin
                            (vec2 3 0)
                            (vec2 3 4))))
  (check-false
   (path-subpath-closed?
    (car (path-geometry-subpaths two-edges-of-triangle))))

  ; closing-edge : path-geometry?
  ;;   Gives only the triangle's implicit closing edge.
  (define closing-edge
    (path-geometry-partial closed-right-path 7/12 1))
  (check-equal? (path-geometry-subpath-points closing-edge)
                (list (list (vec2 3 4)
                            origin)))
  (check-false
   (path-subpath-closed?
    (car (path-geometry-subpaths closing-edge))))
  (check-true
   (path-subpath-closed?
    (car
     (path-geometry-subpaths
      (path-geometry-partial closed-right-path 0 1)))))

  ;; Compound paths reveal one subpath after another. A fully selected closed
  ;; subpath retains closure before a later subpath begins.

  ; four-unit-line-path : path-geometry?
  ;;   Gives an open line with length four.
  (define four-unit-line-path
    (polyline-path (list (vec2 10 0)
                         (vec2 14 0))))

  ; compound-path : path-geometry?
  ;;   Gives the closed triangle followed by four-unit-line-path.
  (define compound-path
    (path-geometry
     (append (path-geometry-subpaths closed-right-path)
             (path-geometry-subpaths four-unit-line-path))))
  (check-equal? (path-geometry-length compound-path)
                16)

  ; completed-first-subpath : path-geometry?
  ;;   Gives exactly the first twelve units of compound-path.
  (define completed-first-subpath
    (path-geometry-partial compound-path 0 3/4))
  (check-equal? (length (path-geometry-subpaths completed-first-subpath))
                1)
  (check-true
   (path-subpath-closed?
    (car (path-geometry-subpaths completed-first-subpath))))

  ; compound-prefix : path-geometry?
  ;;   Gives the full triangle followed by two units of the line.
  (define compound-prefix
    (path-geometry-partial compound-path 0 7/8))
  (check-equal? (path-geometry-subpath-points compound-prefix)
                (list (list origin
                            (vec2 3 0)
                            (vec2 3 4))
                      (list (vec2 10 0)
                            (vec2 12 0))))
  (check-true
   (path-subpath-closed?
    (car (path-geometry-subpaths compound-prefix))))
  (check-false
   (path-subpath-closed?
    (cadr (path-geometry-subpaths compound-prefix))))

  ; crossing-subpath-boundary : path-geometry?
  ;;   Gives the final two triangle units followed by two line units.
  (define crossing-subpath-boundary
    (path-geometry-partial compound-path 5/8 7/8))
  (check-equal?
   (path-geometry-subpath-points crossing-subpath-boundary)
   (list (list (vec2 6/5 8/5)
               origin)
         (list (vec2 10 0)
               (vec2 12 0))))
  (check-equal? (path-geometry-length crossing-subpath-boundary)
                4)

  ;; Zero-length geometry has no positive partial interval, but selecting the
  ;; whole path preserves its exact structure.

  (check-eq? (path-geometry-partial point-only-geometry 0 1)
             point-only-geometry)
  (check-true
   (path-geometry-empty?
    (path-geometry-partial point-only-geometry 0 1/2)))

  ; repeated-point-path : path-geometry?
  ;;   Gives a path whose first stored edge has zero length.
  (define repeated-point-path
    (polyline-path (list origin
                         origin
                         (vec2 2 0))))
  (check-equal? (path-geometry-length repeated-point-path)
                2)
  (check-equal?
   (path-geometry-subpath-points
    (path-geometry-partial repeated-point-path 0 1/2))
   (list (list origin
               (vec2 1 0))))

  ;; Partial extraction validates both fractions and their order.

  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-partial open-right-path -1/4 1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-partial open-right-path 0 5/4)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-partial open-right-path 3/4 1/4)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-partial open-right-path +inf.0 1)))

  ; overflowing-path : path-geometry?
  ;;   Gives a finite-coordinate path whose inexact length overflows.
  (define overflowing-path
    (polyline-path (list (vec2 -1e308 0)
                         (vec2 1e308 0))))
  (check-equal? (path-geometry-length overflowing-path)
                +inf.0)
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-partial overflowing-path 0 1/2)))

  ; large-diagonal-path : path-geometry?
  ;;   Gives a path whose finite length needs scaled hypotenuse calculation.
  (define large-diagonal-path
    (polyline-path (list origin
                         (vec2 1e308 1e308))))
  (check-true
   (finite-real? (path-geometry-length large-diagonal-path)))
  (check-true
   (> (path-geometry-length large-diagonal-path)
      1e308))

  ;; Create carries a complete path Visual. Uncreate carries a present path
  ;; target identity.

  ; reveal-line : path-visual?
  ;;   Gives a four-unit path Visual centered at x=2.
  (define reveal-line
    (line origin
          (vec2 4 0)
          #:id 'reveal-line
          #:stroke "crimson"
          #:stroke-width 4))
  (check-true (create-request? (create reveal-line)))
  (check-true (uncreate-request? (uncreate reveal-line)))
  (check-true (uncreate-request? (uncreate 'reveal-line)))
  (check-false (create-request? (move-to reveal-line origin)))
  (check-false (uncreate-request? (move-to reveal-line origin)))
  (check-exn exn:fail:contract?
             (lambda ()
               (create (circle #:id 'not-a-path))))
  (check-exn exn:fail:contract?
             (lambda ()
               (uncreate (circle #:id 'not-a-path))))

  ; overflowing-visual : path-visual?
  ;;   Gives a path Visual whose inexact local length is not finite.
  (define overflowing-visual
    (make-path-visual overflowing-path
                      #:id 'overflowing-visual))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play (make-scene)
                           (create overflowing-visual))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) overflowing-visual)
                (uncreate overflowing-visual))))

  ;; Create introduces an absent path Visual. The Visual is present but empty at
  ;; clip start and complete in the stored endpoint state.

  ; create-scene : scene?
  ;;   Gives a one-second creation of reveal-line.
  (define create-scene
    (scene-play (make-scene)
                (create reveal-line)
                #:duration 1))
  (check-equal? (scene-duration create-scene)
                1)
  (check-equal? (scene-state-count (scene-current-state create-scene))
                1)
  (check-equal?
   (path-visual-path
    (scene-state-ref (scene-current-state create-scene)
                     'reveal-line))
   (path-visual-path reveal-line))

  ; create-start : scene-state?
  ;;   Gives create-scene at the beginning of its play clip.
  (define create-start
    (scene-sample create-scene 0))
  (check-true (scene-state-has? create-start 'reveal-line))
  ; create-start-visual : path-visual?
  ;;   Gives the empty placeholder prepared for reveal-line.
  (define create-start-visual
    (scene-state-ref create-start 'reveal-line))
  (check-true
   (path-geometry-empty?
    (path-visual-path create-start-visual)))
  (check-equal? (visual-position create-start-visual)
                (visual-position reveal-line))
  (check-equal? (path-visual-stroke create-start-visual)
                (path-visual-stroke reveal-line))
  (check-equal? (path-visual-stroke-width create-start-visual)
                (path-visual-stroke-width reveal-line))

  ; create-quarter : scene-state?
  ;;   Gives create-scene after one quarter of the path has appeared.
  (define create-quarter
    (scene-sample create-scene 1/4))
  (check-equal?
   (path-geometry-length
    (path-visual-path
     (scene-state-ref create-quarter 'reveal-line)))
   1)

  ; create-midpoint : scene-state?
  ;;   Gives create-scene after half of the path has appeared.
  (define create-midpoint
    (scene-sample create-scene 1/2))
  (check-equal?
   (path-geometry-length
    (path-visual-path
     (scene-state-ref create-midpoint 'reveal-line)))
   2)
  (check-equal?
   (visual-id (scene-state-ref create-midpoint 'reveal-line))
   'reveal-line)
  (check-equal?
   (path-geometry-length
    (path-visual-path
     (scene-state-ref (scene-sample create-scene 1)
                      'reveal-line)))
   4)

  ;; A zero-length path has no visible interior prefix. Create still preserves
  ;; its complete semantic structure at the structural endpoint.

  ; point-visual : path-visual?
  ;;   Gives one point-only path Visual.
  (define point-visual
    (make-path-visual point-only-geometry
                      #:id 'point-visual))

  ; point-create-scene : scene?
  ;;   Gives a one-second creation of point-visual.
  (define point-create-scene
    (scene-play (make-scene)
                (create point-visual)))
  (check-true
   (path-geometry-empty?
    (path-visual-path
     (scene-state-ref (scene-sample point-create-scene 1/2)
                      'point-visual))))
  (check-equal?
   (path-visual-path
    (scene-state-ref (scene-current-state point-create-scene)
                     'point-visual))
   point-only-geometry)

  ; point-uncreate-scene : scene?
  ;;   Gives a one-second removal of point-visual.
  (define point-uncreate-scene
    (scene-play
     (scene-add (make-scene) point-visual)
     (uncreate point-visual)))
  (check-true
   (path-geometry-empty?
    (path-visual-path
     (scene-state-ref (scene-sample point-uncreate-scene 1/2)
                      'point-visual))))
  (check-false
   (scene-state-has? (scene-current-state point-uncreate-scene)
                     'point-visual))

  ;; Create may run with disjoint transform components for the same target.
  ;; Request order does not matter because the start state is prepared first.

  ; moving-create-scene : scene?
  ;;   Gives simultaneous movement, rotation, scale, and path creation.
  (define moving-create-scene
    (scene-play (make-scene)
                (move-to reveal-line (vec2 4 1))
                (rotate-by reveal-line 1)
                (scale-to reveal-line (vec2 2 1/2))
                (create reveal-line)
                #:duration 2))

  ; moving-create-midpoint : path-visual?
  ;;   Gives the created Visual halfway through all four animations.
  (define moving-create-midpoint
    (scene-state-ref (scene-sample moving-create-scene 1)
                     'reveal-line))
  (check-equal? (visual-position moving-create-midpoint)
                (vec2 3 1/2))
  (check-equal? (visual-rotation moving-create-midpoint)
                1/2)
  (check-equal? (visual-scale moving-create-midpoint)
                (vec2 3/2 3/4))
  (check-equal?
   (path-geometry-length
    (path-visual-path moving-create-midpoint))
   2)

  ;; Created Visuals are placed in front in the order of their Create requests.

  ; second-line : path-visual?
  ;;   Gives another path Visual with a distinct identity.
  (define second-line
    (line (vec2 0 1)
          (vec2 4 1)
          #:id 'second-line))

  ; two-create-scene : scene?
  ;;   Gives simultaneous creation of reveal-line and second-line.
  (define two-create-scene
    (scene-play (make-scene)
                (create reveal-line)
                (create second-line)))
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order
         (scene-sample two-create-scene 0)))
   '(reveal-line second-line))

  ; creation-in-front-scene : scene?
  ;;   Gives an existing Visual followed by two simultaneous creations.
  (define creation-in-front-scene
    (scene-play
     (scene-add (make-scene)
                (circle #:id 'background))
     (create reveal-line)
     (create second-line)))
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order
         (scene-sample creation-in-front-scene 0)))
   '(background reveal-line second-line))

  ; list-form-create-scene : scene?
  ;;   Gives creation through scene-play's single-list request form.
  (define list-form-create-scene
    (scene-play (make-scene)
                (list (create reveal-line))))
  (check-true
   (scene-state-has? (scene-current-state list-form-create-scene)
                     'reveal-line))

  ;; Create rejects an identity already present. Two reveal requests for one
  ;; target conflict even when one is Create and the other is Uncreate.

  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) reveal-line)
                (create reveal-line))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play (make-scene)
                           (create reveal-line)
                           (uncreate 'reveal-line))))

  ;; Uncreate reverses the prefix reveal and removes the target at clip end.

  ; uncreate-scene : scene?
  ;;   Gives a one-second removal of reveal-line.
  (define uncreate-scene
    (scene-play
     (scene-add (make-scene) reveal-line)
     (uncreate 'reveal-line)
     #:duration 1))
  (check-equal?
   (path-geometry-length
    (path-visual-path
     (scene-state-ref (scene-sample uncreate-scene 0)
                      'reveal-line)))
   4)
  (check-equal?
   (path-geometry-length
    (path-visual-path
     (scene-state-ref (scene-sample uncreate-scene 1/2)
                      'reveal-line)))
   2)
  (check-false
   (scene-state-has? (scene-sample uncreate-scene 1)
                     'reveal-line))
  (check-equal? (scene-state-count (scene-current-state uncreate-scene))
                0)

  ;; Uncreate may move the same path while its visible prefix shrinks.

  ; moving-uncreate-scene : scene?
  ;;   Gives simultaneous movement and removal of reveal-line.
  (define moving-uncreate-scene
    (scene-play
     (scene-add (make-scene) reveal-line)
     (move-to 'reveal-line (vec2 4 0))
     (uncreate 'reveal-line)
     #:duration 1))

  ; moving-uncreate-midpoint : path-visual?
  ;;   Gives reveal-line halfway through movement and removal.
  (define moving-uncreate-midpoint
    (scene-state-ref (scene-sample moving-uncreate-scene 1/2)
                     'reveal-line))
  (check-equal? (visual-position moving-uncreate-midpoint)
                (vec2 3 0))
  (check-equal?
   (path-geometry-length
    (path-visual-path moving-uncreate-midpoint))
   2)
  (check-false
   (scene-state-has? (scene-current-state moving-uncreate-scene)
                     'reveal-line))

  ;; Removing one Visual preserves the identity and drawing order of others.

  ; retained-line : path-visual?
  ;;   Gives a path Visual that remains after reveal-line is removed.
  (define retained-line
    (line (vec2 -1 -1)
          (vec2 1 -1)
          #:id 'retained-line))

  ; selective-uncreate-scene : scene?
  ;;   Gives a scene that removes only reveal-line.
  (define selective-uncreate-scene
    (scene-play
     (scene-add (make-scene)
                retained-line
                reveal-line)
     (uncreate reveal-line)))
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order
         (scene-current-state selective-uncreate-scene)))
   '(retained-line))

  ;; Missing and non-path Uncreate targets are rejected when the request is
  ;; compiled against the current scene state.

  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play (make-scene)
                           (uncreate 'missing-path))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene)
                           (circle #:id 'circle-target))
                (uncreate 'circle-target))))

  ;; Structural completion is guaranteed even when a custom easing procedure
  ;; does not map one to one.

  ; zero-eased-create : scene?
  ;;   Gives a Create clip whose sampled easing progress remains zero.
  (define zero-eased-create
    (scene-play (make-scene)
                (create reveal-line)
                #:easing (lambda (_progress) 0)))
  (check-true
   (path-geometry-empty?
    (path-visual-path
     (scene-state-ref (scene-sample zero-eased-create 1/2)
                      'reveal-line))))
  (check-equal?
   (path-geometry-length
    (path-visual-path
     (scene-state-ref (scene-current-state zero-eased-create)
                      'reveal-line)))
   4)

  ; zero-eased-uncreate : scene?
  ;;   Gives an Uncreate clip whose sampled easing progress remains zero.
  (define zero-eased-uncreate
    (scene-play
     (scene-add (make-scene) reveal-line)
     (uncreate reveal-line)
     #:easing (lambda (_progress) 0)))
  (check-equal?
   (path-geometry-length
    (path-visual-path
     (scene-state-ref (scene-sample zero-eased-uncreate 1/2)
                      'reveal-line)))
   4)
  (check-false
   (scene-state-has? (scene-current-state zero-eased-uncreate)
                     'reveal-line)))
