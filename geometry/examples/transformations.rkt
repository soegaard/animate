#lang racket/base

;; Image geometry is constructed, not moved by an animation updater.
(require "../core.rkt" "private/library-example.rkt")
(provide transformations-demo example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))
(construction transformations-demo
  (given [O (point 0 0)])
  (initially (hide O))
  (layout
    (label-text Ap "A′") (label-text Bp "B′") (label-text Cp "C′")
    (label-text At "A′") (label-text Bt "B′") (label-text Ct "C′")
    (label-text U "A") (label-text V "B") (label-text W "C")
    (label-text Ur "A′") (label-text Vr "B′") (label-text Wr "C′")
    (label-text D "A") (label-text E "B") (label-text F "C")
    (label-text Dd "A′") (label-text Ed "B′") (label-text Fd "C′")
    (label-side A 'below-left) (label-side B 'below) (label-side C 'above)
    (label-offset W (point 0.55 0.1))
    ;; Side labels on triangles stay outside, opposite the third vertex.
    (label-outside-of a C) (label-outside-of ap Cp) (label-outside-of at Ct)
    (label-outside-of d F) (label-outside-of dd Fd)
    (label-position d 0.5) (label-position dd 0.5)
    (label-side radius-r 'above) (label-position radius-r 0.48)
    (label-side radius-2r 'below) (label-position radius-2r 0.72)
    (label-side Ap 'below-right) (label-side Bp 'below) (label-side Cp 'above))
  (style
    [axis [color muted]]
    [ApBp [color-family gold]] [BpCp [color-family gold]] [CpAp [color-family gold]]
    [AtBt [color-family gold]] [BtCt [color-family gold]] [CtAt [color-family gold]]
    [UrVr [color-family gold]] [VrWr [color-family gold]] [WrUr [color-family gold]]
    [DdEd [color-family gold]] [EdFd [color-family gold]] [FdDd [color-family gold]]
    [AAp [color muted]] [AAt [color muted]] [BBt [color muted]] [CCt [color muted]]
    [ODd [color muted]] [OD [color-family gold]])
  (step "Reflect triangle ABC in the vertical line."
    [A (point -3 -0.8)] [B (point -1 -0.8)] [C (point -2.5 0.2)]
    [AB (segment A B)] [BC (segment B C)] [CA (segment C A)]
    [axis (line (point 0 -2) (point 0 2))]
    [T (reflection axis)])
  (step "Each image point lies the same distance on the opposite side."
    (together [Ap (transform T A)] [Bp (reflect B axis)] [Cp (transform T C)])
    (together [ApBp (transform T AB)] [BpCp (transform T BC)] [CpAp (transform T CA)])
    [AAp (segment A Ap)] [M (intersection AAp axis)]
    [reflection-halves (marker (midpoint-of M AAp))]
    [reflection-right-angle (marker (perpendicular AAp axis #:at M))]
    (hide-label M))
  (step #:pause 1.5 "Reflection preserves lengths and angle measures."
    [a (length-label AB "a")] [ap (length-label ApBp "a")])
  (assert (equal-length AB ApBp) (equal-angle (angle B A C) (angle Bp Ap Cp))
          (midpoint-of M AAp) (perpendicular AAp axis #:at M))
  (step #:duration 0.3 #:pause 0
    (hide axis Ap Bp Cp ApBp BpCp CpAp AAp M reflection-halves reflection-right-angle a ap))
  (step "Translate triangle ABC by the vector (4, 0)."
    [v (vector 4 0)] [S (translation v)]
    (together [At (translate A v)] [Bt (transform S B)] [Ct (transform S C)])
    (together [AtBt (transform S AB)] [BtCt (transform S BC)] [CtAt (transform S CA)]))
  (step #:pause 1.5 "Every point receives the same displacement."
    (together [AAt (segment A At)] [BBt (segment B Bt)] [CCt (segment C Ct)])
    [shift-ticks (marker (equal-length AAt BBt CCt))]
    [at (length-label AtBt "a")] (show a))
  (assert (equal-length AB AtBt) (equal-length AAt BBt CCt))
  (step #:duration 0.3 #:pause 0
    (hide A B C AB BC CA At Bt Ct AtBt BtCt CtAt AAt BBt CCt shift-ticks a at))
  (step "Rotate this triangle 90 degrees counterclockwise about O."
    (show O)
    [U (point 0.5 -1.7)] [V (point 2 -1.7)] [W (point 0.8 -1)]
    [UV (segment U V)] [VW (segment V W)] [WU (segment W U)]
    [R (rotation O (degrees 90))])
  (step "The distances from O and all side lengths are preserved."
    (together [Ur (rotate U O (degrees 90))] [Vr (transform R V)] [Wr (transform R W)])
    (together [UrVr (transform R UV)] [VrWr (transform R VW)] [WrUr (transform R WU)])
    [OU (segment O U)] [OUr (segment O Ur)])
  (step #:pause 1.5 "The angle AOA′ is 90 degrees."
    [turn (angle-label (angle U O Ur))])
  (assert (equal-length UV UrVr) (equal-length OU OUr))
  (step #:duration 0.3 #:pause 0 (hide U V W UV VW WU Ur Vr Wr UrVr VrWr WrUr OU OUr turn))
  (step "Dilate triangle ABC about O with scale factor 2."
    [D (point 1 -0.4)] [E (point 2 -0.4)] [F (point 1.12 0.2)]
    [DE (segment D E)] [EF (segment E F)] [FD (segment F D)]
    [H (dilation O 2)])
  (step "Each image point is twice as far from O."
    (together [Dd (dilate D O 2)] [Ed (transform H E)] [Fd (transform H F)])
    (together [DdEd (transform H DE)] [EdFd (transform H EF)] [FdDd (transform H FD)])
    [ODd (segment O Dd)] [OD (segment O D)]
    [radius-r (length-label OD "r")] [radius-2r (length-label ODd "2r")])
  (step #:pause 1.5 "Side lengths double; angle measures stay the same."
    (hide OD ODd radius-r radius-2r)
    [d (length-label DE #:precision 1)] [dd (length-label DdEd #:precision 1)])
  (assert (= (distance O Dd) (* 2 (distance O D)))
          (= (length DdEd) (* 2 (length DE)))
          (equal-angle (angle E D F) (angle Ed Dd Fd)))
  ;; A composite and its inverse are reusable nondrawable values.
  (step #:read-delay 0 #:pause 0
    [composite (compose-transform S T)]
    [inverse (inverse-transform composite)])
  (assert (equal-length (transform inverse (transform composite AB)) AB))
  (result Dd Ed Fd H composite inverse))
(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline transformations-demo #:aspect aspect #:theme (make-library-theme mode)
    #:view (make-geometry-view #:center (point 0 0.1) #:world-width 10.8 #:aspect aspect #:margin 0.08)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode) #:width width #:height height))
(module+ main
  (run-library-example "transformations" (lambda (aspect mode) (make-demo-timeline #:aspect aspect #:theme-mode mode))))
