#lang racket/base

;; A visual regression/demo reel for the geometry authoring layer.  It is
;; intentionally broad rather than a single Euclidean construction: object
;; kinds, semantic markers, presentation actions, and helper expansion all get
;; a short plate that can be inspected in light or dark mode.
;; Sparse review: racket geometry/review-examples.rkt --example gallery --dark
;; This writes triplets and paginated contact sheets without rendering a movie.
(require "../core.rkt" (prefix-in helper: "helpers.rkt")
         (prefix-in c: "../constructions.rkt") "private/library-example.rkt")
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

  ;; Reveal and layout metadata may refer forward to later plates.
  (reveal [reverse-S from-end] [center-S from-center]
          [clockwise-circle clockwise] [counterclockwise-circle counterclockwise]
          [fade-circle fade])
  (layout
    (label-text fxP "P") (label-text fxS "s") (label-text fxC "c")
    (label-text arc-letter "α")
    (label-text crowded-A "A") (label-text crowded-B "B")
    (label-text crowded-C "C (intersection)") (label-text crowded-M "M")
    (label-text crowded-D "D") (label-text crowded-E "E")
    (label-side crowded-A 'left) (label-side crowded-B 'right)
    (label-text tfA "A") (label-text tfB "B") (label-text tfAp "A′") (label-text tfBp "B′")
    (label-text tfAt "A′") (label-text tfBt "B′") (label-text tfAr "A′") (label-text tfBr "B′")
    (label-text tfAd "A′") (label-text tfBd "B′") (label-text origin "O")
    (label-text slA "A") (label-text slB "B") (label-text slC "C")
    (label-side slA 'below-left) (label-side slB 'below-right)
    (label-side slName 'above)
    (label-outside-of slBase slC)
    (label-outside-of slSideA slA) (label-outside-of slSideB slB)
    (label-outside-of slMeasured slA)
    (label-side crowded-C 'above)
    (label-at crowded-M (point 0.42 -0.32))
    (marker-position crowded-halves 0.42)
    (marker-radius arc-letter 0.34)
    (label-text LA "A") (label-text LB "B") (label-text LM "M")
    (label-text LP "P") (label-text LQ "Q") (label-text LH "H")
    (label-text CA0 "A") (label-text CB0 "B") (label-text CC0 "C")
    (label-text CO0 "O") (label-text CT "T")
    (label-text segment-A "A") (label-text segment-B "B")
    (label-text ray-origin "P") (label-text primitive-center "O") (label-text primitive-through "Q"))

  ;; ------------------------------------------------------------------
  ;; Primitive drawable geometry.
  (step "A point is a drawable geometric object."
    [P (point -4 3/2)])
  (step "A segment has two finite endpoints."
    (hide P)
    (together [segment-A (point -2 1)] [segment-B (point 2 1)])
    [S (segment segment-A segment-B)])
  (step "A line extends in both directions."
    (hide S segment-A segment-B)
    [l (line (point -1 1) (point 1 3/2))] (show-label l))
  (step "A ray has one endpoint and extends in one direction."
    (hide l) [ray-origin (point -1 0)]
    [r (ray ray-origin (point 1 1))] (show-label r))
  (step "A circle is defined by its centre and a point on the circumference."
    (hide r ray-origin)
    (together [primitive-center (point 0 1)] [primitive-through (point 1.5 1)])
    [c (circle primitive-center primitive-through)])
  (step #:duration 0.35 #:pause 0 (hide c primitive-center primitive-through))

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
      [b1 (segment (point -0.7 1) (point 0.7 1))]
      [b2 (segment (point -0.7 1/4) (point 0.7 1/4))]
      [d1 (segment (point 2.7 1) (point 4.5 1))]
      [d2 (segment (point 2.7 1/4) (point 4.5 1/4))]
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
  ;; Arc counts distinguish three concurrent angle-equality groups.
  (step "Matching arcs identify each pair of equal angles."
    (together
      [group1-1-base (segment (point -4 1.5) (point -3 1.5))]
      [group1-1-side (segment (point -4 1.5) (point -3.1339745962155616 2.0))]
      [group1-2-base (segment (point -4 -0.7) (point -3 -0.7))]
      [group1-2-side (segment (point -4 -0.7) (point -3.1339745962155616 -0.19999999999999996))]
      [angle-class-1 (marker (equal-angle
        (angle (point -3 1.5) (point -4 1.5) (point -3.1339745962155616 2.0))
        (angle (point -3 -0.7) (point -4 -0.7) (point -3.1339745962155616 -0.19999999999999996))))]
      [group2-1-base (segment (point 0 1.5) (point 1 1.5))]
      [group2-1-side (segment (point 0 1.5) (point 0.5 2.3660254037844384))]
      [group2-2-base (segment (point 0 -0.7) (point 1 -0.7))]
      [group2-2-side (segment (point 0 -0.7) (point 0.5 0.16602540378443864))]
      [angle-class-2 (marker (equal-angle
        (angle (point 1 1.5) (point 0 1.5) (point 0.5 2.3660254037844384))
        (angle (point 1 -0.7) (point 0 -0.7) (point 0.5 0.16602540378443864))))]
      [group3-1-base (segment (point 3.5 1.5) (point 4.5 1.5))]
      [group3-1-side (segment (point 3.5 1.5) (point 3.5 2.5))]
      [group3-2-base (segment (point 3.5 -0.7) (point 4.5 -0.7))]
      [group3-2-side (segment (point 3.5 -0.7) (point 3.5 0.30000000000000004))]
      [angle-class-3 (marker (equal-angle
        (angle (point 4.5 1.5) (point 3.5 1.5) (point 3.5 2.5))
        (angle (point 4.5 -0.7) (point 3.5 -0.7) (point 3.5 0.30000000000000004))))]
    ))
  (step #:duration 0.35 #:pause 0
    (hide group1-1-base group1-1-side group1-2-base group1-2-side angle-class-1 group2-1-base group2-1-side group2-2-base group2-2-side angle-class-2 group3-1-base group3-1-side group3-2-base group3-2-side angle-class-3))

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
  (step "The circle has a fixed centre and radius."
    (deemphasize fxC))
  (step "Every point on the circle is the same distance from its centre."
    (normalize fxC))
  (step "The segment has two endpoints and a fixed length."
    (highlight fxP fxS))
  (step "Objects can be hidden."
    (hide fxP fxS fxC))
  (step "And several hidden objects can return together."
    (together (show fxP) (show fxS) (show fxC)))
  (step #:duration 0.35 #:pause 0
    (hide fxP fxS fxC))

  ;; ------------------------------------------------------------------
  ;; Endpoint and direction-specific reveals. The mathematical description does
  ;; not need to talk about the renderer's drawing direction.
  (step "Each segment joins its two endpoints."
    [forward-S (segment (point -4 1.4) (point -2 1.4))]
    [reverse-S (segment (point -1 1.4) (point 1 1.4))]
    [center-S (segment (point 2 1.4) (point 4 1.4))])
  (step #:duration 0.35 #:pause 0 (hide forward-S reverse-S center-S))
  (step "A circumference point determines a circle's radius."
    (together
      [circle-U (point -3.5 1)] [circle-V (point -2.65 1)]
      [circle-O (point 0 1)] [circle-Q (point 0.85 1)]
      [circle-X (point 3.5 1)] [circle-Y (point 4.35 1)])
    (hide-label circle-U circle-V circle-O circle-Q circle-X circle-Y))
  (step "The three circles have equal radii."
    (together
      [two-front-circle (circle circle-U circle-V)]
      [clockwise-circle (circle circle-O circle-Q)]
      [counterclockwise-circle (circle circle-X circle-Y)]))
  (step #:duration 0.35 #:pause 0
    (hide circle-U circle-V circle-O circle-Q circle-X circle-Y
          two-front-circle clockwise-circle counterclockwise-circle))
  (step "This circle has the same radius."
    [fade-circle (circle (point 0 1) (point 0.85 1))])
  (step #:duration 0.35 #:pause 0 (hide fade-circle))

  ;; ------------------------------------------------------------------
  ;; A custom angle label and a dense diagram exercise the shared layout pass.
  (step "The arc identifies the angle α."
    (together
      [angle-base (segment (point 0 0) (point 2 0))]
      [angle-side (segment (point 0 0) (point 1 1.7))]
      [arc-letter (marker (angle (point 2 0) (point 0 0) (point 1 1.7)))])
    (show-label arc-letter))
  (step #:duration 0.35 #:pause 0 (hide angle-base angle-side arc-letter))
  (step "C and M lie on the same line."
    (together
      [crowded-A (point -2 0)] [crowded-B (point 2 0)]
      [crowded-C (point 0 2)] [crowded-M (point 0 0)]
      [crowded-D (point -0.2 0.55)] [crowded-E (point 0.3 0.8)]
      [crowded-base (segment crowded-A crowded-B)]
      [crowded-left (segment crowded-A crowded-C)]
      [crowded-right (segment crowded-B crowded-C)]
      [crowded-altitude (segment crowded-M crowded-C)]))
  (step "AM and MB are equal, and CM is perpendicular to AB."
    (together
      [crowded-halves (marker (midpoint-of crowded-M crowded-base))]
      [crowded-square (marker (perpendicular crowded-base crowded-altitude #:at crowded-M))]))
  (step "The equal parts meet at M."
    (highlight crowded-halves crowded-M))
  (step #:duration 0.35 #:pause 0
    (hide crowded-A crowded-B crowded-C crowded-M crowded-D crowded-E
          crowded-base crowded-left crowded-right crowded-altitude crowded-halves crowded-square))

  ;; ------------------------------------------------------------------
  ;; Reusable construction expansion.
  (step "Reusable constructions can expose their internal construction steps."
    (together
      [HA (point -1 0)]
      [HB (point 1 0)]))
  (step "The segment joins the two given points." [helper-base (segment HA HB)])
  (step #:pause 0.7
    (expand [bisector (helper:perpendicular-bisector HA HB)] #:auxiliaries 'hide))
  (step "The line is the perpendicular bisector of the segment."
    (highlight bisector))
  (step #:duration 0.35 #:pause 0 (hide HA HB bisector helper-base))

  ;; ------------------------------------------------------------------
  ;; The eight standard constructions, in three short application plates.
  (step "A midpoint and a perpendicular bisector can be reused as known constructions."
    [LA (point -2 0)] [LB (point 2 0)] [LS (segment LA LB)]
    [LM (c:bisect-segment LA LB)] [Lm (c:perpendicular-bisector LA LB)])
  (step "The midpoint gives two equal parts and the bisector meets them at a right angle."
    [LMticks (marker (midpoint-of LM LS))]
    [LMsquare (marker (perpendicular LS Lm #:at LM))])
  (step #:duration 0.35 #:pause 0 (hide LA LB LS LM Lm LMticks LMsquare))

  (step "A perpendicular can be erected at a point on a line."
    [Ll (line (point -2 0) (point 2 0))] [LP (point -1 0)]
    [Lerect (c:erect-perpendicular Ll LP)])
  (step "A perpendicular can also be dropped from an external point."
    [LQ (point 1 1.6)] [Ldrop (c:drop-perpendicular Ll LQ)]
    [LH (intersection Ll Ldrop)])
  (step "Through the external point, a parallel completes the diagram."
    [Lparallel (c:parallel-through-point Ll LQ)]
    [Larrows (marker (parallel Ll Lparallel))])
  (step #:duration 0.35 #:pause 0
    (hide Ll LP Lerect LQ Ldrop LH Lparallel Larrows))

  (step "The angle bisector divides this source angle into equal parts."
    [CA0 (point -2 1.3)] [CB0 (point -3 -0.5)] [CC0 (point -1.7 -0.5)]
    [Cbase (segment CB0 CC0)] [Cside (segment CB0 CA0)]
    [Cbisection (c:angle-bisector CC0 CB0 CA0)]
    [Cbisector-mark (marker (equal-angle
      (angle CC0 CB0 (end-point Cbisection)) (angle (end-point Cbisection) CB0 CA0)))])
  (step #:duration 0.35 #:pause 0 (hide Cbisection Cbisector-mark))
  (step "Copy the base length onto a new ray."
    [CO0 (point 1 -0.5)] [Ctarget (ray CO0 (point 2.5 -0.5))]
    (expand [CT (c:copy-segment Cbase Ctarget)] #:auxiliaries 'hide))
  (step "Copy the source angle onto that ray."
    [Ccopied (c:copy-angle (angle CC0 CB0 CA0) Ctarget 'left)]
    [Canglemark (marker (equal-angle (angle CC0 CB0 CA0)
                                    (angle CT CO0 (end-point Ccopied))))])
  (step #:pause 1.5 "The same constructions can be combined into larger constructions."
    (highlight Ccopied CT))
  (step #:duration 0.3 #:pause 0
    (hide CA0 CB0 CC0 CO0 CT Cbase Cside Ctarget Ccopied Canglemark))

  ;; First-class transformations preserve the kind of the image geometry.
  (style [tfSp [color-family gold]] [tfSt [color-family gold]]
         [tfSr [color-family gold]] [tfSd [color-family gold]]
         [tfAxis [color muted]])
  (step "Reflect segment AB in the vertical line."
    [tfA (point -3 0.4)] [tfB (point -1.8 1.4)] [tfS (segment tfA tfB)]
    [tfAxis (line (point -0.5 -1.8) (point -0.5 2))] [tfMirror (reflection tfAxis)])
  (step "The image segment has the same length."
    (together [tfAp (transform tfMirror tfA)] [tfBp (reflect tfB tfAxis)])
    [tfSp (transform tfMirror tfS)]
    [tfLength (length-label tfS "a")] [tfLengthP (length-label tfSp "a")])
  (assert (equal-length tfS tfSp))
  (step #:duration 0.3 #:pause 0 (hide tfAxis tfAp tfBp tfSp tfLengthP))
  (step "Translation adds the same vector to both endpoints."
    [tfMove (translation (vector 4 0))]
    (together [tfAt (transform tfMove tfA)] [tfBt (transform tfMove tfB)])
    [tfSt (transform tfMove tfS)] [tfLengthT (length-label tfSt "a")])
  (step #:duration 0.3 #:pause 0 (hide tfAt tfBt tfSt tfLengthT))
  (step "A half-turn about O also preserves the length."
    (show origin) (show-label origin)
    [tfSpin (rotation origin (degrees 180))]
    (together [tfAr (transform tfSpin tfA)] [tfBr (rotate tfB origin (degrees 180))])
    [tfSr (transform tfSpin tfS)] [tfLengthR (length-label tfSr "a")])
  (step #:duration 0.3 #:pause 0 (hide tfAr tfBr tfSr tfLengthR))
  (step "A dilation about O by one half halves the length."
    [tfScale (dilation origin 1/2)]
    (together [tfAd (dilate tfA origin 1/2)] [tfBd (transform tfScale tfB)])
    [tfSd (transform tfScale tfS)] [tfLengthD (length-label tfSd "a/2")])
  (assert (equal-length tfS tfSt tfSr))
  (step #:duration 0.3 #:pause 0
    (hide tfA tfB tfS tfAd tfBd tfSd tfLength tfLengthD origin))

  ;; Labels are named annotations, with their own presentation state.
  (step "Triangle ABC has a base of length 4 cm."
    [slA (point -2 0)] [slB (point 2 0)] [slC (point -0.8 2)]
    [slAB (segment slA slB)] [slBC (segment slB slC)] [slCA (segment slC slA)]
    (hide-label slC)
    [slName (point-label slC "C")] [slBase (segment-label slAB "4 cm")])
  (step "The remaining side lengths are a and b, and the angle at A is α."
    (together [slSideA (length-label slBC "a")] [slSideB (length-label slCA "b")]
              [slAngle (angle-label (angle slB slA slC) "α")]))
  (step "Length and angle labels can also show measured values."
    (hide slSideA slAngle)
    (together [slMeasured (length-label slBC #:precision 2 #:unit "cm")]
              [slDegrees (angle-label (angle slB slA slC) #:precision 1)]))
  (step #:pause 1.5 "These symbols describe the same triangle."
    (hide slMeasured slDegrees) (show slSideA slAngle)))

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
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode theme-mode)
                            #:width width #:height height))

(module+ main
  (run-library-example "gallery"
                        (lambda (aspect theme-mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode theme-mode))))
