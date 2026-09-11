#lang racket/base

;; A visual regression/demo reel for the geometry authoring layer.  It is
;; intentionally broad rather than a single Euclidean construction: object
;; kinds, semantic markers, presentation actions, and helper expansion all get
;; a short plate that can be inspected in light or dark mode.
(require "../main.rkt" (prefix-in helper: "helpers.rkt"))
(provide geometry-gallery example-theme make-demo-timeline make-demo-scene)

(define (base-theme mode)
  (case mode
    [(dark) default-dark-geometry-theme]
    [else default-light-geometry-theme]))

(define (make-example-theme [mode 'light])
  (geometry-theme #:extends (base-theme mode)
    (stroke [width 2.5])
    (point [radius 0.06])
    (label [font-size 0.28])
    (circle (deemphasized (stroke [dash (7 5)])))
    (marker (size 0.18) (spacing 0.08) (radius 0.27))
    (highlighted (stroke [width 4.5]))))

(define example-theme (make-example-theme 'light))

(construction geometry-gallery
  ;; The DSL currently requires one given clause.  The hidden origin keeps the
  ;; gallery otherwise fully deterministic and self-contained.
  (given [origin (point 0 0)])
  (initially (hide origin) (hide-label origin))
  (timing
    [opening-pause 0.6]
    [read-delay 1.0]
    [action-duration 0.75]
    [step-pause 0.45])

  ;; ------------------------------------------------------------------
  ;; Primitive drawable geometry.
  (step "A point is a drawable geometric object."
    [P (point -4 3/2)])
  (step "A segment has two finite endpoints."
    [S (segment (point -7/2 1/2) (point -3/2 1/2))]
    (show-label S))
  (step "A line extends in both directions."
    [l (line (point -1 1) (point 1 3/2))]
    (show-label l))
  (step "A ray has one endpoint and extends in one direction."
    [r (ray (point 1/2 -1/4) (point 3/2 1/4))]
    (show-label r))
  (step "A circle is defined by its centre and a point on the circumference."
    [c (circle (point 3 1) (point 7/2 1))]
    (show-label c))
  (step #:duration 0.35 #:pause 0
    (together (hide P) (hide S) (hide l) (hide r) (hide c)))

  ;; ------------------------------------------------------------------
  ;; Midpoint and perpendicular markers share one clean diagram.
  (step "Midpoint ticks mark equal halves; a square marks a right angle."
    (together
      [h (segment (point -2 1) (point 2 1))]
      [v (segment (point 0 -1/2) (point 0 5/2))]
      [M (midpoint (point -2 1) (point 2 1))]
      [midmark (marker (midpoint-of M h))]
      [right-angle (marker (perpendicular h v #:at M))])
    (hide-label M))
  (assert (midpoint-of M h)
          (perpendicular h v #:at M))
  (step #:duration 0.35 #:pause 0
    (hide h v M midmark right-angle))

  ;; ------------------------------------------------------------------
  ;; Parallel marker.
  (step "Parallel objects use matching arrow marks."
    (together
      [p1 (segment (point -3 3/4) (point 3 3/4))]
      [p2 (segment (point -3 -1/4) (point 3 -1/4))]
      [parallel-mark (marker (parallel p1 p2))]))
  (assert (parallel p1 p2))
  (step #:duration 0.35 #:pause 0
    (hide p1 p2 parallel-mark))

  ;; ------------------------------------------------------------------
  ;; Equality classes.  Source order deliberately produces 1, 2 and 3 ticks.
  (step "Different equal-length classes use one, two, or three ticks."
    (together
      [a1 (segment (point -9/2 1) (point -7/2 1))]
      [a2 (segment (point -9/2 1/4) (point -7/2 1/4))]
      [b1 (segment (point -1/2 1) (point 1/2 1))]
      [b2 (segment (point -1/2 1/4) (point 1/2 1/4))]
      [d1 (segment (point 7/2 1) (point 9/2 1))]
      [d2 (segment (point 7/2 1/4) (point 9/2 1/4))]
      [equal-one (marker (equal-length a1 a2))]
      [equal-two (marker (equal-length b1 b2))]
      [equal-three (marker (equal-length d1 d2))]))
  (assert (equal-length a1 a2)
          (equal-length b1 b2)
          (equal-length d1 d2))
  (step #:duration 0.35 #:pause 0
    (hide a1 a2 b1 b2 d1 d2 equal-one equal-two equal-three))

  ;; ------------------------------------------------------------------
  ;; Angle and equal-angle markers.
  (step "An angle can be marked by an arc."
    (together
      [A0 (point -1 0)]
      [O0 (point 0 0)]
      [B0 (point 0 1)]
      [oa (segment O0 A0)]
      [ob (segment O0 B0)]
      [angle-mark (marker (angle A0 O0 B0))])
    (hide-label A0 O0 B0))
  (step #:duration 0.35 #:pause 0
    (hide A0 O0 B0 oa ob angle-mark))

  (step "Equal angles receive matching arc marks."
    (together
      [A2 (point -4 0)] [O2 (point -3 0)] [B2 (point -3 1)]
      [A3 (point 1 0)]  [O3 (point 2 0)]  [B3 (point 2 1)]
      [o2a (segment O2 A2)] [o2b (segment O2 B2)]
      [o3a (segment O3 A3)] [o3b (segment O3 B3)]
      [equal-angles (marker (equal-angle (angle A2 O2 B2)
                                         (angle A3 O3 B3)))])
    (hide-label A2 O2 B2 A3 O3 B3))
  (assert (equal-angle (angle A2 O2 B2)
                       (angle A3 O3 B3)))
  (step #:duration 0.35 #:pause 0
    (hide A2 O2 B2 A3 O3 B3 o2a o2b o3a o3b equal-angles))

  ;; ------------------------------------------------------------------
  ;; Presentation-state actions.
  (step "Several objects can appear together."
    (together
      [fxP (point -3 1/2)]
      [fxS (segment (point -1 0) (point 1 0))]
      [fxC (circle (point 3 1/2) (point 7/2 1/2))]))
  (step "Labels can be switched on without changing the geometry."
    (show-label fxS fxC))
  (step "Labels can also be removed again."
    (hide-label fxS fxC))
  (step "Auxiliary geometry can be made lighter."
    (deemphasize fxC))
  (step "Its normal style can be restored."
    (normalize fxC))
  (step "A highlight is temporary and leaves the stored state unchanged."
    (highlight fxP fxS))
  (step "Objects can be hidden."
    (hide fxP fxS fxC))
  (step "And several hidden objects can return together."
    (together (show fxP) (show fxS) (show fxC)))
  (step #:duration 0.35 #:pause 0
    (hide fxP fxS fxC))

  ;; ------------------------------------------------------------------
  ;; Reusable construction expansion.
  (step "Reusable constructions can expose their internal construction steps."
    (together
      [HA (point -1 0)]
      [HB (point 1 0)]))
  (step #:pause 0.7
    (expand [bisector (helper:perpendicular-bisector HA HB)]))
  (step "The helper returns its requested result while its construction remains visible."
    (highlight bisector)))

(define (gallery-view aspect)
  (make-geometry-view #:center (point 0 1/3)
                      #:world-width 12.0
                      #:aspect aspect
                      #:margin 0.08))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [theme-mode 'light])
  (construction->timeline geometry-gallery
                          #:theme (make-example-theme theme-mode)
                          #:view (gallery-view aspect)
                          #:aspect aspect))

(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [theme-mode 'light])
  (geometry-timeline->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode theme-mode)
                            #:width width #:height height))

(module+ main
  (require "private/run-example.rkt")
  (run-geometry-example "gallery"
                        (lambda (aspect theme-mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode theme-mode))))
