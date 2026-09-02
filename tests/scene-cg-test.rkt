#lang racket/base

;;;
;;; SCENE-CG General Shape Transform Tests
;;;

;; Verifies the high-level replacement operation: primitive shapes use one
;; topology-aware path interior, while composite Visuals fall back to the exact
;; endpoint trees cross-faded in place.

(require rackunit
         racket/list
         "../private/visual-model.rkt"
         "../main.rkt")


(module+ test
  (define square
    (rectangle #:id 'square
               #:center (vec2 -1 0)
               #:width 2
               #:height 2
               #:fill "cornflowerblue"
               #:stroke "navy"
               #:stroke-width 2))
  (define disk
    (circle #:id 'disk
            #:center (vec2 2 1)
            #:radius 3/2
            #:fill "seagreen"
            #:stroke "darkgreen"
            #:stroke-width 3))
  (define geometric
    (scene-play
     (scene-add (make-scene) square)
     (transform-shape 'square disk #:mode 'morph)
     #:duration 1))

  ;; The source is structurally retained but completely hidden during the
  ;; interval. A frontmost temporary group provides the two styled morph layers.
  (define geometric-middle
    (scene-sample geometric 1/2))
  (check-true (scene-state-has? geometric-middle 'square))
  (check-= (visual-opacity (scene-state-ref geometric-middle 'square)) 0 1e-12)
  (check-equal? (scene-state-count geometric-middle) 2)
  (define geometric-overlay
    (last (scene-state-visuals-in-drawing-order geometric-middle)))
  (check-true (group-visual? geometric-overlay))
  (check-equal? (length (group-visual-children geometric-overlay)) 2)

  ;; SCENE-CJ chooses canonical right-midpoint/cardinal perimeter anchors for
  ;; primitive pairs.  The middle geometry therefore has eight corresponding
  ;; segments and remains symmetric about its own local origin, rather than
  ;; inheriting an arbitrary rectangle corner/path-start correspondence.
  (define perimeter-layer
    (transient-visual-underlying
     (first (group-visual-children geometric-overlay))))
  (check-true (path-visual? perimeter-layer))
  (define perimeter-subpath
    (first (path-geometry-subpaths (path-visual-path perimeter-layer))))
  (check-equal? (length (path-subpath-segments perimeter-subpath)) 8)
  (define-values (minimum-x minimum-y maximum-x maximum-y)
    (path-geometry-bounds (path-visual-path perimeter-layer)))
  (check-= (+ minimum-x maximum-x) 0 1e-10)
  (check-= (+ minimum-y maximum-y) 0 1e-10)
  ;; Every endpoint remains at its matching eighth-perimeter location.  In
  ;; particular, the final closing edge is explicit: otherwise generic path
  ;; normalization would split an unrelated rectangle edge and make the
  ;; halfway contour lopsided.
  (define perimeter-ends
    (for/list ([segment (in-list (path-subpath-segments perimeter-subpath))])
      (cubic-bezier-path-segment-end segment)))
  (define root-half 0.7071067811865476)
  (define half-diagonal (/ (+ 1 root-half) 2))
  (define expected-perimeter-ends
    (list (vec2 half-diagonal half-diagonal)
          (vec2 0 1)
          (vec2 (- half-diagonal) half-diagonal)
          (vec2 -1 0)
          (vec2 (- half-diagonal) (- half-diagonal))
          (vec2 0 -1)
          (vec2 half-diagonal (- half-diagonal))
          (vec2 1 0)))
  (for ([actual (in-list perimeter-ends)]
        [expected (in-list expected-perimeter-ends)])
    (check-= (vec2-x actual) (vec2-x expected) 1e-10)
    (check-= (vec2-y actual) (vec2-y expected) 1e-10))

  ;; Completion removes the old identity and restores the exact destination
  ;; primitive rather than retaining the temporary path proxy.
  (check-false (scene-state-has? (scene-current-state geometric) 'square))
  (check-true (circle-visual? (scene-visual-at geometric 'disk 1)))
  (check-equal? (scene-visual-at geometric 'disk 1) disk)

  ;; A composite diagram has no single contour correspondence. Auto mode still
  ;; yields a valid replacement through its cross-fade policy.
  (define diagram
    (group
     (list (rectangle #:id 'diagram-box
                      #:width 2
                      #:height 1
                      #:fill "aliceblue"
                      #:stroke "navy")
           (circle #:id 'diagram-point
                   #:center (vec2 1/2 0)
                   #:radius 1/5
                   #:fill "crimson"))
     #:id 'diagram))
  (define marker
    (circle #:id 'marker
            #:center (vec2 3 0)
            #:radius 3/4
            #:fill "goldenrod"))
  (define fallback
    (scene-play
     (scene-add (make-scene) diagram)
     (transform-shape diagram marker)
     #:duration 1))
  (check-equal? (scene-state-count (scene-sample fallback 1/2)) 2)
  (check-false (scene-state-has? (scene-current-state fallback) 'diagram))
  (check-equal? (scene-visual-at fallback 'marker 1) marker)

  ;; Explicit morph mode refuses to pretend that a whole composite has a
  ;; geometric correspondence; cross-fade mode remains available explicitly.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) diagram)
      (transform-shape diagram marker #:mode 'morph)
      #:duration 1)))
  (check-not-exn
   (lambda ()
     (scene-play
      (scene-add (make-scene) diagram)
      (transform-shape diagram marker #:mode 'cross-fade)
      #:duration 1)))
  ;; Explicit perimeter correspondence is intentionally only a primitive-shape
  ;; feature; callers can still ask for a strict morph and receive a useful
  ;; contract error for a path/composite pair.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) diagram)
      (transform-shape diagram marker
                       #:mode 'morph
                       #:correspondence 'perimeter)
      #:duration 1)))
  ;; Replacement reserves both endpoint identities, so an independent
  ;; introduction of the destination cannot make structural completion order
  ;; observable.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) square)
      (transform-shape square disk)
      (fade-in disk)
      #:duration 1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (transform-shape square
                      (circle #:id 'square #:radius 1))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (transform-shape square disk #:mode 'unexpected))))
