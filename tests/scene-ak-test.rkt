#lang racket/base

;;;
;;; SCENE-AK Per-Subpath Birth/Death Anchor Map Model Tests
;;;

;; Tests sparse original-subpath-index anchor overrides while preserving the
;; SCENE-AI shared-anchor fallback, SCENE-AJ assignment policy, exact endpoints,
;; immutable request capture, and path-geometry component conflicts.

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

  ;; Two open source subpaths die while two closed destination subpaths are born.
  ;; The source/destination storage indexes therefore make map lookup explicit
  ;; and independent of topology-class assignment indexes.
  (define death-left
    (polyline-path
     (list (vec2 -9 2) (vec2 -7 4) (vec2 -5 2))))
  (define death-right
    (cubic-bezier-path
     (vec2 4 2)
     (list
      (cubic-bezier-path-segment
       (vec2 6 5) (vec2 8 5) (vec2 10 2)))))
  (define birth-left
    (polygon-path
     (list (vec2 -9 -5) (vec2 -6 -6) (vec2 -4 -3) (vec2 -6 -1))))
  (define birth-right
    (polygon-path
     (list (vec2 4 -5) (vec2 7 -6) (vec2 10 -4)
           (vec2 9 -1) (vec2 5 -1))))

  (define source (combine-paths death-left death-right))
  (define destination (combine-paths birth-left birth-right))
  (define source-subpaths (path-geometry-subpaths source))
  (define destination-subpaths (path-geometry-subpaths destination))

  (define shared-anchor origin)
  (define left-anchor (vec2 -6 0))
  (define right-anchor (vec2 7 0))
  (define birth-map (hash 0 left-anchor 1 right-anchor))
  (define death-map (hash 0 left-anchor 1 right-anchor))

  (define-values (prepared-source prepared-destination)
    (path-geometry-prepare-topology-changing-morph
     source
     destination
     #:birth-anchor shared-anchor
     #:death-anchor shared-anchor
     #:birth-anchor-map birth-map
     #:death-anchor-map death-map))
  (define prepared-source-subpaths (path-geometry-subpaths prepared-source))
  (define prepared-destination-subpaths
    (path-geometry-subpaths prepared-destination))

  ;; Existing source slots remain first and use source-index death overrides.
  (check-equal? (length prepared-source-subpaths) 4)
  (check-equal? (length prepared-destination-subpaths) 4)
  (check-eq? (list-ref prepared-source-subpaths 0) (list-ref source-subpaths 0))
  (check-eq? (list-ref prepared-source-subpaths 1) (list-ref source-subpaths 1))
  (check-seed-at
   (list-ref prepared-destination-subpaths 0)
   (list-ref source-subpaths 0)
   left-anchor)
  (check-seed-at
   (list-ref prepared-destination-subpaths 1)
   (list-ref source-subpaths 1)
   right-anchor)

  ;; Birth-only slots are appended in caller destination order and use the
  ;; corresponding original destination indexes for map lookup.
  (check-seed-at
   (list-ref prepared-source-subpaths 2)
   (list-ref destination-subpaths 0)
   left-anchor)
  (check-seed-at
   (list-ref prepared-source-subpaths 3)
   (list-ref destination-subpaths 1)
   right-anchor)
  (check-eq? (list-ref prepared-destination-subpaths 2)
             (list-ref destination-subpaths 0))
  (check-eq? (list-ref prepared-destination-subpaths 3)
             (list-ref destination-subpaths 1))

  ;; Maps are sparse. Missing indexes fall back to the existing shared anchor,
  ;; while an explicit 'bounds-center entry overrides an explicit shared point.
  (define sparse-map (hash 0 left-anchor))
  (define-values (sparse-source sparse-destination)
    (path-geometry-prepare-topology-changing-morph
     empty-path-geometry
     destination
     #:birth-anchor shared-anchor
     #:birth-anchor-map sparse-map))
  (define sparse-source-subpaths (path-geometry-subpaths sparse-source))
  (check-seed-at
   (list-ref sparse-source-subpaths 0)
   (list-ref destination-subpaths 0)
   left-anchor)
  (check-seed-at
   (list-ref sparse-source-subpaths 1)
   (list-ref destination-subpaths 1)
   shared-anchor)
  (check-eq? (list-ref (path-geometry-subpaths sparse-destination) 1)
             (list-ref destination-subpaths 1))

  (define birth-right-center
    (path-geometry-center (subpath-geometry (list-ref destination-subpaths 1))))
  (define-values (center-override-source center-override-destination)
    (path-geometry-prepare-topology-changing-morph
     empty-path-geometry
     destination
     #:birth-anchor shared-anchor
     #:birth-anchor-map (hash 1 'bounds-center)))
  (check-seed-at
   (list-ref (path-geometry-subpaths center-override-source) 0)
   (list-ref destination-subpaths 0)
   shared-anchor)
  (check-seed-at
   (list-ref (path-geometry-subpaths center-override-source) 1)
   (list-ref destination-subpaths 1)
   birth-right-center)
  (check-eq? (list-ref (path-geometry-subpaths center-override-destination) 1)
             (list-ref destination-subpaths 1))

  ;; Empty maps reproduce SCENE-AI exactly.
  (define-values (shared-source shared-destination)
    (path-geometry-prepare-topology-changing-morph
     source
     destination
     #:birth-anchor shared-anchor
     #:death-anchor shared-anchor))
  (define-values (empty-map-source empty-map-destination)
    (path-geometry-prepare-topology-changing-morph
     source
     destination
     #:birth-anchor shared-anchor
     #:death-anchor shared-anchor
     #:birth-anchor-map #hash()
     #:death-anchor-map #hash()))
  (check-equal? empty-map-source shared-source)
  (check-equal? empty-map-destination shared-destination)

  ;; Penalized voluntary rejection also resolves maps through original source
  ;; and destination indexes after global assignment/reordering.
  (define good-source
    (polyline-path (list (vec2 -9 7) (vec2 -7 7))))
  (define bad-source
    (polyline-path (list (vec2 -9 -7) (vec2 -7 -7))))
  (define far-destination
    (polyline-path (list (vec2 7 -7) (vec2 9 -7))))
  (define good-destination
    (polyline-path (list (vec2 -17/2 7) (vec2 -13/2 7))))
  (define penalized-source (combine-paths good-source bad-source))
  ;; The far destination is stored first even though it is the voluntary birth.
  (define penalized-destination (combine-paths far-destination good-destination))
  (define death-special (vec2 -6 -5))
  (define birth-special (vec2 6 -5))
  (define-values (penalized-prepared-source penalized-prepared-destination)
    (path-geometry-prepare-topology-changing-morph
     penalized-source
     penalized-destination
     #:sample-count 8
     #:birth-anchor shared-anchor
     #:death-anchor shared-anchor
     #:birth-anchor-map (hash 0 birth-special)
     #:death-anchor-map (hash 1 death-special)
     #:birth-penalty 2
     #:death-penalty 2))
  (define penalized-source-subpaths
    (path-geometry-subpaths penalized-prepared-source))
  (define penalized-destination-subpaths
    (path-geometry-subpaths penalized-prepared-destination))
  (check-equal? (length penalized-source-subpaths) 3)
  (check-equal? (length penalized-destination-subpaths) 3)
  (check-seed-at
   (list-ref penalized-destination-subpaths 1)
   (list-ref (path-geometry-subpaths penalized-source) 1)
   death-special)
  (check-seed-at
   (list-ref penalized-source-subpaths 2)
   (list-ref (path-geometry-subpaths penalized-destination) 0)
   birth-special)

  ;; Timeline requests snapshot caller hash contents. Mutating a mutable map
  ;; after request creation must not alter the compiled scene.
  (define mutable-birth-map (make-hash (list (cons 0 left-anchor)
                                             (cons 1 right-anchor))))
  (define mutable-death-map (make-hash (list (cons 0 left-anchor)
                                             (cons 1 right-anchor))))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 4))
  (define request
    (morph-to-topology-changing
     panel
     destination
     #:birth-anchor shared-anchor
     #:death-anchor shared-anchor
     #:birth-anchor-map mutable-birth-map
     #:death-anchor-map mutable-death-map))
  (check-true (morph-to-topology-changing-request? request))
  (hash-set! mutable-birth-map 0 (vec2 99 99))
  (hash-set! mutable-death-map 0 (vec2 99 99))
  (define animated-scene
    (scene-play
     (scene-add (make-scene) panel)
     request
     #:duration 2))
  (define midpoint-path
    (path-visual-path
     (scene-state-ref (scene-sample animated-scene 1) 'panel)))
  (define-values (normalized-source normalized-destination)
    (path-geometry-normalize-for-morph prepared-source prepared-destination))
  (check-equal?
   midpoint-path
   (path-geometry-lerp normalized-source normalized-destination 1/2))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 0) 'panel))
   source)
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 2) 'panel))
   destination)

  ;; Map validation is explicit. Keys are original nonnegative subpath indexes;
  ;; direct preparation also rejects indexes outside the corresponding side.
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                source destination #:birth-anchor-map '())))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                source destination #:death-anchor-map (hash -1 origin))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                source destination #:birth-anchor-map (hash 0 'center))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                source destination #:birth-anchor-map (hash 2 origin))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                source destination #:death-anchor-map (hash 2 origin))))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                panel destination #:birth-anchor-map (hash 1/2 origin))))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                panel destination #:death-anchor-map (hash 0 'center))))

  ;; A request can only know the current source subpath count at scene compile
  ;; time, so an out-of-range death-map key is rejected by scene-play.
  (define bad-range-request
    (morph-to-topology-changing
     panel destination #:death-anchor-map (hash 2 origin)))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                bad-range-request)))

  ;; SCENE-AK does not change the ordinary path-geometry component conflict.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                request
                (morph-to-normalized panel destination)))))
