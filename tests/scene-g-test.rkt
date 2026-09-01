#lang racket/base

;;;
;;; SCENE-G Model Tests
;;;

;; Tests semantic cubic Bézier segments, curve bounds, deterministic length
;; approximation, partial-curve extraction, and path reveal.


;;;
;;; Imports
;;;

(require rackunit
         (only-in racket/math pi)
         "../main.rkt")


(module+ test
  ;; Cubic segments store two control points and one endpoint. Their start point
  ;; remains implicit in the containing subpath.

  ; arch-segment : cubic-bezier-path-segment?
  ;;   Gives one symmetric cubic arch segment.
  (define arch-segment
    (cubic-bezier-path-segment (vec2 -1 2)
                               (vec2 1 2)
                               (vec2 1 0)))

  (check-true (path-segment? arch-segment))
  (check-equal? (cubic-bezier-path-segment-control1 arch-segment)
                (vec2 -1 2))
  (check-equal? (cubic-bezier-path-segment-control2 arch-segment)
                (vec2 1 2))
  (check-equal? (cubic-bezier-path-segment-end arch-segment)
                (vec2 1 0))
  (check-exn exn:fail:contract?
             (lambda ()
               (cubic-bezier-path-segment origin
                                          'not-a-point
                                          origin)))

  ; arch-path : path-geometry?
  ;;   Gives one open cubic arch from negative x to positive x.
  (define arch-path
    (cubic-bezier-path (vec2 -1 0)
                       (list arch-segment)))

  ; arch-subpath : path-subpath?
  ;;   Gives the sole subpath of arch-path.
  (define arch-subpath
    (car (path-geometry-subpaths arch-path)))

  (check-false (path-subpath-closed? arch-subpath))
  (check-equal? (path-subpath-points arch-subpath)
                (list (vec2 -1 0)
                      (vec2 1 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (cubic-bezier-path origin '())))

  ; closed-arch-path : path-geometry?
  ;;   Gives the same cubic plus an implicit straight closing edge.
  (define closed-arch-path
    (cubic-bezier-path (vec2 -1 0)
                       (list arch-segment)
                       #:closed? #t))
  (check-true
   (path-subpath-closed?
    (car (path-geometry-subpaths closed-arch-path))))

  ;; Point mapping transforms both control points and endpoints while
  ;; preserving segment kind, subpath order, and closure.

  ; shifted-arch-path : path-geometry?
  ;;   Gives arch-path shifted right by three and down by one.
  (define shifted-arch-path
    (path-geometry-translate arch-path (vec2 3 -1)))

  ; shifted-arch-subpath : path-subpath?
  ;;   Gives the sole shifted subpath.
  (define shifted-arch-subpath
    (car (path-geometry-subpaths shifted-arch-path)))

  ; shifted-arch-segment : cubic-bezier-path-segment?
  ;;   Gives the shifted cubic segment.
  (define shifted-arch-segment
    (car (path-subpath-segments shifted-arch-subpath)))

  (check-equal? (path-subpath-start shifted-arch-subpath)
                (vec2 2 -1))
  (check-equal?
   (cubic-bezier-path-segment-control1 shifted-arch-segment)
   (vec2 2 1))
  (check-equal?
   (cubic-bezier-path-segment-control2 shifted-arch-segment)
   (vec2 4 1))
  (check-equal? (cubic-bezier-path-segment-end shifted-arch-segment)
                (vec2 4 -1))

  ;; Curve bounds use derivative extrema, not the larger control-point box.

  (define-values (arch-minimum-x
                  arch-minimum-y
                  arch-maximum-x
                  arch-maximum-y)
    (path-geometry-bounds arch-path))
  (check-equal? arch-minimum-x -1)
  (check-equal? arch-minimum-y 0)
  (check-equal? arch-maximum-x 1)
  (check-equal? arch-maximum-y 3/2)
  (check-equal? (path-geometry-center arch-path)
                (vec2 0 3/4))

  ;; Straight cubic geometry has exact chord length. Curved geometry uses the
  ;; deterministic adaptive approximation.

  ; straight-cubic-path : path-geometry?
  ;;   Gives a three-unit straight line represented as one cubic segment.
  (define straight-cubic-path
    (cubic-bezier-path
     origin
     (list
      (cubic-bezier-path-segment (vec2 1 0)
                                 (vec2 2 0)
                                 (vec2 3 0)))))

  (check-equal? (path-geometry-length straight-cubic-path)
                3)
  (check-equal? (path-geometry-length
                 (cubic-bezier-path
                  origin
                  (list
                   (cubic-bezier-path-segment (vec2 1 0)
                                              (vec2 2 0)
                                              (vec2 3 0)))
                  #:closed? #t))
                6)
  (check-= (path-geometry-length arch-path)
           4
           1e-7)

  ; circle-kappa : positive-real?
  ;;   Gives the common one-segment quarter-circle control factor.
  (define circle-kappa
    (* 4/3 (- (sqrt 2) 1)))

  ; quarter-circle-path : path-geometry?
  ;;   Gives the standard cubic approximation of a unit quarter circle.
  (define quarter-circle-path
    (cubic-bezier-path
     (vec2 1 0)
     (list
      (cubic-bezier-path-segment (vec2 1 circle-kappa)
                                 (vec2 circle-kappa 1)
                                 (vec2 0 1)))))

  (check-= (path-geometry-length quarter-circle-path)
           1.5710167
           1e-6)
  (check-= (path-geometry-length quarter-circle-path)
           (/ pi 2)
           3e-4)

  ;; Partial extraction preserves cubic segment structure and uses de
  ;; Casteljau subdivision at the selected arc-length positions.

  ; first-half-path : path-geometry?
  ;;   Gives the first half of the straight cubic path.
  (define first-half-path
    (path-geometry-partial straight-cubic-path 0 1/2))

  ; first-half-subpath : path-subpath?
  ;;   Gives the sole first-half subpath.
  (define first-half-subpath
    (car (path-geometry-subpaths first-half-path)))

  ; first-half-segment : cubic-bezier-path-segment?
  ;;   Gives the subdivided first-half cubic segment.
  (define first-half-segment
    (car (path-subpath-segments first-half-subpath)))

  (check-equal? (path-subpath-start first-half-subpath)
                origin)
  (check-equal?
   (cubic-bezier-path-segment-control1 first-half-segment)
   (vec2 1/2 0))
  (check-equal?
   (cubic-bezier-path-segment-control2 first-half-segment)
   (vec2 1 0))
  (check-equal? (cubic-bezier-path-segment-end first-half-segment)
                (vec2 3/2 0))

  ; second-half-path : path-geometry?
  ;;   Gives the second half of the straight cubic path.
  (define second-half-path
    (path-geometry-partial straight-cubic-path 1/2 1))

  ; second-half-subpath : path-subpath?
  ;;   Gives the sole second-half subpath.
  (define second-half-subpath
    (car (path-geometry-subpaths second-half-path)))

  ; second-half-segment : cubic-bezier-path-segment?
  ;;   Gives the subdivided second-half cubic segment.
  (define second-half-segment
    (car (path-subpath-segments second-half-subpath)))

  (check-equal? (path-subpath-start second-half-subpath)
                (vec2 3/2 0))
  (check-equal?
   (cubic-bezier-path-segment-control1 second-half-segment)
   (vec2 2 0))
  (check-equal?
   (cubic-bezier-path-segment-control2 second-half-segment)
   (vec2 5/2 0))
  (check-equal? (cubic-bezier-path-segment-end second-half-segment)
                (vec2 3 0))

  ; arch-first-half : path-geometry?
  ;;   Gives the first half by arc length of the symmetric arch.
  (define arch-first-half
    (path-geometry-partial arch-path 0 1/2))

  ; arch-first-half-segment : cubic-bezier-path-segment?
  ;;   Gives the preserved cubic segment for arch-first-half.
  (define arch-first-half-segment
    (car
     (path-subpath-segments
      (car (path-geometry-subpaths arch-first-half)))))

  (check-true
   (cubic-bezier-path-segment? arch-first-half-segment))
  (check-= (vec2-x
            (cubic-bezier-path-segment-end arch-first-half-segment))
           0
           1e-8)
  (check-= (vec2-y
            (cubic-bezier-path-segment-end arch-first-half-segment))
           3/2
           1e-8)
  (check-eq? (path-geometry-partial arch-path 0 1)
             arch-path)

  ;; Mixed segment kinds keep significant traversal order.

  ; mixed-path : path-geometry?
  ;;   Gives a line followed by one collinear cubic segment.
  (define mixed-path
    (path-geometry
     (list
      (path-subpath origin
                    (list (line-path-segment (vec2 2 0))
                          (cubic-bezier-path-segment (vec2 3 0)
                                                     (vec2 4 0)
                                                     (vec2 5 0)))
                    #f))))

  (check-equal? (path-geometry-length mixed-path)
                5)
  (check-equal?
   (map path-segment?
        (path-subpath-segments
         (car
          (path-geometry-subpaths
           (path-geometry-partial mixed-path 1/5 4/5)))))
   (list #t #t))

  ;; Zero-length cubics do not consume reveal progress.

  ; zero-cubic-path : path-geometry?
  ;;   Gives a cubic whose four defining points are identical.
  (define zero-cubic-path
    (cubic-bezier-path
     origin
     (list
      (cubic-bezier-path-segment origin origin origin))))

  (check-equal? (path-geometry-length zero-cubic-path)
                0)
  (check-true
   (path-geometry-empty?
    (path-geometry-partial zero-cubic-path 0 1/2)))

  ;; Create and Uncreate use the same semantic curve extraction without a new
  ;; public animation interface.

  ; arch-visual : path-visual?
  ;;   Gives arch-path as a styled path Visual.
  (define arch-visual
    (make-path-visual arch-path
                      #:id 'arch
                      #:stroke "navy"
                      #:stroke-width 3))

  ; create-scene : scene?
  ;;   Gives one second of cubic path creation.
  (define create-scene
    (scene-play (make-scene)
                (create arch-visual)
                #:duration 1))

  ; created-midpoint : path-visual?
  ;;   Gives the visible first half of arch-visual.
  (define created-midpoint
    (scene-state-ref (scene-sample create-scene 1/2)
                     'arch))

  ; created-midpoint-segment : cubic-bezier-path-segment?
  ;;   Gives the cubic segment stored at the creation midpoint.
  (define created-midpoint-segment
    (car
     (path-subpath-segments
      (car
       (path-geometry-subpaths
        (path-visual-path created-midpoint))))))

  (check-true
   (cubic-bezier-path-segment? created-midpoint-segment))
  (check-equal? (path-visual-path
                 (scene-state-ref (scene-sample create-scene 1)
                                  'arch))
                arch-path)

  ; uncreate-scene : scene?
  ;;   Gives one second of cubic path removal.
  (define uncreate-scene
    (scene-play (scene-add (make-scene) arch-visual)
                (uncreate arch-visual)
                #:duration 1))

  (check-true
   (cubic-bezier-path-segment?
    (car
     (path-subpath-segments
      (car
       (path-geometry-subpaths
        (path-visual-path
         (scene-state-ref (scene-sample uncreate-scene 1/2)
                          'arch))))))))
  (check-false
   (scene-state-has? (scene-sample uncreate-scene 1)
                     'arch)))
