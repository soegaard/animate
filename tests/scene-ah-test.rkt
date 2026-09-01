#lang racket/base

;;;
;;; SCENE-AH Topology-Changing Morph Model Tests
;;;

;; Tests rectangular topology-aware pairing, deterministic in-place birth/death
;; seeds, normalization, exact endpoints, validation, and timeline integration.

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

  (define (check-vec2~= actual expected tolerance)
    (check-= (vec2-x actual) (vec2-x expected) tolerance)
    (check-= (vec2-y actual) (vec2-y expected) tolerance))

  (define (check-degenerate-seed seed real-subpath)
    (define center
      (path-geometry-center (subpath-geometry real-subpath)))
    (check-equal? (path-subpath-closed? seed)
                  (path-subpath-closed? real-subpath))
    (check-equal? (length (path-subpath-segments seed)) 1)
    (check-vec2~= (path-subpath-start seed) center 1e-12)
    (define segment (car (path-subpath-segments seed)))
    (check-true (line-path-segment? segment))
    (check-vec2~= (line-path-segment-end segment) center 1e-12))

  (define open-match-source
    (polyline-path
     (list (vec2 -9 1) (vec2 -7 2) (vec2 -5 0))))
  (define open-death-source
    (cubic-bezier-path
     (vec2 1 -5)
     (list
      (cubic-bezier-path-segment
       (vec2 3 -7) (vec2 6 -7) (vec2 8 -5)))))
  (define closed-match-source
    (polygon-path
     (list (vec2 -8 -3) (vec2 -5 -3) (vec2 -5 0) (vec2 -8 0))))
  (define closed-death-source
    (polygon-path
     (list (vec2 3 2) (vec2 6 2) (vec2 7 4) (vec2 5 6) (vec2 2 4))))

  (define open-match-destination
    (path-geometry-reverse
     (cubic-bezier-path
      (vec2 -9 1)
      (list
       (cubic-bezier-path-segment
        (vec2 -8 4) (vec2 -5 3) (vec2 -4 0))))))
  (define open-birth-destination
    (polyline-path
     (list (vec2 4 -5) (vec2 6 -2) (vec2 9 -4))))
  (define closed-match-destination
    (path-geometry-cycle-start
     (path-geometry-reverse
      (polygon-path
       (list (vec2 -9 -3) (vec2 -5 -4) (vec2 -4 -1) (vec2 -7 1) (vec2 -10 -1))))
     1/5))
  (define closed-birth-destination
    (polygon-path
     (list (vec2 2 1) (vec2 5 0) (vec2 8 2) (vec2 7 5) (vec2 3 5))))

  ;; Unequal counts in both topology classes: one open source dies while one
  ;; closed destination is born. Matching real subpaths are also reordered and
  ;; direction/phase scrambled.
  (define source
    (combine-paths
     open-match-source
     closed-match-source
     open-death-source
     closed-death-source))
  (define destination
    (combine-paths
     closed-birth-destination
     open-match-destination
     closed-match-destination
     open-birth-destination))

  ;; Use a source with two closed and two open against destination with two of
  ;; each first to prove matching-count input reduces exactly to SCENE-AG.
  (define equal-source source)
  (define equal-destination destination)
  (define-values (equal-prepared-source equal-prepared-destination)
    (path-geometry-prepare-topology-changing-morph
     equal-source equal-destination #:sample-count 24))
  (check-eq? equal-prepared-source equal-source)
  (check-equal?
   equal-prepared-destination
   (path-geometry-align-mixed-compound-for-morph
    equal-source equal-destination #:sample-count 24))

  ;; Now make the topology counts differ: remove destination's born open path
  ;; and source's dying closed loop. Interior correspondence therefore needs one
  ;; open death and one closed birth even though total endpoint counts stay 3.
  (define changing-source
    (combine-paths open-match-source closed-match-source open-death-source))
  (define changing-destination
    (combine-paths
     open-match-destination
     closed-birth-destination
     closed-match-destination))
  (define-values (prepared-source prepared-destination)
    (path-geometry-prepare-topology-changing-morph
     changing-source changing-destination #:sample-count 24))
  (define source-subpaths (path-geometry-subpaths changing-source))
  (define destination-subpaths (path-geometry-subpaths changing-destination))
  (define prepared-source-subpaths (path-geometry-subpaths prepared-source))
  (define prepared-destination-subpaths
    (path-geometry-subpaths prepared-destination))

  ;; Three source slots remain first, then the unmatched closed destination is
  ;; appended as a birth slot. Topology matches pairwise in all four interiors.
  (check-equal? (length prepared-source-subpaths) 4)
  (check-equal? (length prepared-destination-subpaths) 4)
  (check-equal? (map path-subpath-closed? prepared-source-subpaths)
                '(#f #t #f #t))
  (check-equal? (map path-subpath-closed? prepared-destination-subpaths)
                '(#f #t #f #t))
  (check-eq? (list-ref prepared-source-subpaths 0) (list-ref source-subpaths 0))
  (check-eq? (list-ref prepared-source-subpaths 1) (list-ref source-subpaths 1))
  (check-eq? (list-ref prepared-source-subpaths 2) (list-ref source-subpaths 2))

  ;; The third source open path is unmatched and collapses at its own bounds
  ;; center. The appended source slot is the in-place seed for the new closed loop.
  (check-degenerate-seed
   (list-ref prepared-destination-subpaths 2)
   (list-ref source-subpaths 2))
  (check-degenerate-seed
   (list-ref prepared-source-subpaths 3)
   (list-ref destination-subpaths 1))
  (check-eq? (list-ref prepared-destination-subpaths 3)
             (list-ref destination-subpaths 1))

  ;; The real open and closed matches are spatially local despite destination
  ;; storage order/direction/phase being scrambled.
  (check-vec2~=
   (path-geometry-center
    (subpath-geometry (list-ref prepared-destination-subpaths 0)))
   (path-geometry-center open-match-destination)
   1e-9)
  (check-vec2~=
   (path-geometry-center
    (subpath-geometry (list-ref prepared-destination-subpaths 1)))
   (path-geometry-center closed-match-destination)
   1e-9)

  ;; The prepared paths are directly consumable by the existing cubic
  ;; normalization/interpolation pipeline.
  (check-true
   (path-geometry-morph-normalizable? prepared-source prepared-destination))
  (define-values (normalized-source normalized-destination)
    (path-geometry-normalize-for-morph
     prepared-source prepared-destination))
  (check-true
   (path-geometry-morph-compatible? normalized-source normalized-destination))
  (check-equal?
   (length (path-geometry-subpaths normalized-source))
   4)

  ;; Pure births and deaths from/to empty geometry are supported.
  (define-values (born-source born-destination)
    (path-geometry-prepare-topology-changing-morph
     empty-path-geometry open-birth-destination))
  (check-equal? (length (path-geometry-subpaths born-source)) 1)
  (check-degenerate-seed
   (car (path-geometry-subpaths born-source))
   (car (path-geometry-subpaths open-birth-destination)))
  (check-eq? (car (path-geometry-subpaths born-destination))
             (car (path-geometry-subpaths open-birth-destination)))

  (define-values (dying-source dying-destination)
    (path-geometry-prepare-topology-changing-morph
     closed-death-source empty-path-geometry))
  (check-eq? (car (path-geometry-subpaths dying-source))
             (car (path-geometry-subpaths closed-death-source)))
  (check-degenerate-seed
   (car (path-geometry-subpaths dying-destination))
   (car (path-geometry-subpaths closed-death-source)))

  (define-values (empty-source empty-destination)
    (path-geometry-prepare-topology-changing-morph
     empty-path-geometry empty-path-geometry))
  (check-eq? empty-source empty-path-geometry)
  (check-eq? empty-destination empty-path-geometry)

  ;; Timeline integration uses prepared geometry only in interior frames. Exact
  ;; endpoint storage remains the caller's source and destination objects.
  (define panel
    (make-path-visual changing-source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 4))
  (define request
    (morph-to-topology-changing panel changing-destination #:sample-count 24))
  (check-true (morph-to-topology-changing-request? request))
  (check-true
   (morph-to-topology-changing-request?
    (morph-to-topology-changing
     'panel changing-destination #:allow-reverse? #f #:sample-count 16)))
  (define animated-scene
    (scene-play
     (scene-add (make-scene) panel)
     request
     (move-to panel (vec2 2 -1))
     #:duration 2))
  (define midpoint
    (scene-state-ref (scene-sample animated-scene 1) 'panel))
  (check-equal?
   (path-visual-path midpoint)
   (path-geometry-lerp normalized-source normalized-destination 1/2))
  (check-equal? (visual-position midpoint) (vec2 1 -1/2))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 0) 'panel))
   changing-source)
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 2) 'panel))
   changing-destination)

  ;; The request reserves the same path-geometry component as other morphs.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-topology-changing panel changing-destination)
                (morph-to-normalized panel changing-destination))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-topology-changing panel changing-destination)
                (uncreate panel))))

  ;; Existing degenerate subpaths are invalid real correspondence candidates;
  ;; SCENE-AH creates its own controlled degenerate seeds after validation.
  (define zero-open
    (path-geometry (list (path-subpath origin '() #f))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                zero-open changing-destination)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                (circle #:id 'not-path)
                changing-destination)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                panel changing-destination #:allow-reverse? 'yes)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                panel changing-destination #:sample-count 7))))
