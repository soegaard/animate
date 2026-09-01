#lang racket/base

;;;
;;; SCENE-AJ Penalized Topology-Changing Morph Model Tests
;;;

;; Tests optional rejection of poor real correspondences through explicit
;; birth/death penalties while preserving SCENE-AH/AI forced-only defaults,
;; anchors, exact endpoints, and path-geometry component conflicts.

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

  ;; One equal-count open-path pair is deliberately much farther apart than the
  ;; cost of one death plus one birth.
  (define far-source
    (polyline-path (list (vec2 -8 0) (vec2 -6 0))))
  (define far-destination
    (polyline-path (list (vec2 6 0) (vec2 8 0))))

  ;; The default remains SCENE-AH/AI's forced-only policy. Equal topology counts
  ;; therefore reduce exactly to SCENE-AG and cannot voluntarily birth/death.
  (define-values (forced-source forced-destination)
    (path-geometry-prepare-topology-changing-morph
     far-source far-destination #:sample-count 8))
  (check-eq? forced-source far-source)
  (check-equal?
   forced-destination
   (path-geometry-align-mixed-compound-for-morph
    far-source far-destination #:sample-count 8))
  (check-equal? (length (path-geometry-subpaths forced-source)) 1)
  (define-values (explicit-forced-source explicit-forced-destination)
    (path-geometry-prepare-topology-changing-morph
     far-source
     far-destination
     #:sample-count 8
     #:birth-penalty 'forced
     #:death-penalty 'forced))
  (check-eq? explicit-forced-source forced-source)
  (check-equal? explicit-forced-destination forced-destination)

  ;; Low numeric penalties make the poor real pair more expensive than one
  ;; local collapse plus one local regrowth, even though endpoint counts match.
  (define-values (rejected-source rejected-destination)
    (path-geometry-prepare-topology-changing-morph
     far-source
     far-destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 2))
  (define rejected-source-subpaths
    (path-geometry-subpaths rejected-source))
  (define rejected-destination-subpaths
    (path-geometry-subpaths rejected-destination))
  (check-equal? (length rejected-source-subpaths) 2)
  (check-equal? (length rejected-destination-subpaths) 2)
  (check-eq? (list-ref rejected-source-subpaths 0)
             (car (path-geometry-subpaths far-source)))
  (check-seed-at
   (list-ref rejected-destination-subpaths 0)
   (car (path-geometry-subpaths far-source))
   (path-geometry-center far-source))
  (check-seed-at
   (list-ref rejected-source-subpaths 1)
   (car (path-geometry-subpaths far-destination))
   (path-geometry-center far-destination))
  (check-eq? (list-ref rejected-destination-subpaths 1)
             (car (path-geometry-subpaths far-destination)))

  ;; High penalties make the same real correspondence preferable again.
  (define-values (high-source high-destination)
    (path-geometry-prepare-topology-changing-morph
     far-source
     far-destination
     #:sample-count 8
     #:birth-penalty 8
     #:death-penalty 8))
  (check-eq? high-source far-source)
  (check-equal? high-destination forced-destination)
  (check-equal? (length (path-geometry-subpaths high-source)) 1)

  ;; Exact primary-cost ties prefer fewer topology changes. This translated
  ;; segment has correspondence score exactly 2, equal to 1 + 1 penalties.
  (define tie-source
    (polyline-path (list (vec2 0 0) (vec2 2 0))))
  (define tie-destination
    (polyline-path (list (vec2 2 0) (vec2 4 0))))
  (define-values (tie-prepared-source tie-prepared-destination)
    (path-geometry-prepare-topology-changing-morph
     tie-source
     tie-destination
     #:sample-count 8
     #:birth-penalty 1
     #:death-penalty 1))
  (check-eq? tie-prepared-source tie-source)
  (check-equal? (length (path-geometry-subpaths tie-prepared-source)) 1)
  (check-eq? (car (path-geometry-subpaths tie-prepared-destination))
             (car (path-geometry-subpaths tie-destination)))

  ;; Closed loops use the same optional policy but retain SCENE-AC phase/direction
  ;; scoring for real candidates. A distant square is likewise cheaper to kill
  ;; and rebirth under the low penalties.
  (define far-closed-source
    (polygon-path
     (list (vec2 -8 -2) (vec2 -6 -2) (vec2 -6 0) (vec2 -8 0))))
  (define far-closed-destination
    (polygon-path
     (list (vec2 6 -2) (vec2 8 -2) (vec2 8 0) (vec2 6 0))))
  (define-values (closed-prepared-source closed-prepared-destination)
    (path-geometry-prepare-topology-changing-morph
     far-closed-source
     far-closed-destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 2))
  (check-equal? (length (path-geometry-subpaths closed-prepared-source)) 2)
  (check-equal? (length (path-geometry-subpaths closed-prepared-destination)) 2)
  (check-true
   (andmap path-subpath-closed?
           (path-geometry-subpaths closed-prepared-source)))
  (check-true
   (andmap path-subpath-closed?
           (path-geometry-subpaths closed-prepared-destination)))

  ;; Penalized correspondence is still global. A nearby upper pair survives;
  ;; the far lower destination is rejected and born independently despite the
  ;; destination list being deliberately scrambled.
  (define good-source
    (polyline-path (list (vec2 -8 3) (vec2 -6 3))))
  (define bad-source
    (polyline-path (list (vec2 -8 -3) (vec2 -6 -3))))
  (define far-lower-destination
    (polyline-path (list (vec2 6 -3) (vec2 8 -3))))
  (define good-destination
    (polyline-path (list (vec2 -15/2 3) (vec2 -11/2 3))))
  (define compound-source
    (combine-paths good-source bad-source))
  (define compound-destination
    (combine-paths far-lower-destination good-destination))
  (define shared-anchor (vec2 0 -1))
  (define-values (compound-prepared-source compound-prepared-destination)
    (path-geometry-prepare-topology-changing-morph
     compound-source
     compound-destination
     #:sample-count 8
     #:birth-anchor shared-anchor
     #:death-anchor shared-anchor
     #:birth-penalty 2
     #:death-penalty 2))
  (define compound-source-subpaths
    (path-geometry-subpaths compound-prepared-source))
  (define compound-destination-subpaths
    (path-geometry-subpaths compound-prepared-destination))
  (check-equal? (length compound-source-subpaths) 3)
  (check-equal? (length compound-destination-subpaths) 3)
  ;; First source gets the nearby destination even though that destination was
  ;; stored second. The second source dies; the far stored-first destination is
  ;; appended as the birth slot.
  (check-equal?
   (path-geometry-center (subpath-geometry (list-ref compound-destination-subpaths 0)))
   (path-geometry-center good-destination))
  (check-seed-at
   (list-ref compound-destination-subpaths 1)
   (car (path-geometry-subpaths bad-source))
   shared-anchor)
  (check-seed-at
   (list-ref compound-source-subpaths 2)
   (car (path-geometry-subpaths far-lower-destination))
   shared-anchor)
  (check-eq? (list-ref compound-destination-subpaths 2)
             (car (path-geometry-subpaths far-lower-destination)))

  ;; Numeric policy also handles topology-count differences. A zero-score real
  ;; pair stays matched and only the unavoidable extra destination is born.
  (define count-destination
    (combine-paths good-source far-lower-destination))
  (define-values (count-source count-target)
    (path-geometry-prepare-topology-changing-morph
     good-source
     count-destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 2))
  (check-equal? (length (path-geometry-subpaths count-source)) 2)
  (check-equal? (length (path-geometry-subpaths count-target)) 2)
  (check-eq? (car (path-geometry-subpaths count-source))
             (car (path-geometry-subpaths good-source)))

  ;; Timeline requests carry the policy into interior preparation, while exact
  ;; caller source/destination objects remain structural clip endpoints.
  (define panel
    (make-path-visual far-source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 4))
  (define request
    (morph-to-topology-changing
     panel
     far-destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 2))
  (check-true (morph-to-topology-changing-request? request))
  (define-values (normalized-source normalized-destination)
    (path-geometry-normalize-for-morph rejected-source rejected-destination))
  (define animated-scene
    (scene-play
     (scene-add (make-scene) panel)
     request
     #:duration 2))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 0) 'panel))
   far-source)
  (check-equal?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 1) 'panel))
   (path-geometry-lerp normalized-source normalized-destination 1/2))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 2) 'panel))
   far-destination)

  ;; Policy validation is explicit: either both defaults are 'forced, or both
  ;; values are finite nonnegative real costs.
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                far-source far-destination
                #:birth-penalty 1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                far-source far-destination
                #:birth-penalty -1
                #:death-penalty 1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                far-source far-destination
                #:birth-penalty +inf.0
                #:death-penalty 1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                panel far-destination
                #:birth-penalty 1)))

  ;; SCENE-AJ does not change path-geometry component conflict semantics.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                request
                (morph-to-normalized panel far-destination)))))
