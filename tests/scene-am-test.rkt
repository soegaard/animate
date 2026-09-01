#lang racket/base

;;;
;;; SCENE-AM Per-Pair Match Penalty Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define (combine-paths . geometries)
    (path-geometry
     (apply append
            (for/list ([geometry (in-list geometries)])
              (path-geometry-subpaths geometry)))))

  (define source-top
    (polyline-path (list (vec2 -1 4) (vec2 1 4))))
  (define source-bottom
    (polyline-path (list (vec2 -1 -4) (vec2 1 -4))))
  (define destination-top
    (polyline-path (list (vec2 -1 4) (vec2 1 4))))
  (define destination-bottom
    (polyline-path (list (vec2 -1 -4) (vec2 1 -4))))
  (define source
    (combine-paths source-top source-bottom))
  (define destination
    (combine-paths destination-top destination-bottom))
  (define destination-subpaths
    (path-geometry-subpaths destination))

  ;; Forced mode normally selects the spatially identical pairing. A sparse
  ;; real-edge penalty can change that global pairing without enabling births or
  ;; deaths. Keys use original caller indexes, not topology-class positions.
  (define-values (default-source default-destination)
    (path-geometry-prepare-topology-changing-morph
     source destination #:sample-count 8))
  (check-eq? default-source source)
  (check-eq? default-destination destination)

  (define-values (cross-source cross-destination)
    (path-geometry-prepare-topology-changing-morph
     source destination
     #:sample-count 8
     #:match-penalty-map (hash (cons 0 0) 1000)))
  (check-eq? cross-source source)
  (define crossed-subpaths (path-geometry-subpaths cross-destination))
  (check-eq? (list-ref crossed-subpaths 0) (list-ref destination-subpaths 1))
  (check-eq? (list-ref crossed-subpaths 1) (list-ref destination-subpaths 0))

  ;; Closed-loop candidates use the same original-index pair penalties after
  ;; SCENE-AC phase/direction alignment has selected each edge's geometric score.
  (define closed-source
    (combine-paths
     (polygon-path (list (vec2 -1 5) (vec2 1 5) (vec2 1 7) (vec2 -1 7)))
     (polygon-path (list (vec2 -1 -7) (vec2 1 -7) (vec2 1 -5) (vec2 -1 -5)))))
  (define closed-destination
    (combine-paths
     (polygon-path (list (vec2 -1 5) (vec2 1 5) (vec2 1 7) (vec2 -1 7)))
     (polygon-path (list (vec2 -1 -7) (vec2 1 -7) (vec2 1 -5) (vec2 -1 -5)))))
  (define-values (closed-source* closed-destination*)
    (path-geometry-prepare-topology-changing-morph
     closed-source closed-destination
     #:sample-count 8
     #:match-penalty-map (hash (cons 0 0) 1000)))
  (check-eq? closed-source* closed-source)
  (check-eq? (list-ref (path-geometry-subpaths closed-destination*) 0)
             (list-ref (path-geometry-subpaths closed-destination) 1))

  ;; Empty maps preserve the exact historical forced/equal-count fast path.
  (define-values (empty-map-source empty-map-destination)
    (path-geometry-prepare-topology-changing-morph
     source destination
     #:sample-count 8
     #:match-penalty-map #hash()))
  (check-eq? empty-map-source source)
  (check-eq? empty-map-destination destination)

  ;; In numeric AJ mode the additive real-edge penalty participates in the same
  ;; primary objective as birth/death costs. A sufficiently costly match can be
  ;; replaced by one death plus one birth.
  (define single-source
    (polyline-path (list (vec2 -1 0) (vec2 1 0))))
  (define single-destination
    (polyline-path (list (vec2 -1 0) (vec2 1 0))))
  (define-values (numeric-match-source numeric-match-destination)
    (path-geometry-prepare-topology-changing-morph
     single-source single-destination
     #:sample-count 8
     #:birth-penalty 1
     #:death-penalty 1))
  (check-eq? numeric-match-source single-source)
  (check-eq? numeric-match-destination single-destination)

  (define-values (numeric-replaced-source numeric-replaced-destination)
    (path-geometry-prepare-topology-changing-morph
     single-source single-destination
     #:sample-count 8
     #:birth-penalty 1
     #:death-penalty 1
     #:match-penalty-map (hash (cons 0 0) 5)))
  (check-equal? (length (path-geometry-subpaths numeric-replaced-source)) 2)
  (check-equal? (length (path-geometry-subpaths numeric-replaced-destination)) 2)

  ;; AL dummy-edge overrides remain independent. Raising only the destination's
  ;; birth cost makes the same AM real edge cheaper than death+birth again.
  (define-values (composed-source composed-destination)
    (path-geometry-prepare-topology-changing-morph
     single-source single-destination
     #:sample-count 8
     #:birth-penalty 1
     #:death-penalty 1
     #:birth-penalty-map (hash 0 10)
     #:match-penalty-map (hash (cons 0 0) 5)))
  (check-eq? composed-source single-source)
  (check-eq? composed-destination single-destination)

  ;; Exact primary-cost ties still use AJ's secondary objective and retain the
  ;; real match instead of performing unnecessary topology changes.
  (define-values (tie-source tie-destination)
    (path-geometry-prepare-topology-changing-morph
     single-source single-destination
     #:sample-count 8
     #:birth-penalty 1
     #:death-penalty 1
     #:match-penalty-map (hash (cons 0 0) 2)))
  (check-eq? tie-source single-source)
  (check-eq? tie-destination single-destination)

  ;; Forced unequal-count matching also honors real-edge penalties while the
  ;; count difference alone still determines the unavoidable birth slot.
  (define subset-source
    (polyline-path (list (vec2 -1 0) (vec2 1 0))))
  (define subset-near
    (polyline-path (list (vec2 -1 0) (vec2 1 0))))
  (define subset-far
    (polyline-path (list (vec2 5 0) (vec2 7 0))))
  (define subset-destination
    (combine-paths subset-near subset-far))
  (define-values (subset-default-source subset-default-destination)
    (path-geometry-prepare-topology-changing-morph
     subset-source subset-destination #:sample-count 8))
  (check-eq?
   (car (path-geometry-subpaths subset-default-destination))
   (car (path-geometry-subpaths subset-near)))
  (define-values (subset-mapped-source subset-mapped-destination)
    (path-geometry-prepare-topology-changing-morph
     subset-source subset-destination
     #:sample-count 8
     #:match-penalty-map (hash (cons 0 0) 1000)))
  (check-eq?
   (car (path-geometry-subpaths subset-mapped-destination))
   (car (path-geometry-subpaths subset-far)))
  (check-equal? (length (path-geometry-subpaths subset-mapped-source)) 2)

  ;; Pair keys are always original source/destination indexes, including across
  ;; interleaved topology classes. Open index 0 may target open destination 1;
  ;; an open-to-closed key is rejected because no such real assignment edge can
  ;; exist.
  (define source-closed
    (polygon-path
     (list (vec2 -2 -2) (vec2 0 -2) (vec2 0 0) (vec2 -2 0))))
  (define destination-closed
    (polygon-path
     (list (vec2 2 -2) (vec2 4 -2) (vec2 4 0) (vec2 2 0))))
  (define mixed-source
    (combine-paths single-source source-closed))
  (define mixed-destination
    (combine-paths destination-closed single-destination))
  (define-values (mixed-source* mixed-destination*)
    (path-geometry-prepare-topology-changing-morph
     mixed-source mixed-destination
     #:sample-count 8
     #:match-penalty-map (hash (cons 0 1) 3)))
  (check-equal? (length (path-geometry-subpaths mixed-source*)) 2)
  (check-equal? (length (path-geometry-subpaths mixed-destination*)) 2)
  (check-exn
   exn:fail:contract?
   (lambda ()
     (path-geometry-prepare-topology-changing-morph
      mixed-source mixed-destination
      #:sample-count 8
      #:match-penalty-map (hash (cons 0 0) 1))))

  ;; Direct preparation validates pair key shape, ranges, and finite
  ;; nonnegative values.
  (for ([bad-map (in-list
                  (list (hash (list 0 0) 1)
                        (hash (cons -1 0) 1)
                        (hash (cons 0 -1) 1)
                        (hash (cons 2 0) 1)
                        (hash (cons 0 2) 1)
                        (hash (cons 0 0) -1)
                        (hash (cons 0 0) +inf.0)))])
    (check-exn
     exn:fail:contract?
     (lambda ()
       (path-geometry-prepare-topology-changing-morph
        source destination
        #:sample-count 8
        #:match-penalty-map bad-map))))

  ;; Timeline requests snapshot mutable pair maps. Mutating the caller hash after
  ;; request construction cannot change correspondence when the clip compiles.
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 4))
  (define mutable-match-map
    (make-hash (list (cons (cons 0 0) 1000))))
  (define request
    (morph-to-topology-changing
     panel destination
     #:sample-count 8
     #:match-penalty-map mutable-match-map))
  (check-true (morph-to-topology-changing-request? request))
  (hash-set! mutable-match-map (cons 0 0) 0)
  (define mapped-scene
    (scene-play
     (scene-add (make-scene) panel)
     request
     #:duration 2))
  (define expected-scene
    (scene-play
     (scene-add (make-scene) panel)
     (morph-to-topology-changing
      panel destination
      #:sample-count 8
      #:match-penalty-map (hash (cons 0 0) 1000))
     #:duration 2))
  (check-equal?
   (path-visual-path
    (scene-state-ref (scene-sample mapped-scene 1) 'panel))
   (path-visual-path
    (scene-state-ref (scene-sample expected-scene 1) 'panel)))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample mapped-scene 2) 'panel))
   destination)

  ;; Request-time validation can reject malformed keys/values immediately even
  ;; though range/topology validation waits for the clip-start source geometry.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (morph-to-topology-changing
      panel destination
      #:match-penalty-map (hash (list 0 0) 1))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (morph-to-topology-changing
      panel destination
      #:match-penalty-map (hash (cons 0 0) -1))))
  (define out-of-range-request
    (morph-to-topology-changing
     panel destination
     #:match-penalty-map (hash (cons 2 0) 1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) panel)
      out-of-range-request
      #:duration 1)))

  ;; The new option is still the path-geometry animation component and therefore
  ;; retains the existing conflict rule.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) panel)
      (morph-to-topology-changing
       panel destination
       #:match-penalty-map (hash (cons 0 0) 1000))
      (morph-to-normalized panel destination)
      #:duration 1))))
