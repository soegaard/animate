#lang racket/base

;;;
;;; SCENE-AE Automatic Open-Path Morph Correspondence Model Tests
;;;

;; Tests deterministic endpoint-direction selection, optional traversal
;; reversal, cubic alignment, validation, and timeline integration.
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
  ;;   Checks representative total-arc-length samples on two open paths.
  (define (check-path-samples~= actual expected tolerance)
    (for ([fraction
           (in-list '(0 1/20 1/10 1/5 7/20 1/2 13/20 4/5 9/10 19/20 1))])
      (check-vec2~=
       (path-geometry-point-at actual fraction)
       (path-geometry-point-at expected fraction)
       tolerance)))

  ;; A deliberately asymmetric open path gives the endpoint direction a clear
  ;; geometric answer.
  (define source
    (polyline-path
     (list (vec2 -5 -2)
           (vec2 -3 1)
           (vec2 -1 3)
           (vec2 2 2)
           (vec2 5 -1))))
  (define reversed-source
    (path-geometry-reverse source))
  (define aligned-reverse
    (path-geometry-align-open-for-morph source reversed-source))
  (check-path-samples~= aligned-reverse source 1e-10)

  ;; Disabling reversal keeps the exact stored destination object even when its
  ;; endpoint correspondence is much worse.
  (check-eq?
   (path-geometry-align-open-for-morph
    source reversed-source #:allow-reverse? #f)
   reversed-source)
  (define forward-only-probe
    (path-geometry-point-at reversed-source 1/5))
  (define source-probe
    (path-geometry-point-at source 1/5))
  (check-true
   (> (+ (abs (- (vec2-x forward-only-probe) (vec2-x source-probe)))
         (abs (- (vec2-y forward-only-probe) (vec2-y source-probe))))
      1))

  ;; An already aligned open path remains the exact destination object.
  (check-eq?
   (path-geometry-align-open-for-morph source source)
   source)

  ;; A retraced open path has an exact forward/reverse score tie. The public
  ;; tie rule keeps the caller's forward destination representation.
  (define direction-tie-path
    (polyline-path
     (list origin (vec2 2 0) origin)))
  (check-eq?
   (path-geometry-align-open-for-morph
    direction-tie-path direction-tie-path)
   direction-tie-path)

  ;; Cubic open paths use the same deterministic adaptive arc-length tables as
  ;; SCENE-Y/AC. Reversal changes endpoint correspondence without changing the
  ;; traced curve.
  (define cubic-source
    (cubic-bezier-path
     (vec2 -4 -1)
     (list
      (cubic-bezier-path-segment
       (vec2 -4 3)
       (vec2 -1 4)
       (vec2 0 1))
      (cubic-bezier-path-segment
       (vec2 2 -3)
       (vec2 4 -2)
       (vec2 5 2)))))
  (define cubic-reversed
    (path-geometry-reverse cubic-source))
  (define cubic-aligned
    (path-geometry-align-open-for-morph
     cubic-source cubic-reversed #:sample-count 96))
  (check-path-samples~= cubic-aligned cubic-source 2e-4)

  ;; Timeline integration chooses endpoint direction first, then reuses the
  ;; existing normalized cubic morph. Progress zero and one preserve exact
  ;; caller-visible source/destination representations.
  (define canonical-destination
    (cubic-bezier-path
     (vec2 -5 2)
     (list
      (cubic-bezier-path-segment
       (vec2 -3 4)
       (vec2 -1 -2)
       (vec2 0 -1))
      (cubic-bezier-path-segment
       (vec2 2 3)
       (vec2 4 4)
       (vec2 5 1)))))
  (define stored-destination
    (path-geometry-reverse canonical-destination))
  (define panel
    (make-path-visual cubic-source
                      #:id 'panel
                      #:stroke "navy"
                      #:stroke-width 4))
  (define request
    (morph-to-open-aligned panel stored-destination))
  (check-true (morph-to-open-aligned-request? request))
  (check-true
   (morph-to-open-aligned-request?
    (morph-to-open-aligned
     'panel stored-destination
     #:allow-reverse? #f
     #:sample-count 32)))

  (define animated-scene
    (scene-play
     (scene-add (make-scene) panel)
     request
     (move-to panel (vec2 1 -1))
     #:duration 2))
  (define aligned-destination
    (path-geometry-align-open-for-morph
     cubic-source stored-destination))
  (define-values (normalized-source normalized-destination)
    (path-geometry-normalize-for-morph
     cubic-source aligned-destination))
  (define midpoint
    (scene-state-ref (scene-sample animated-scene 1) 'panel))
  (check-equal?
   (path-visual-path midpoint)
   (path-geometry-lerp normalized-source normalized-destination 1/2))
  (check-equal? (visual-position midpoint) (vec2 1/2 -1/2))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 0) 'panel))
   cubic-source)
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample animated-scene 2) 'panel))
   stored-destination)

  ;; The new request reserves the ordinary path-geometry animation component.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-open-aligned panel stored-destination)
                (morph-to-normalized panel canonical-destination))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play
                (scene-add (make-scene) panel)
                (morph-to-open-aligned panel stored-destination)
                (uncreate panel))))

  ;; Validation is explicit: exactly one open positive finite subpath on each
  ;; side, plus the same deterministic option constraints as closed alignment.
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-open-aligned
                (circle #:id 'not-path)
                stored-destination)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-open-aligned
                panel stored-destination #:allow-reverse? 'yes)))
  (check-exn exn:fail:contract?
             (lambda ()
               (morph-to-open-aligned
                panel stored-destination #:sample-count 7)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-open-for-morph
                (polygon-path (list origin (vec2 1 0) (vec2 0 1)))
                source)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-open-for-morph
                source
                (path-geometry
                 (append (path-geometry-subpaths source)
                         (path-geometry-subpaths source))))))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-open-for-morph
                (path-geometry (list (path-subpath origin '() #f)))
                source)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-align-open-for-morph
                source source #:sample-count 8.0))))
