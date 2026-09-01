#lang racket/base

;;;
;;; SCENE-AI Explicit Birth/Death Anchor Model Tests
;;;

;; Tests explicit local birth/death anchors while preserving SCENE-AH default
;; bounds-center behavior, topology correspondence, exact endpoints, and request
;; component conflicts.

(require rackunit
         "../private/animation.rkt"
         "../private/geometry.rkt"
         "../private/path-geometry.rkt"
         "../private/scene-state.rkt"
         "../private/scene.rkt"
         "../private/visual-model.rkt")

(module+ test
  (define (combine-paths . geometries)
    (path-geometry
     (apply append
            (for/list ([geometry (in-list geometries)])
              (path-geometry-subpaths geometry)))))

  (define (subpath-geometry subpath)
    (path-geometry (list subpath)))

  (define (check-seed-at seed real-subpath anchor)
    (check-equal? (path-subpath-closed? seed)
                  (path-subpath-closed? real-subpath))
    (check-equal? (length (path-subpath-segments seed)) 1)
    (check-equal? (path-subpath-start seed) anchor)
    (define segment (car (path-subpath-segments seed)))
    (check-true (line-path-segment? segment))
    (check-equal? (line-path-segment-end segment) anchor))

  (define source-open-match
    (polyline-path
     (list (vec2 -8 2) (vec2 -5 4) (vec2 -2 2))))
  (define source-open-death
    (cubic-bezier-path
     (vec2 -8 -4)
     (list
      (cubic-bezier-path-segment
       (vec2 -6 -7) (vec2 -2 -7) (vec2 0 -4)))))
  (define destination-open-match
    (path-geometry-reverse
     (cubic-bezier-path
      (vec2 -8 1)
      (list
       (cubic-bezier-path-segment
        (vec2 -6 5) (vec2 -2 5) (vec2 1 2))))))
  (define destination-closed-birth
    (polygon-path
     (list (vec2 3 -5) (vec2 7 -5) (vec2 9 -2)
           (vec2 7 1) (vec2 3 0))))

  (define source
    (combine-paths source-open-match source-open-death))
  (define destination
    (combine-paths destination-open-match destination-closed-birth))
  (define source-subpaths (path-geometry-subpaths source))
  (define destination-subpaths (path-geometry-subpaths destination))

  ;; SCENE-AH defaults are unchanged and resolve each unmatched side to its own
  ;; bounds center.
  (define-values (default-source default-destination)
    (path-geometry-prepare-topology-changing-morph
     source destination #:sample-count 24))
  (define default-source-subpaths (path-geometry-subpaths default-source))
  (define default-destination-subpaths
    (path-geometry-subpaths default-destination))
  (define death-center
    (path-geometry-center (subpath-geometry (list-ref source-subpaths 1))))
  (define birth-center
    (path-geometry-center (subpath-geometry (list-ref destination-subpaths 1))))
  (check-seed-at
   (list-ref default-destination-subpaths 1)
   (list-ref source-subpaths 1)
   death-center)
  (check-seed-at
   (list-ref default-source-subpaths 2)
   (list-ref destination-subpaths 1)
   birth-center)
  (define-values (explicit-default-source explicit-default-destination)
    (path-geometry-prepare-topology-changing-morph
     source
     destination
     #:sample-count 24
     #:birth-anchor 'bounds-center
     #:death-anchor 'bounds-center))
  (check-equal? explicit-default-source default-source)
  (check-equal? explicit-default-destination default-destination)

  ;; SCENE-AI permits one explicit local-space point for all births on one side
  ;; and another point for all deaths on the other side.
  (define birth-anchor (vec2 2 -1))
  (define death-anchor (vec2 -1 -1))
  (define-values (prepared-source prepared-destination)
    (path-geometry-prepare-topology-changing-morph
     source
     destination
     #:sample-count 24
     #:birth-anchor birth-anchor
     #:death-anchor death-anchor))
  (define prepared-source-subpaths (path-geometry-subpaths prepared-source))
  (define prepared-destination-subpaths
    (path-geometry-subpaths prepared-destination))
  (check-equal? (length prepared-source-subpaths) 3)
  (check-equal? (length prepared-destination-subpaths) 3)
  (check-eq? (list-ref prepared-source-subpaths 0)
             (list-ref source-subpaths 0))
  (check-eq? (list-ref prepared-source-subpaths 1)
             (list-ref source-subpaths 1))
  (check-seed-at
   (list-ref prepared-destination-subpaths 1)
   (list-ref source-subpaths 1)
   death-anchor)
  (check-seed-at
   (list-ref prepared-source-subpaths 2)
   (list-ref destination-subpaths 1)
   birth-anchor)
  (check-eq? (list-ref prepared-destination-subpaths 2)
             (list-ref destination-subpaths 1))

  ;; Explicit anchors also work for pure birth/death and stay local path-space
  ;; values rather than being transformed by scene position/camera state.
  (define-values (pure-birth-source pure-birth-destination)
    (path-geometry-prepare-topology-changing-morph
     empty-path-geometry
     destination-closed-birth
     #:birth-anchor birth-anchor))
  (check-seed-at
   (car (path-geometry-subpaths pure-birth-source))
   (car (path-geometry-subpaths destination-closed-birth))
   birth-anchor)
  (check-eq? (car (path-geometry-subpaths pure-birth-destination))
             (car (path-geometry-subpaths destination-closed-birth)))

  (define-values (pure-death-source pure-death-destination)
    (path-geometry-prepare-topology-changing-morph
     source-open-death
     empty-path-geometry
     #:death-anchor death-anchor))
  (check-eq? (car (path-geometry-subpaths pure-death-source))
             (car (path-geometry-subpaths source-open-death)))
  (check-seed-at
   (car (path-geometry-subpaths pure-death-destination))
   (car (path-geometry-subpaths source-open-death))
   death-anchor)

  ;; One explicit point is shared by every unmatched subpath on that side, even
  ;; when multiple topology slots are born or die together.
  (define multi-birth-destination
    (combine-paths destination-open-match destination-closed-birth))
  (define-values (multi-birth-source multi-birth-target)
    (path-geometry-prepare-topology-changing-morph
     empty-path-geometry
     multi-birth-destination
     #:birth-anchor birth-anchor))
  (for ([seed (in-list (path-geometry-subpaths multi-birth-source))]
        [real (in-list (path-geometry-subpaths multi-birth-target))])
    (check-seed-at seed real birth-anchor))

  (define-values (multi-death-source multi-death-target)
    (path-geometry-prepare-topology-changing-morph
     source
     empty-path-geometry
     #:death-anchor death-anchor))
  (for ([real (in-list (path-geometry-subpaths multi-death-source))]
        [seed (in-list (path-geometry-subpaths multi-death-target))])
    (check-seed-at seed real death-anchor))

  ;; Matching topology counts remain exact SCENE-AG correspondence. Anchor
  ;; values are valid but unused because no birth/death slot exists.
  (define equal-source source-open-match)
  (define equal-destination destination-open-match)
  (define-values (equal-prepared-source equal-prepared-destination)
    (path-geometry-prepare-topology-changing-morph
     equal-source
     equal-destination
     #:birth-anchor birth-anchor
     #:death-anchor death-anchor
     #:sample-count 24))
  (check-eq? equal-prepared-source equal-source)
  (check-equal?
   equal-prepared-destination
   (path-geometry-align-mixed-compound-for-morph
    equal-source equal-destination #:sample-count 24))

  ;; Timeline integration carries both anchor values into interior preparation
  ;; while preserving exact structural source/destination endpoint objects.
  (define-values (normalized-source normalized-destination)
    (path-geometry-normalize-for-morph prepared-source prepared-destination))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:center (vec2 5 3)
                      #:stroke "seagreen"
                      #:stroke-width 4))
  (define request
    (morph-to-topology-changing
     panel
     destination
     #:sample-count 24
     #:birth-anchor birth-anchor
     #:death-anchor death-anchor))
  (check-true (morph-to-topology-changing-request? request))
  (define animated-scene
    (scene-play
     (scene-add (make-scene) panel)
     request
     #:duration 2))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 0) 'panel))
   source)
  (check-equal?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 1) 'panel))
   (path-geometry-lerp normalized-source normalized-destination 1/2))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 2) 'panel))
   destination)
  (check-equal?
   (visual-position
    (scene-state-ref (scene-sample animated-scene 1) 'panel))
   (vec2 5 3))

  ;; The anchor options are declarative: only the exact default marker or a
  ;; finite vec2 is accepted.
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                source destination #:birth-anchor 'center)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                source destination #:death-anchor '(0 0))))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                panel destination #:birth-anchor 'center)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                panel destination #:death-anchor 0)))

  ;; SCENE-AI does not change path-geometry component conflict semantics.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-topology-changing
                 panel destination #:birth-anchor birth-anchor)
                (morph-to-normalized panel destination)))))
