#lang racket/base

;;;
;;; SCENE-AF Automatic Open-Compound Morph Correspondence Model Tests
;;;

;; Tests global open-subpath pairing, per-pair endpoint direction, validation,
;; exact structural endpoints, and timeline integration without renderer state.

(require rackunit
         "../private/animation.rkt"
         "../private/geometry.rkt"
         "../private/path-geometry.rkt"
         "../private/scene-state.rkt"
         "../private/scene.rkt"
         "../private/visual-model.rkt")

(module+ test
  (define (one-subpath geometry)
    (car (path-geometry-subpaths geometry)))

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

  (define (check-open-samples~= actual expected tolerance)
    (define actual-geometry (subpath-geometry actual))
    (define expected-geometry (subpath-geometry expected))
    (for ([fraction (in-list '(0 1/8 1/4 3/8 1/2 5/8 3/4 7/8 1))])
      (check-vec2~=
       (path-geometry-point-at actual-geometry fraction)
       (path-geometry-point-at expected-geometry fraction)
       tolerance)))

  (define source-a
    (polyline-path
     (list (vec2 -9 -2)
           (vec2 -7 2)
           (vec2 -5 1)
           (vec2 -3 3))))
  (define source-b
    (cubic-bezier-path
     (vec2 -1 -3)
     (list
      (cubic-bezier-path-segment
       (vec2 0 2)
       (vec2 2 2)
       (vec2 3 -1)))))
  (define source-c
    (polyline-path
     (list (vec2 5 3)
           (vec2 6 -1)
           (vec2 8 -2)
           (vec2 10 1))))
  (define source
    (combine-paths source-a source-b source-c))

  ;; Store the same paths in unrelated order, independently reversing two of
  ;; them. Correct global pairing plus endpoint direction has total score zero.
  (define stored-destination
    (combine-paths
     (path-geometry-reverse source-c)
     source-a
     (path-geometry-reverse source-b)))
  (define aligned
    (path-geometry-align-open-compound-for-morph
     source stored-destination #:sample-count 24))
  (for ([actual (in-list (path-geometry-subpaths aligned))]
        [expected (in-list (path-geometry-subpaths source))])
    (check-open-samples~= actual expected 2e-4))

  ;; Already corresponding open compound geometry remains the exact destination
  ;; object rather than an equal reconstruction.
  (check-eq?
   (path-geometry-align-open-compound-for-morph
    source source #:sample-count 16)
   source)

  ;; A one-subpath compound request reduces exactly to SCENE-AE's endpoint rule.
  (check-equal?
   (path-geometry-align-open-compound-for-morph
    source-a (path-geometry-reverse source-a) #:sample-count 16)
   (path-geometry-align-open-for-morph
    source-a (path-geometry-reverse source-a) #:sample-count 16))

  ;; Global assignment is not greedy. Source x=10 is locally closer to x=9,
  ;; but the lower total cost is x=10 -> 12 and x=0 -> 9.
  (define (vertical-line-at x)
    (polyline-path (list (vec2 x -1) (vec2 x 1))))
  (define assignment-source
    (combine-paths (vertical-line-at 10)
                   (vertical-line-at 0)))
  (define assignment-destination
    (combine-paths (vertical-line-at 9)
                   (vertical-line-at 12)))
  (define assignment-aligned
    (path-geometry-align-open-compound-for-morph
     assignment-source assignment-destination #:sample-count 8))
  (define assignment-start-xs
    (for/list ([subpath (in-list (path-geometry-subpaths assignment-aligned))])
      (vec2-x (path-subpath-start subpath))))
  (check-equal? assignment-start-xs '(12 9))

  ;; Exact assignment ties are deterministic and retain ascending destination
  ;; storage order. Distinct but coincident subpath objects make identity visible.
  (define tie-source-0 (vertical-line-at 0))
  (define tie-source-1 (vertical-line-at 0))
  (define tie-destination-0 (one-subpath (vertical-line-at 0)))
  (define tie-destination-1 (one-subpath (vertical-line-at 0)))
  (define tie-destination
    (path-geometry (list tie-destination-0 tie-destination-1)))
  (define tie-aligned
    (path-geometry-align-open-compound-for-morph
     (combine-paths tie-source-0 tie-source-1)
     tie-destination
     #:sample-count 8))
  (check-eq? (car (path-geometry-subpaths tie-aligned)) tie-destination-0)
  (check-eq? (cadr (path-geometry-subpaths tie-aligned)) tie-destination-1)

  ;; Per-pair direction ties and the public reversal switch reuse AE semantics.
  (define direction-tie
    (polyline-path (list origin (vec2 2 0) origin)))
  (check-eq?
   (path-geometry-align-open-compound-for-morph
    direction-tie direction-tie #:sample-count 8)
   direction-tie)
  (define reversed-a (path-geometry-reverse source-a))
  (check-eq?
   (path-geometry-align-open-compound-for-morph
    source-a reversed-a #:allow-reverse? #f #:sample-count 16)
   reversed-a)

  ;; Timeline integration globally pairs first, normalizes corresponding open
  ;; paths, and still preserves the exact caller-requested storage at progress 1.
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "navy"
                      #:stroke-width 4))
  (define request
    (morph-to-open-compound-aligned
     panel stored-destination #:sample-count 24))
  (check-true (morph-to-open-compound-aligned-request? request))
  (check-true
   (morph-to-open-compound-aligned-request?
    (morph-to-open-compound-aligned
     'panel stored-destination
     #:allow-reverse? #f
     #:sample-count 16)))
  (define animated-scene
    (scene-play
     (scene-add (make-scene) panel)
     request
     (move-to panel (vec2 2 -1))
     #:duration 2))
  (define aligned-destination
    (path-geometry-align-open-compound-for-morph
     source stored-destination #:sample-count 24))
  (define-values (normalized-source normalized-destination)
    (path-geometry-normalize-for-morph source aligned-destination))
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
   stored-destination)

  ;; The request reserves the ordinary path-geometry animation component.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-open-compound-aligned panel stored-destination)
                (morph-to-normalized panel stored-destination))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-open-compound-aligned panel stored-destination)
                (uncreate panel))))

  ;; Validation deliberately requires equal, nonempty, positive finite open
  ;; subpath sets. Mixed/closed topology remains a later stage.
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-open-compound-aligned
                (circle #:id 'not-path)
                stored-destination)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-open-compound-aligned
                panel stored-destination #:allow-reverse? 'yes)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-open-compound-aligned
                panel stored-destination #:sample-count 7)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-open-compound-for-morph
                source
                (combine-paths source-a source-b))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-open-compound-for-morph
                empty-path-geometry empty-path-geometry)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-open-compound-for-morph
                (combine-paths source-a
                               (polygon-path
                                (list origin (vec2 1 0) (vec2 0 1))))
                (combine-paths source-a source-b))))
  (define zero-open
    (path-geometry (list (path-subpath origin '() #f))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-open-compound-for-morph
                (combine-paths source-a zero-open)
                (combine-paths source-a source-b))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-open-compound-for-morph
                source source #:sample-count 8.0))))
