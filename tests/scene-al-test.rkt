#lang racket/base

;;;
;;; SCENE-AL Per-Subpath Penalty Map Model Tests
;;;

;; Tests sparse original-index birth/death cost overrides layered on SCENE-AJ's
;; numeric global assignment, including reordering, fallback, immutable request
;; capture, validation, exact endpoints, and path-geometry component conflicts.

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

  ;; Source storage is top then bottom. Destination storage is deliberately
  ;; bottom then top, so map keys must survive global assignment/reordering.
  (define source-top
    (polyline-path (list (vec2 -8 3) (vec2 -6 3))))
  (define source-bottom
    (polyline-path (list (vec2 -8 -3) (vec2 -6 -3))))
  (define destination-bottom
    (polyline-path (list (vec2 6 -3) (vec2 8 -3))))
  (define destination-top
    (polyline-path (list (vec2 6 3) (vec2 8 3))))
  (define source
    (combine-paths source-top source-bottom))
  (define destination
    (combine-paths destination-bottom destination-top))

  ;; With shared low costs, both distant real pairs are rejected. Two source
  ;; slots die and two destination slots are born.
  (define-values (shared-source shared-destination)
    (path-geometry-prepare-topology-changing-morph
     source
     destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 2))
  (check-equal? (length (path-geometry-subpaths shared-source)) 4)
  (check-equal? (length (path-geometry-subpaths shared-destination)) 4)

  ;; Protect original source index 0 from cheap death and original destination
  ;; index 1 from cheap birth. The top pair is then globally retained even
  ;; though destination index 1 is stored after the bottom destination. The
  ;; bottom pair still dies/regrows under the shared costs.
  (define-values (mapped-source mapped-destination)
    (path-geometry-prepare-topology-changing-morph
     source
     destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 2
     #:birth-penalty-map (hash 1 20)
     #:death-penalty-map (hash 0 20)))
  (define mapped-source-subpaths (path-geometry-subpaths mapped-source))
  (define mapped-destination-subpaths (path-geometry-subpaths mapped-destination))
  (check-equal? (length mapped-source-subpaths) 3)
  (check-equal? (length mapped-destination-subpaths) 3)
  (check-eq? (list-ref mapped-source-subpaths 0)
             (car (path-geometry-subpaths source-top)))
  (check-equal?
   (path-geometry-center
    (subpath-geometry (list-ref mapped-destination-subpaths 0)))
   (path-geometry-center destination-top))
  (check-seed-at
   (list-ref mapped-destination-subpaths 1)
   (car (path-geometry-subpaths source-bottom))
   (path-geometry-center source-bottom))
  (check-seed-at
   (list-ref mapped-source-subpaths 2)
   (car (path-geometry-subpaths destination-bottom))
   (path-geometry-center destination-bottom))
  (check-eq? (list-ref mapped-destination-subpaths 2)
             (car (path-geometry-subpaths destination-bottom)))

  ;; Cost maps compose independently with SCENE-AK anchor maps. The same
  ;; assignment is chosen, while the one dying/born lower pair uses explicit
  ;; original-index seed positions.
  (define death-special (vec2 -5 -5))
  (define birth-special (vec2 5 -5))
  (define-values (anchored-mapped-source anchored-mapped-destination)
    (path-geometry-prepare-topology-changing-morph
     source
     destination
     #:sample-count 8
     #:birth-anchor-map (hash 0 birth-special)
     #:death-anchor-map (hash 1 death-special)
     #:birth-penalty 2
     #:death-penalty 2
     #:birth-penalty-map (hash 1 20)
     #:death-penalty-map (hash 0 20)))
  (check-seed-at
   (list-ref (path-geometry-subpaths anchored-mapped-destination) 1)
   (car (path-geometry-subpaths source-bottom))
   death-special)
  (check-seed-at
   (list-ref (path-geometry-subpaths anchored-mapped-source) 2)
   (car (path-geometry-subpaths destination-bottom))
   birth-special)

  ;; Empty maps are exact AJ fallback and one-sided sparse overrides are legal
  ;; within numeric shared mode.
  (define-values (empty-map-source empty-map-destination)
    (path-geometry-prepare-topology-changing-morph
     source
     destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 2
     #:birth-penalty-map #hash()
     #:death-penalty-map #hash()))
  (check-equal? empty-map-source shared-source)
  (check-equal? empty-map-destination shared-destination)
  (define-values (death-only-source death-only-destination)
    (path-geometry-prepare-topology-changing-morph
     source
     destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 2
     #:death-penalty-map (hash 0 20)))
  (check-equal? (length (path-geometry-subpaths death-only-source)) 3)
  (check-equal? (length (path-geometry-subpaths death-only-destination)) 3)

  ;; With unequal counts, sparse costs also influence which real destination is
  ;; left as the unavoidable birth. Shared costs match the nearby destination;
  ;; a high original-index birth cost on the far destination makes the global
  ;; assignment match that destination instead and birth the cheap nearby one.
  (define subset-source
    (polyline-path (list (vec2 0 0) (vec2 2 0))))
  (define subset-near
    (polyline-path (list (vec2 1/2 0) (vec2 5/2 0))))
  (define subset-far
    (polyline-path (list (vec2 6 0) (vec2 8 0))))
  (define subset-destination
    (combine-paths subset-near subset-far))
  (define-values (subset-shared-source subset-shared-destination)
    (path-geometry-prepare-topology-changing-morph
     subset-source subset-destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 20))
  (check-equal?
   (path-geometry-center
    (subpath-geometry
     (car (path-geometry-subpaths subset-shared-destination))))
   (path-geometry-center subset-near))
  (define-values (subset-mapped-source subset-mapped-destination)
    (path-geometry-prepare-topology-changing-morph
     subset-source subset-destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 20
     #:birth-penalty-map (hash 1 20)))
  (check-equal? (length (path-geometry-subpaths subset-mapped-source)) 2)
  (check-equal?
   (path-geometry-center
    (subpath-geometry
     (car (path-geometry-subpaths subset-mapped-destination))))
   (path-geometry-center subset-far))
  (check-eq? (list-ref (path-geometry-subpaths subset-mapped-destination) 1)
             (car (path-geometry-subpaths subset-near)))

  ;; Per-subpath costs still use AJ's secondary topology-change objective. When
  ;; map overrides make death+birth exactly equal to a real score, the real pair
  ;; is retained rather than needlessly disappearing and regrowing.
  (define tie-source
    (polyline-path (list (vec2 0 0) (vec2 2 0))))
  (define tie-destination
    (polyline-path (list (vec2 2 0) (vec2 4 0))))
  (define-values (tie-source* tie-destination*)
    (path-geometry-prepare-topology-changing-morph
     tie-source tie-destination
     #:sample-count 8
     #:birth-penalty 1/4
     #:death-penalty 1/4
     #:birth-penalty-map (hash 0 1)
     #:death-penalty-map (hash 0 1)))
  (check-eq? tie-source* tie-source)
  (check-equal? (length (path-geometry-subpaths tie-destination*)) 1)

  ;; Maps apply across topology classes by original caller index. Here the open
  ;; source is index 0 and the closed source is index 1, while destination order
  ;; is closed index 0 then open index 1.
  (define closed-source
    (polygon-path
     (list (vec2 -8 -1) (vec2 -6 -1) (vec2 -6 1) (vec2 -8 1))))
  (define closed-destination
    (polygon-path
     (list (vec2 6 -1) (vec2 8 -1) (vec2 8 1) (vec2 6 1))))
  (define mixed-source
    (combine-paths source-top closed-source))
  (define mixed-destination
    (combine-paths closed-destination destination-top))
  (define-values (mixed-prepared-source mixed-prepared-destination)
    (path-geometry-prepare-topology-changing-morph
     mixed-source
     mixed-destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 2
     #:birth-penalty-map (hash 1 20)
     #:death-penalty-map (hash 0 20)))
  ;; The protected open pair survives; the unprotected closed pair dies/regrows.
  (check-equal? (length (path-geometry-subpaths mixed-prepared-source)) 3)
  (check-equal? (length (path-geometry-subpaths mixed-prepared-destination)) 3)
  (check-false (path-subpath-closed?
                (list-ref (path-geometry-subpaths mixed-prepared-source) 0)))
  (check-true (path-subpath-closed?
               (list-ref (path-geometry-subpaths mixed-prepared-source) 1)))
  (check-true (path-subpath-closed?
               (list-ref (path-geometry-subpaths mixed-prepared-source) 2)))

  ;; Timeline requests snapshot mutable cost maps. Mutating the caller hashes
  ;; after request construction cannot revert the protected pair to shared costs.
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 4))
  (define mutable-birth-map (make-hash (list (cons 1 20))))
  (define mutable-death-map (make-hash (list (cons 0 20))))
  (define request
    (morph-to-topology-changing
     panel
     destination
     #:sample-count 8
     #:birth-penalty 2
     #:death-penalty 2
     #:birth-penalty-map mutable-birth-map
     #:death-penalty-map mutable-death-map))
  (check-true (morph-to-topology-changing-request? request))
  (hash-set! mutable-birth-map 1 0)
  (hash-set! mutable-death-map 0 0)
  (define animated-scene
    (scene-play
     (scene-add (make-scene) panel)
     request
     #:duration 2))
  (define midpoint-path
    (path-visual-path
     (scene-state-ref (scene-sample animated-scene 1) 'panel)))
  (check-equal? (length (path-geometry-subpaths midpoint-path)) 3)
  (define-values (normalized-source normalized-destination)
    (path-geometry-normalize-for-morph mapped-source mapped-destination))
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

  ;; Maps are numeric sparse overrides and therefore require AJ numeric mode.
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                source destination #:birth-penalty-map (hash 0 2))))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                panel destination #:death-penalty-map (hash 0 2))))

  ;; Map validation mirrors anchor-map index semantics but accepts only finite
  ;; nonnegative numeric costs.
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                source destination
                #:birth-penalty 2 #:death-penalty 2
                #:birth-penalty-map '())))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                panel destination
                #:birth-penalty 2 #:death-penalty 2
                #:birth-penalty-map (hash -1 2))))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                panel destination
                #:birth-penalty 2 #:death-penalty 2
                #:death-penalty-map (hash 0 -1))))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-topology-changing
                panel destination
                #:birth-penalty 2 #:death-penalty 2
                #:birth-penalty-map (hash 0 +inf.0))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                source destination
                #:birth-penalty 2 #:death-penalty 2
                #:birth-penalty-map (hash 2 5))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-prepare-topology-changing-morph
                source destination
                #:birth-penalty 2 #:death-penalty 2
                #:death-penalty-map (hash 2 5))))

  ;; Source range can only be known at clip compilation for a request.
  (define bad-range-request
    (morph-to-topology-changing
     panel
     destination
     #:birth-penalty 2
     #:death-penalty 2
     #:death-penalty-map (hash 2 5)))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                bad-range-request)))

  (define bad-birth-range-request
    (morph-to-topology-changing
     panel
     destination
     #:birth-penalty 2
     #:death-penalty 2
     #:birth-penalty-map (hash 2 5)))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                bad-birth-range-request)))

  ;; SCENE-AL changes cost policy only; the path-geometry animation component
  ;; conflict remains unchanged.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                request
                (morph-to-normalized panel destination)))))
