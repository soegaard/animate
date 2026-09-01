#lang racket/base

;;;
;;; SCENE-AG Mixed-Topology Compound Morph Correspondence Model Tests
;;;

;; Tests topology-class partitioning, global pairing within each class,
;; per-pair open/closed correspondence, exact endpoints, and timeline integration.

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

  (define (check-open-subpath~= actual expected tolerance)
    (define actual-path (subpath-geometry actual))
    (define expected-path (subpath-geometry expected))
    (for ([fraction (in-list '(0 1/8 1/4 3/8 1/2 5/8 3/4 7/8 1))])
      (check-vec2~=
       (path-geometry-point-at actual-path fraction)
       (path-geometry-point-at expected-path fraction)
       tolerance)))

  (define (check-closed-subpath~= actual expected tolerance)
    (define actual-path (subpath-geometry actual))
    (define expected-path (subpath-geometry expected))
    (for ([fraction (in-list '(0 1/8 1/4 3/8 1/2 5/8 3/4 7/8))])
      (check-vec2~=
       (path-geometry-point-at actual-path fraction)
       (path-geometry-point-at expected-path fraction)
       tolerance)))

  (define open-a
    (cubic-bezier-path
     (vec2 -9 -2)
     (list
      (cubic-bezier-path-segment
       (vec2 -8 3)
       (vec2 -5 3)
       (vec2 -4 -1)))))
  (define closed-a
    (polygon-path
     (list (vec2 -3 -2)
           (vec2 0 -2)
           (vec2 0 1)
           (vec2 -3 1))))
  (define open-b
    (polyline-path
     (list (vec2 2 2)
           (vec2 4 -2)
           (vec2 6 -1)
           (vec2 8 2))))
  (define closed-b
    (polygon-path
     (list (vec2 4 3)
           (vec2 7 3)
           (vec2 8 5)
           (vec2 6 7)
           (vec2 3 5))))

  ;; Source order deliberately interleaves topology classes. Destination keeps
  ;; the same closure pattern at each storage position so ordinary normalized
  ;; morphing is legal, but swaps identities inside both topology classes and
  ;; independently reverses/cycles their traversal.
  (define source
    (combine-paths open-a closed-a open-b closed-b))
  (define destination
    (combine-paths
     (path-geometry-reverse open-b)
     (path-geometry-cycle-start (path-geometry-reverse closed-b) 2/5)
     (path-geometry-reverse open-a)
     (path-geometry-cycle-start (path-geometry-reverse closed-a) 1/4)))
  (define aligned
    (path-geometry-align-mixed-compound-for-morph
     source destination #:sample-count 24))
  (define source-subpaths (path-geometry-subpaths source))
  (define aligned-subpaths (path-geometry-subpaths aligned))
  (check-open-subpath~= (list-ref aligned-subpaths 0)
                        (list-ref source-subpaths 0)
                        2e-4)
  (check-closed-subpath~= (list-ref aligned-subpaths 1)
                          (list-ref source-subpaths 1)
                          2e-4)
  (check-open-subpath~= (list-ref aligned-subpaths 2)
                        (list-ref source-subpaths 2)
                        2e-4)
  (check-closed-subpath~= (list-ref aligned-subpaths 3)
                          (list-ref source-subpaths 3)
                          2e-4)

  ;; A no-op reuses the exact destination object.
  (check-eq?
   (path-geometry-align-mixed-compound-for-morph
    source source #:sample-count 16)
   source)

  ;; The mixed-capable API reduces to the existing homogeneous APIs when one
  ;; topology class is absent.
  (define all-open-source (combine-paths open-a open-b))
  (define all-open-destination
    (combine-paths (path-geometry-reverse open-b)
                   (path-geometry-reverse open-a)))
  (check-equal?
   (path-geometry-align-mixed-compound-for-morph
    all-open-source all-open-destination #:sample-count 16)
   (path-geometry-align-open-compound-for-morph
    all-open-source all-open-destination #:sample-count 16))
  (define all-closed-source (combine-paths closed-a closed-b))
  (define all-closed-destination
    (combine-paths
     (path-geometry-cycle-start closed-b 1/5)
     (path-geometry-cycle-start closed-a 1/4)))
  (check-equal?
   (path-geometry-align-mixed-compound-for-morph
    all-closed-source all-closed-destination #:sample-count 16)
   (path-geometry-align-compound-for-morph
    all-closed-source all-closed-destination #:sample-count 16))

  ;; Pairing is constrained by topology even when a geometrically nearby path
  ;; of the other class exists. The aligned result preserves source closure order.
  (check-equal?
   (map path-subpath-closed? aligned-subpaths)
   (map path-subpath-closed? source-subpaths))

  ;; Forward-only mode keeps stored direction/phase but still performs the
  ;; topology-class assignment.
  (define forward-only
    (path-geometry-align-mixed-compound-for-morph
     source destination #:allow-reverse? #f #:sample-count 16))
  (check-equal? (map path-subpath-closed? (path-geometry-subpaths forward-only))
                (map path-subpath-closed? source-subpaths))

  ;; Timeline integration aligns only the interior correspondence. Exact source
  ;; and exact caller-requested destination storage are restored at endpoints.
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "navy"
                      #:stroke-width 4))
  (define request
    (morph-to-mixed-compound-aligned panel destination #:sample-count 24))
  (check-true (morph-to-mixed-compound-aligned-request? request))
  (check-true
   (morph-to-mixed-compound-aligned-request?
    (morph-to-mixed-compound-aligned
     'panel destination #:allow-reverse? #f #:sample-count 16)))
  (define animated-scene
    (scene-play
     (scene-add (make-scene) panel)
     request
     (move-to panel (vec2 2 -1))
     #:duration 2))
  (define-values (normalized-source normalized-destination)
    (path-geometry-normalize-for-morph source aligned))
  (define midpoint
    (scene-state-ref (scene-sample animated-scene 1) 'panel))
  (check-equal?
   (path-visual-path midpoint)
   (path-geometry-lerp normalized-source normalized-destination 1/2))
  (check-equal? (visual-position midpoint) (vec2 1 -1/2))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 0) 'panel))
   source)
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 2) 'panel))
   destination)

  ;; The request reserves the ordinary path-geometry component.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-mixed-compound-aligned panel destination)
                (morph-to-normalized panel destination))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-mixed-compound-aligned panel destination)
                (uncreate panel))))

  ;; Validation requires nonempty positive finite subpaths and matching counts
  ;; inside each closure class. Unequal topology counts remain birth/death work.
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-mixed-compound-aligned
                (circle #:id 'not-path)
                destination)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-mixed-compound-aligned
                panel destination #:allow-reverse? 'yes)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-mixed-compound-aligned
                panel destination #:sample-count 7)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-mixed-compound-for-morph
                empty-path-geometry empty-path-geometry)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-mixed-compound-for-morph
                source
                (combine-paths open-a closed-a open-b open-a))))
  (define zero-open
    (path-geometry (list (path-subpath origin '() #f))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-mixed-compound-for-morph
                (combine-paths zero-open closed-a)
                (combine-paths open-a closed-a))))
  (define zero-closed
    (path-geometry (list (path-subpath origin '() #t))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-mixed-compound-for-morph
                (combine-paths open-a zero-closed)
                (combine-paths open-a closed-a))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-mixed-compound-for-morph
                source source #:sample-count 8.0))))
