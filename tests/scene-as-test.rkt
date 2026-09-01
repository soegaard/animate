#lang racket/base

;;;
;;; SCENE-AS Stroke-Width Animation Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define dot
    (circle #:id 'dot
            #:radius 1/2
            #:center origin
            #:fill #f
            #:stroke "royalblue"
            #:stroke-width 2))

  (define box
    (rectangle #:id 'box
               #:width 2
               #:height 1
               #:center (vec2 -3 0)
               #:fill #f
               #:stroke "seagreen"
               #:stroke-width 3))

  (define route
    (line (vec2 -2 -2)
          (vec2 2 -2)
          #:id 'route
          #:stroke "tomato"
          #:stroke-width 4))

  (define vector
    (arrow (vec2 -2 2)
           (vec2 2 2)
           #:id 'vector
           #:stroke "black"
           #:stroke-width 5))

  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -2 2 1)
          #:stroke-width 6))

  (define number-line-value
    (number-line (axis-range -2 2 1)
                 #:id 'number-line-value
                 #:stroke-width 7))

  (define marker
    (point-marker #:id 'marker
                  #:stroke-width 8))

  (define (visual-at scene time id)
    (scene-state-ref (scene-sample scene time) id))

  ;; Stroke width is a semantic Visual capability shared by the built-ins that
  ;; expose cosmetic line width. The generic getter agrees with concrete accessors.
  (for ([visual (in-list (list dot
                               box
                               route
                               vector
                               coordinate-axes
                               number-line-value
                               marker))]
        [expected (in-list '(2 3 4 5 6 7 8))])
    (check-true (stroke-width-visual? visual))
    (check-true (stroke-width? (visual-stroke-width visual)))
    (check-equal? (visual-stroke-width visual) expected))

  (check-false (stroke-width? -1))
  (check-false (stroke-width? +inf.0))
  (check-false (stroke-width? +nan.0))
  (check-true (stroke-width? 0))
  ;; The semantic domain is renderer-independent; the default Pict backend has
  ;; its own narrower racket/draw pen-width range.
  (check-true (stroke-width? 300))
  (check-equal? (visual-id (visual-with-stroke-width dot 9)) 'dot)
  (check-equal? (visual-stroke-width (visual-with-stroke-width dot 9)) 9)
  (check-exn exn:fail:contract?
             (lambda ()
               (visual-with-stroke-width dot -1)))

  ;; Public request construction validates direct Visual targets immediately,
  ;; while symbol targets are validated when scene-play resolves the scene value.
  (check-true (stroke-width-to-request? (stroke-width-to dot 10)))
  (check-true (stroke-width-to-request? (stroke-width-to 'dot 10)))
  (check-exn exn:fail:contract?
             (lambda ()
               (stroke-width-to dot -1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (stroke-width-to dot +inf.0)))
  (define title
    (plain-text "not stroked" #:id 'title))
  (check-false (stroke-width-visual? title))
  (check-exn exn:fail:contract?
             (lambda ()
               (stroke-width-to title 3)))
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"stroke-width Visual" (exn-message value))))
   (lambda ()
     (scene-play (scene-add (make-scene) title)
                 (stroke-width-to 'title 3))))

  ;; Plot curves/areas that are themselves path Visuals inherit the protocol, but
  ;; scatter-plot returns a top-level group whose marker children are not scene
  ;; targets. Callout connector width is likewise a separate frame-space style.
  (define scatter-axes
    (axes #:id 'scatter-axes
          #:x-range (axis-range -1 1 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 2
          #:y-length 2))
  (define scatter
    (scatter-plot scatter-axes
                  (list origin (vec2 1 1))
                  #:id 'scatter))
  (check-false (stroke-width-visual? scatter))
  (check-exn exn:fail:contract?
             (lambda ()
               (stroke-width-to scatter 5)))
  (define scatter-state
    (scene-current-state
     (scene-add (make-scene) scatter)))
  (check-true (scene-state-has? scatter-state 'scatter))
  (check-false (scene-state-has? scatter-state 'scatter-marker-0))
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"not present" (exn-message value))))
   (lambda ()
     (scene-play
      (scene-add (make-scene) scatter)
      (stroke-width-to 'scatter-marker-0 5))))
  (define annotation
    (callout (plain-text "annotation" #:id 'annotation)
             dot
             #:camera (make-camera)
             #:at (vec2 2 1)
             #:connector-width 3))
  (check-false (stroke-width-visual? annotation))
  (check-exn exn:fail:contract?
             (lambda ()
               (stroke-width-to annotation 5)))

  ;; The request interpolates linearly and preserves the exact requested endpoint.
  ;; The inexact starting width makes the endpoint check catch accidental 7.0 output.
  (define exact-end-dot
    (circle #:id 'exact-end-dot
            #:radius 1/2
            #:fill #f
            #:stroke-width 2.0))
  (define width-scene
    (scene-play
     (scene-add (make-scene) exact-end-dot)
     (stroke-width-to exact-end-dot 7)
     #:duration 4))
  (check-equal? (visual-stroke-width (visual-at width-scene 0 'exact-end-dot))
                2.0)
  (check-equal? (visual-stroke-width (visual-at width-scene 2 'exact-end-dot))
                4.5)
  (check-equal? (visual-stroke-width (visual-at width-scene 4 'exact-end-dot))
                7)
  (check-true (exact? (visual-stroke-width (visual-at width-scene 4 'exact-end-dot))))

  ;; Zero is a valid endpoint and leaves the stroke semantically present with zero
  ;; cosmetic width rather than treating it as a structural removal.
  (define zero-width-scene
    (scene-play
     (scene-add (make-scene) dot)
     (stroke-width-to dot 0)
     #:duration 2))
  (check-equal? (visual-stroke-width (visual-at zero-width-scene 1 'dot)) 1)
  (check-equal? (visual-stroke-width (visual-at zero-width-scene 2 'dot)) 0)
  (check-true (scene-state-has? (scene-sample zero-width-scene 2) 'dot))

  ;; Stroke width is independent from affine and opacity components, so compatible
  ;; changes to one Visual can run in parallel.
  (define parallel-style-and-motion
    (scene-play
     (scene-add (make-scene) dot)
     (animation-group
      (move-to dot (vec2 4 0))
      (rotate-by dot 2)
      (fade-to dot 1/2)
      (stroke-width-to dot 10))
     #:duration 4))
  (define parallel-mid
    (visual-at parallel-style-and-motion 2 'dot))
  (check-equal? (visual-position parallel-mid) (vec2 2 0))
  (check-equal? (visual-rotation parallel-mid) 1)
  (check-equal? (visual-opacity parallel-mid) 3/4)
  (check-equal? (visual-stroke-width parallel-mid) 6)

  ;; Overlapping updates to the same style component conflict, while touching
  ;; sequential updates compile from the exact prior width endpoint.
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"stroke-width" (exn-message value))))
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (animation-group
       (stroke-width-to dot 6)
       (stroke-width-to dot 10))
      #:duration 2)))

  (define sequential-widths
    (scene-play
     (scene-add (make-scene) dot)
     (succession
      (stroke-width-to dot 6)
      (stroke-width-to dot 10))
     #:duration 4))
  (check-equal? (visual-stroke-width (visual-at sequential-widths 1 'dot)) 4)
  (check-equal? (visual-stroke-width (visual-at sequential-widths 2 'dot)) 6)
  (check-equal? (visual-stroke-width (visual-at sequential-widths 3 'dot)) 8)
  (check-equal? (visual-stroke-width (visual-at sequential-widths 4 'dot)) 10)

  ;; AN-AR local timing works without any special style scheduler path.
  (define locally-timed-width
    (scene-play
     (scene-add (make-scene) dot)
     (timed (stroke-width-to dot 10)
            #:start 1
            #:duration 2)
     #:duration 4))
  (check-equal? (visual-stroke-width (visual-at locally-timed-width 1/2 'dot)) 2)
  (check-equal? (visual-stroke-width (visual-at locally-timed-width 2 'dot)) 6)
  (check-equal? (visual-stroke-width (visual-at locally-timed-width 3 'dot)) 10)
  (check-equal? (visual-stroke-width (visual-at locally-timed-width 4 'dot)) 10)

  ;; A structural introduction can animate opacity and stroke width together. The
  ;; introduced Visual becomes available to the width leaf at the same boundary.
  (define introduced
    (circle #:id 'introduced
            #:radius 1/2
            #:fill #f
            #:stroke "purple"
            #:stroke-width 2))
  (define introduction-scene
    (scene-play
     (make-scene)
     (animation-group
      (fade-in introduced)
      (stroke-width-to 'introduced 8))
     #:duration 2))
  (define introduced-mid
    (visual-at introduction-scene 1 'introduced))
  (check-equal? (visual-opacity introduced-mid) 1/2)
  (check-equal? (visual-stroke-width introduced-mid) 5)
  (check-equal? (visual-stroke-width
                 (visual-at introduction-scene 2 'introduced))
                8)

  ;; Third-party Visuals can opt in without implementing affine transforms or
  ;; opacity. The engine also validates custom protocol endpoint behavior.
  (struct width-marker (id position stroke-width)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual)
       (width-marker-id visual))
     (define (visual-position visual)
       (width-marker-position visual))
     (define (visual-with-position visual position)
       (struct-copy width-marker visual [position position]))]
    #:methods gen:stroke-width-visual
    [(define (visual-stroke-width visual)
       (width-marker-stroke-width visual))
     (define (visual-with-stroke-width visual stroke-width)
       (struct-copy width-marker visual [stroke-width stroke-width]))])

  (define custom
    (width-marker 'custom origin 3))
  (check-true (visual? custom))
  (check-true (stroke-width-visual? custom))
  (check-false (affine-visual? custom))
  (define custom-scene
    (scene-play
     (scene-add (make-scene) custom)
     (stroke-width-to custom 9)
     #:duration 2))
  (check-equal? (visual-stroke-width (visual-at custom-scene 1 'custom)) 6)
  (check-equal? (visual-stroke-width (visual-at custom-scene 2 'custom)) 9)

  (struct invalid-width-marker (id position stroke-width)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual)
       (invalid-width-marker-id visual))
     (define (visual-position visual)
       (invalid-width-marker-position visual))
     (define (visual-with-position visual position)
       (struct-copy invalid-width-marker visual [position position]))]
    #:methods gen:stroke-width-visual
    [(define (visual-stroke-width visual)
       (invalid-width-marker-stroke-width visual))
     (define (visual-with-stroke-width visual _stroke-width)
       visual)])

  ;; Exact endpoint validation includes exactness. A third-party setter may not
  ;; silently coerce an exact requested endpoint to an inexact equal value.
  (struct coercing-width-marker (id position stroke-width)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual)
       (coercing-width-marker-id visual))
     (define (visual-position visual)
       (coercing-width-marker-position visual))
     (define (visual-with-position visual position)
       (struct-copy coercing-width-marker visual [position position]))]
    #:methods gen:stroke-width-visual
    [(define (visual-stroke-width visual)
       (coercing-width-marker-stroke-width visual))
     (define (visual-with-stroke-width visual stroke-width)
       (struct-copy coercing-width-marker
                    visual
                    [stroke-width (exact->inexact stroke-width)]))])

  (define coercing-custom
    (coercing-width-marker 'coercing-custom origin 3.0))
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"must install the requested stroke width exactly"
                         (exn-message value))))
   (lambda ()
     (scene-play
      (scene-add (make-scene) coercing-custom)
      (stroke-width-to coercing-custom 9)
      #:duration 2)))

  (define invalid-custom
    (invalid-width-marker 'invalid-custom origin 3))
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"must install the requested stroke width"
                         (exn-message value))))
   (lambda ()
     (scene-play
      (scene-add (make-scene) invalid-custom)
      (stroke-width-to invalid-custom 9)
      #:duration 2))))
