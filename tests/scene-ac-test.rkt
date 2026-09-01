#lang racket/base

;;;
;;; SCENE-AC Automatic Closed-Loop Morph Correspondence Model Tests
;;;

;; Tests deterministic cyclic phase selection, optional traversal reversal,
;; cubic alignment, validation, and timeline integration.
;;
;; This module intentionally imports no Pict, bitmap, filesystem, or process
;; adapter.


;;;
;;; Imports
;;;

(require rackunit
         "../private/animation.rkt"
         "../private/geometry.rkt"
         "../private/path-geometry.rkt"
         "../private/scene-state.rkt"
         "../private/scene.rkt"
         "../private/visual-model.rkt")


(module+ test
  ; check-vec2~= : vec2? vec2? nonnegative-real? -> void?
  ;;   Checks two semantic points componentwise with tolerance.
  (define (check-vec2~= actual expected tolerance)
    (check-= (vec2-x actual) (vec2-x expected) tolerance)
    (check-= (vec2-y actual) (vec2-y expected) tolerance))

  ; check-path-samples~= : path-geometry? path-geometry? nonnegative-real?
  ;                        -> void?
  ;;   Checks representative total-arc-length samples on two paths.
  (define (check-path-samples~= actual expected tolerance)
    (for ([fraction
           (in-list '(0 1/20 1/10 1/5 7/20 1/2 13/20 4/5 9/10 19/20))])
      (check-vec2~=
       (path-geometry-point-at actual fraction)
       (path-geometry-point-at expected fraction)
       tolerance)))

  ;; An asymmetric loop gives direction and phase a unique geometric answer.
  (define source
    (polygon-path
     (list (vec2 -4 -1)
           (vec2 -2 2)
           (vec2 1 3)
           (vec2 4 1)
           (vec2 3 -2)
           (vec2 -1 -3))))

  ;; Same visible loop, same direction, but stored from a different vertex.
  (define phase-shifted
    (polygon-path
     (list (vec2 4 1)
           (vec2 3 -2)
           (vec2 -1 -3)
           (vec2 -4 -1)
           (vec2 -2 2)
           (vec2 1 3))))
  (define phase-aligned
    (path-geometry-align-for-morph
     source
     phase-shifted
     #:allow-reverse? #f))
  (check-path-samples~= phase-aligned source 1e-10)

  ;; Same visible loop, opposite direction, and a different stored start.
  (define reversed-shifted
    (polygon-path
     (list (vec2 4 1)
           (vec2 1 3)
           (vec2 -2 2)
           (vec2 -4 -1)
           (vec2 -1 -3)
           (vec2 3 -2))))
  (define automatically-aligned
    (path-geometry-align-for-morph source reversed-shifted))
  (check-path-samples~= automatically-aligned source 1e-10)

  ;; Disabling reversal preserves the destination traversal even when the
  ;; reversed correspondence is geometrically much better.
  (define forward-only
    (path-geometry-align-for-morph
     source
     reversed-shifted
     #:allow-reverse? #f))
  (define forward-only-probe
    (path-geometry-point-at forward-only 1/5))
  (define source-probe
    (path-geometry-point-at source 1/5))
  (check-true
   (> (+ (abs (- (vec2-x forward-only-probe) (vec2-x source-probe)))
         (abs (- (vec2-y forward-only-probe) (vec2-y source-probe))))
      1/10))

  ;; Already aligned loops preserve the destination object exactly.
  (check-eq? (path-geometry-align-for-morph source source) source)

  ;; A retraced two-edge closed loop has an exact forward/reverse score tie.
  ;; The public tie rule must keep the original forward destination object.
  (define direction-tie-loop
    (path-geometry
     (list
      (path-subpath origin
                    (list (line-path-segment (vec2 2 0)))
                    #t))))
  (check-eq?
   (path-geometry-align-for-morph direction-tie-loop direction-tie-loop)
   direction-tie-loop)

  ;; Cubic closed loops may also be phase-shifted inside a segment. Alignment
  ;; uses the same deterministic arc-length approximation as SCENE-Y/AB.
  (define cubic-source
    (cubic-bezier-path
     (vec2 -3 0)
     (list
      (cubic-bezier-path-segment
       (vec2 -3 3)
       (vec2 0 4)
       (vec2 2 2))
      (cubic-bezier-path-segment
       (vec2 4 0)
       (vec2 2 -3)
       (vec2 -1 -2)))
     #:closed? #t))
  (define cubic-shifted
    (path-geometry-cycle-start cubic-source 7/20))
  (define cubic-aligned
    (path-geometry-align-for-morph
     cubic-source
     cubic-shifted
     #:allow-reverse? #f
     #:sample-count 96))
  (check-path-samples~= cubic-aligned cubic-source 2e-4)

  ;; The new timeline request aligns first, then reuses the existing normalized
  ;; cubic morph representation. Exact source/destination representations are
  ;; still preserved at eased progress zero and one.
  (define canonical-destination
    (polygon-path
     (list (vec2 -7/2 -3/2)
           (vec2 -5/2 3/2)
           (vec2 0 7/2)
           (vec2 4 2)
           (vec2 4 -1)
           (vec2 0 -5/2))))
  ;; Store the destination from a deliberately unhelpful reverse start.
  (define stored-destination
    (polygon-path
     (list (vec2 4 2)
           (vec2 0 7/2)
           (vec2 -5/2 3/2)
           (vec2 -7/2 -3/2)
           (vec2 0 -5/2)
           (vec2 4 -1))))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:fill "cornflowerblue"
                      #:stroke "navy"
                      #:stroke-width 4))
  (define aligned-request
    (morph-to-aligned panel stored-destination))
  (check-true (morph-to-aligned-request? aligned-request))
  (check-true
   (morph-to-aligned-request?
    (morph-to-aligned 'panel
                      stored-destination
                      #:allow-reverse? #f
                      #:sample-count 32)))

  (define aligned-scene
    (scene-play
     (scene-add (make-scene) panel)
     aligned-request
     (move-to panel (vec2 1 -1))
     #:duration 2))
  (define aligned-destination
    (path-geometry-align-for-morph source stored-destination))
  (define-values (normalized-source normalized-destination)
    (path-geometry-normalize-for-morph source aligned-destination))
  (define midpoint
    (scene-state-ref (scene-sample aligned-scene 1) 'panel))
  (check-equal?
   (path-visual-path midpoint)
   (path-geometry-lerp normalized-source normalized-destination 1/2))
  (check-equal? (visual-position midpoint) (vec2 1/2 -1/2))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample aligned-scene 0) 'panel))
   source)
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample aligned-scene 2) 'panel))
   stored-destination)

  ;; The aligned request reserves the same path-geometry component as every
  ;; other morph/reveal request.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-aligned panel stored-destination)
                (morph-to-normalized panel canonical-destination))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-aligned panel stored-destination)
                (uncreate panel))))

  ;; Constructor and geometry validation remain explicit. Automatic alignment
  ;; deliberately handles one positive closed loop, not open/compound paths.
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-aligned (circle #:id 'not-path)
                                 stored-destination)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-aligned panel stored-destination
                                 #:allow-reverse? 'yes)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-aligned panel stored-destination
                                 #:sample-count 7)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-for-morph
                (polyline-path (list origin (vec2 1 0)))
                source)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-for-morph
                source
                (path-geometry
                 (append (path-geometry-subpaths source)
                         (path-geometry-subpaths source))))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-for-morph
                (path-geometry (list (path-subpath origin '() #t)))
                source)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-for-morph
                source source
                #:sample-count 8.0))))
