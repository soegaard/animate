#lang racket/base

;;;
;;; SCENE-AD Automatic Compound Morph Correspondence Model Tests
;;;

;; Tests global closed-subpath pairing, per-loop SCENE-AC alignment, validation,
;; exact structural endpoints, and timeline integration without renderer state.

(require rackunit
         "../private/animation.rkt"
         "../private/geometry.rkt"
         "../private/path-geometry.rkt"
         "../private/scene-state.rkt"
         "../private/scene.rkt"
         "../private/visual-model.rkt")

(module+ test
  ; one-subpath : path-geometry? -> path-subpath?
  (define (one-subpath geometry)
    (car (path-geometry-subpaths geometry)))

  ; combine-paths : path-geometry? ... -> path-geometry?
  (define (combine-paths . geometries)
    (path-geometry
     (apply append
            (for/list ([geometry (in-list geometries)])
              (path-geometry-subpaths geometry)))))

  ; subpath-geometry : path-subpath? -> path-geometry?
  (define (subpath-geometry subpath)
    (path-geometry (list subpath)))

  ; check-vec2~= : vec2? vec2? nonnegative-real? -> void?
  (define (check-vec2~= actual expected tolerance)
    (check-= (vec2-x actual) (vec2-x expected) tolerance)
    (check-= (vec2-y actual) (vec2-y expected) tolerance))

  ; check-loop-samples~= : path-subpath? path-subpath? nonnegative-real? -> void?
  (define (check-loop-samples~= actual expected tolerance)
    (define actual-geometry (subpath-geometry actual))
    (define expected-geometry (subpath-geometry expected))
    (for ([fraction (in-list '(0 1/8 1/4 3/8 1/2 5/8 3/4 7/8))])
      (check-vec2~=
       (path-geometry-point-at actual-geometry fraction)
       (path-geometry-point-at expected-geometry fraction)
       tolerance)))

  ; square-at : real? real? real? -> path-geometry?
  (define (square-at x y half-size)
    (polygon-path
     (list (vec2 (- x half-size) (- y half-size))
           (vec2 (+ x half-size) (- y half-size))
           (vec2 (+ x half-size) (+ y half-size))
           (vec2 (- x half-size) (+ y half-size)))))

  (define source-a
    (polygon-path
     (list (vec2 -8 -2)
           (vec2 -5 -3)
           (vec2 -4 0)
           (vec2 -6 2)
           (vec2 -9 1))))
  (define source-b
    (polygon-path
     (list (vec2 -1 -1)
           (vec2 1 -2)
           (vec2 3 0)
           (vec2 2 3)
           (vec2 -1 2))))
  (define source-c
    (polygon-path
     (list (vec2 5 -3)
           (vec2 8 -2)
           (vec2 9 1)
           (vec2 7 3)
           (vec2 4 1))))
  (define source
    (combine-paths source-a source-b source-c))

  ;; Store the same three loops in an unrelated order, with independent cyclic
  ;; phases and traversal directions. Correct pairing has total score zero.
  (define destination-c
    (path-geometry-cycle-start
     (path-geometry-reverse source-c)
     2/5))
  (define destination-a
    (path-geometry-cycle-start source-a 1/3))
  (define destination-b
    (path-geometry-cycle-start
     (path-geometry-reverse source-b)
     3/7))
  (define stored-destination
    (combine-paths destination-c destination-a destination-b))
  (define aligned
    (path-geometry-align-compound-for-morph
     source stored-destination #:sample-count 16))
  (for ([actual (in-list (path-geometry-subpaths aligned))]
        [expected (in-list (path-geometry-subpaths source))])
    (check-loop-samples~= actual expected 1e-8))

  ;; Already corresponding compound geometry remains the exact destination
  ;; object, not merely an equal reconstruction.
  (check-eq?
   (path-geometry-align-compound-for-morph
    source source #:sample-count 16)
   source)

  ;; A one-loop compound request reduces to SCENE-AC's correspondence rule.
  (check-equal?
   (path-geometry-align-compound-for-morph
    source-a destination-a #:sample-count 16)
   (path-geometry-align-for-morph
    source-a destination-a #:sample-count 16))

  ;; Pairing is global rather than greedy. Source storage deliberately begins at
  ;; x=10, then x=0. A greedy first-row choice would use destination x=9, but
  ;; the lower total cost is x=10 -> 12 and x=0 -> 9.
  (define assignment-source
    (combine-paths (square-at 10 0 1/10)
                   (square-at 0 0 1/10)))
  (define assignment-destination
    (combine-paths (square-at 9 0 1/10)
                   (square-at 12 0 1/10)))
  (define assignment-aligned
    (path-geometry-align-compound-for-morph
     assignment-source assignment-destination #:sample-count 8))
  (define assignment-centers
    (for/list ([subpath (in-list (path-geometry-subpaths assignment-aligned))])
      (path-geometry-center (subpath-geometry subpath))))
  (check-vec2~= (car assignment-centers) (vec2 12 0) 1e-10)
  (check-vec2~= (cadr assignment-centers) (vec2 9 0) 1e-10)

  ;; Exact cost ties are deterministic. Distinct but coincident destination
  ;; subpaths retain their ascending storage order.
  (define tie-source-0 (square-at 0 0 1))
  (define tie-source-1 (square-at 0 0 1))
  (define tie-destination-0 (one-subpath (square-at 0 0 1)))
  (define tie-destination-1 (one-subpath (square-at 0 0 1)))
  (define tie-destination
    (path-geometry (list tie-destination-0 tie-destination-1)))
  (define tie-aligned
    (path-geometry-align-compound-for-morph
     (combine-paths tie-source-0 tie-source-1)
     tie-destination
     #:sample-count 8))
  (check-eq? (car (path-geometry-subpaths tie-aligned)) tie-destination-0)
  (check-eq? (cadr (path-geometry-subpaths tie-aligned)) tie-destination-1)

  ;; The public reversal option is passed through independently for every pair.
  (check-equal?
   (path-geometry-align-compound-for-morph
    source-a
    (path-geometry-reverse source-a)
    #:allow-reverse? #f
    #:sample-count 16)
   (path-geometry-align-for-morph
    source-a
    (path-geometry-reverse source-a)
    #:allow-reverse? #f
    #:sample-count 16))

  ;; Timeline integration globally pairs first, normalizes corresponding pairs,
  ;; and still preserves the exact caller-requested representation at progress 1.
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:fill "lightsteelblue"
                      #:stroke "navy"
                      #:stroke-width 4))
  (define request
    (morph-to-compound-aligned
     panel stored-destination #:sample-count 16))
  (check-true (morph-to-compound-aligned-request? request))
  (check-true
   (morph-to-compound-aligned-request?
    (morph-to-compound-aligned
     'panel
     stored-destination
     #:allow-reverse? #f
     #:sample-count 8)))
  (define animated-scene
    (scene-play
     (scene-add (make-scene) panel)
     request
     (move-to panel (vec2 1 -1))
     #:duration 2))
  (define expected-aligned
    (path-geometry-align-compound-for-morph
     source stored-destination #:sample-count 16))
  (define-values (normalized-source normalized-destination)
    (path-geometry-normalize-for-morph source expected-aligned))
  (define midpoint
    (scene-state-ref (scene-sample animated-scene 1) 'panel))
  (check-equal?
   (path-visual-path midpoint)
   (path-geometry-lerp normalized-source normalized-destination 1/2))
  (check-equal? (visual-position midpoint) (vec2 1/2 -1/2))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 0) 'panel))
   source)
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 2) 'panel))
   stored-destination)

  ;; Compound alignment reserves the ordinary path-geometry component.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-compound-aligned
                 panel stored-destination #:sample-count 8)
                (morph-to-normalized panel source))))

  ;; Validation is explicit: equal nonempty counts, closed positive loops, and
  ;; the same deterministic option constraints as SCENE-AC.
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-compound-for-morph
                source
                (combine-paths source-a source-b)
                #:sample-count 8)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-compound-for-morph
                empty-path-geometry empty-path-geometry #:sample-count 8)))
  (define open-loop
    (polyline-path (list (vec2 0 0) (vec2 1 0) (vec2 1 1))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-compound-for-morph
                (combine-paths source-a source-b)
                (combine-paths source-a open-loop)
                #:sample-count 8)))
  (define degenerate-loop
    (path-geometry (list (path-subpath origin '() #t))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-compound-for-morph
                degenerate-loop degenerate-loop #:sample-count 8)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-compound-for-morph
                source source #:allow-reverse? 'yes #:sample-count 8)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-compound-for-morph
                source source #:sample-count 7)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-compound-aligned
                (circle #:id 'not-a-path)
                stored-destination)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-compound-aligned panel stored-destination
                                          #:sample-count 7))))
