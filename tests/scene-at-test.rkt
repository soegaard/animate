#lang racket/base

;;;
;;; SCENE-AT Semantic Color Animation Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define (visual-at scene time id)
    (scene-state-ref (scene-sample scene time) id))

  ;; Semantic colors resolve without drawing-backend dependencies. Named colors
  ;; are case/spacing insensitive and hexadecimal forms preserve exact channels.
  (check-equal? (color-spec->rgba-color "red")
                (rgba-color 255 0 0 1))
  (check-equal? (color-spec->rgba-color "Light Steel Blue")
                (rgba-color 176 196 222 1))
  ;; Use X11/Racket named-color channels rather than CSS channels.
  (check-equal? (color-spec->rgba-color "green")
                (rgba-color 0 255 0 1))
  (check-equal? (color-spec->rgba-color "gray")
                (rgba-color 190 190 190 1))
  (check-equal? (color-spec->rgba-color "purple")
                (rgba-color 160 32 240 1))
  (check-equal? (color-spec->rgba-color "gold")
                (rgba-color 255 215 0 1))
  (check-equal? (color-spec->rgba-color "#0f08")
                (rgba-color 0 255 0 8/15))
  (check-equal? (color-spec->rgba-color "#33669980")
                (rgba-color 51 102 153 128/255))
  (check-equal? (rgba-color-lerp (rgb-color 255 0 0)
                                 (rgb-color 0 0 255)
                                 1/2)
                (rgba-color 255/2 0 255/2 1))
  (check-true (color-spec? "dodgerblue"))
  (check-true (color-spec? (rgb-color 1 2 3)))
  (check-false (color-spec? "definitely-not-a-color"))
  (check-exn exn:fail:contract?
             (lambda () (rgba-color 256 0 0 1)))
  (check-exn exn:fail:contract?
             (lambda () (rgba-color 0 0 0 2)))

  (define dot
    (circle #:id 'dot
            #:radius 1/2
            #:fill "red"
            #:stroke "black"
            #:stroke-width 2))
  (define box
    (rectangle #:id 'box
               #:center (vec2 -3 0)
               #:width 2
               #:height 1
               #:fill "gold"
               #:stroke "navy"))
  (define route
    (line (vec2 -2 -2) (vec2 2 -2)
          #:id 'route
          #:stroke "tomato"))
  (define vector
    (arrow (vec2 -2 2) (vec2 2 2)
           #:id 'vector
           #:stroke "black"))
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -2 2 1)
          #:stroke "dimgray"))
  (define number-line-value
    (number-line (axis-range -2 2 1)
                 #:id 'number-line-value
                 #:stroke "purple"))
  (define marker
    (point-marker #:id 'marker
                  #:fill "royalblue"
                  #:stroke "black"))

  ;; Built-ins expose only the style components they semantically own.
  (for ([visual (in-list (list dot box route marker))])
    (check-true (fill-color-visual? visual)))
  (for ([visual (in-list (list dot box route vector coordinate-axes
                               number-line-value marker))])
    (check-true (stroke-color-visual? visual)))
  (check-equal? (visual-fill-color dot) "red")
  (check-equal? (visual-stroke-color vector) "black")
  (check-equal? (visual-fill-color (visual-with-fill-color dot "blue")) "blue")
  (check-equal? (visual-stroke-color (visual-with-stroke-color dot "gold")) "gold")

  ;; Direct Visual targets validate capability/current color immediately. Symbol
  ;; targets defer scene-specific checks until scene-play resolves the Visual.
  (check-true (fill-color-to-request? (fill-color-to dot "blue")))
  (check-true (stroke-color-to-request? (stroke-color-to dot "white")))
  (check-exn exn:fail:contract?
             (lambda () (fill-color-to dot "not a known color")))
  (define title
    (plain-text "not a fill/stroke Visual" #:id 'title))
  (check-false (fill-color-visual? title))
  (check-false (stroke-color-visual? title))
  (check-exn exn:fail:contract?
             (lambda () (fill-color-to title "red")))
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"stroke-color Visual" (exn-message value))))
   (lambda ()
     (scene-play (scene-add (make-scene) title)
                 (stroke-color-to 'title "red"))))

  ;; Nested scatter markers and callout connector paint are not top-level color
  ;; animation components. Scatter plots remain groups, and connector paint is a
  ;; separate frame-space style rather than the callout content Visual's color.
  (define scatter
    (scatter-plot coordinate-axes
                  (list origin (vec2 1 1))
                  #:id 'color-scatter))
  (check-false (fill-color-visual? scatter))
  (check-false (stroke-color-visual? scatter))
  (check-exn exn:fail:contract?
             (lambda () (fill-color-to scatter "red")))
  (check-exn exn:fail:contract?
             (lambda () (stroke-color-to scatter "red")))
  (define scatter-state
    (scene-current-state
     (scene-add (make-scene) scatter)))
  (check-true (scene-state-has? scatter-state 'color-scatter))
  (check-false (scene-state-has? scatter-state 'color-scatter-marker-0))
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"not present" (exn-message value))))
   (lambda ()
     (scene-play
      (scene-add (make-scene) scatter)
      (fill-color-to 'color-scatter-marker-0 "red"))))
  (define annotation
    (callout (plain-text "annotation" #:id 'annotation)
             dot
             #:camera (make-camera)
             #:at (vec2 2 1)
             #:connector-stroke "red"))
  (check-false (fill-color-visual? annotation))
  (check-false (stroke-color-visual? annotation))
  (check-exn exn:fail:contract?
             (lambda () (stroke-color-to annotation "blue")))

  ;; A style slot may exist while its current value is #f (no paint). AT does not
  ;; make paint presence structural: color animation requires a real source color.
  (define unfilled
    (circle #:id 'unfilled #:fill #f #:stroke "black"))
  (check-true (fill-color-visual? unfilled))
  (check-exn exn:fail?
             (lambda () (fill-color-to unfilled "red")))
  (check-exn exn:fail?
             (lambda ()
               (scene-play (scene-add (make-scene) unfilled)
                           (fill-color-to 'unfilled "red"))))

  ;; Interior samples are renderer-independent RGBA values, but exact boundaries
  ;; preserve the caller's original textual endpoints.
  (define fill-scene
    (scene-play
     (scene-add (make-scene) dot)
     (fill-color-to dot "blue")
     #:duration 4))
  (check-equal? (visual-fill-color (visual-at fill-scene 0 'dot)) "red")
  (check-equal? (visual-fill-color (visual-at fill-scene 2 'dot))
                (rgba-color 255/2 0 255/2 1))
  (check-equal? (visual-fill-color (visual-at fill-scene 4 'dot)) "blue")

  (define alpha-scene
    (scene-play
     (scene-add
      (make-scene)
      (circle #:id 'alpha #:fill (rgba-color 255 0 0 1) #:stroke #f))
     (fill-color-to 'alpha "transparent")
     #:duration 2))
  (check-equal? (visual-fill-color (visual-at alpha-scene 1 'alpha))
                (rgba-color 255/2 0 0 1/2))
  (check-equal? (visual-fill-color (visual-at alpha-scene 2 'alpha))
                "transparent")

  ;; Fill, stroke, width, opacity, and affine motion are independent components.
  (define parallel-style-and-motion
    (scene-play
     (scene-add (make-scene) dot)
     (animation-group
      (move-to dot (vec2 4 0))
      (fade-to dot 1/2)
      (stroke-width-to dot 10)
      (fill-color-to dot "blue")
      (stroke-color-to dot "gold"))
     #:duration 4))
  (define parallel-mid
    (visual-at parallel-style-and-motion 2 'dot))
  (check-equal? (visual-position parallel-mid) (vec2 2 0))
  (check-equal? (visual-opacity parallel-mid) 3/4)
  (check-equal? (visual-stroke-width parallel-mid) 6)
  (check-equal? (visual-fill-color parallel-mid)
                (rgba-color 255/2 0 255/2 1))
  (check-equal? (visual-stroke-color parallel-mid)
                (rgba-color 255/2 215/2 0 1))

  ;; Same-component overlaps conflict. Fill and stroke remain independent.
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"fill-color" (exn-message value))))
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (animation-group
       (fill-color-to dot "blue")
       (fill-color-to dot "green"))
      #:duration 2)))
  (check-not-exn
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (animation-group
       (fill-color-to dot "blue")
       (stroke-color-to dot "green"))
      #:duration 2)))

  ;; Sequential/timed color changes compile from the exact prior style endpoint.
  (define sequential-fills
    (scene-play
     (scene-add (make-scene) dot)
     (succession
      (fill-color-to dot "white")
      (fill-color-to dot "blue"))
     #:duration 4))
  (check-equal? (visual-fill-color (visual-at sequential-fills 2 'dot)) "white")
  (check-equal? (visual-fill-color (visual-at sequential-fills 3 'dot))
                (rgba-color 255/2 255/2 255 1))
  (check-equal? (visual-fill-color (visual-at sequential-fills 4 'dot)) "blue")

  (define locally-timed-stroke
    (scene-play
     (scene-add (make-scene) vector)
     (timed (stroke-color-to vector "red") #:start 1 #:duration 2)
     #:duration 4))
  (check-equal? (visual-stroke-color (visual-at locally-timed-stroke 1/2 'vector))
                "black")
  (check-equal? (visual-stroke-color (visual-at locally-timed-stroke 2 'vector))
                (rgba-color 255/2 0 0 1))
  (check-equal? (visual-stroke-color (visual-at locally-timed-stroke 3 'vector))
                "red")

  ;; Structural introduction composes with style animation at the same boundary.
  (define introduced
    (circle #:id 'introduced #:fill "red" #:stroke "black"))
  (define introduction-scene
    (scene-play
     (make-scene)
     (animation-group
      (fade-in introduced)
      (fill-color-to 'introduced "blue")
      (stroke-color-to 'introduced "gold"))
     #:duration 2))
  (define introduced-mid
    (visual-at introduction-scene 1 'introduced))
  (check-equal? (visual-opacity introduced-mid) 1/2)
  (check-equal? (visual-fill-color introduced-mid)
                (rgba-color 255/2 0 255/2 1))
  (check-equal? (visual-stroke-color introduced-mid)
                (rgba-color 255/2 215/2 0 1))

  ;; Third-party semantic Visuals can opt into either protocol independently.
  (struct color-marker (id position fill stroke)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual) (color-marker-id visual))
     (define (visual-position visual) (color-marker-position visual))
     (define (visual-with-position visual position)
       (struct-copy color-marker visual [position position]))]
    #:methods gen:fill-color-visual
    [(define (visual-fill-color visual) (color-marker-fill visual))
     (define (visual-with-fill-color visual color)
       (struct-copy color-marker visual [fill color]))]
    #:methods gen:stroke-color-visual
    [(define (visual-stroke-color visual) (color-marker-stroke visual))
     (define (visual-with-stroke-color visual color)
       (struct-copy color-marker visual [stroke color]))])

  (define custom (color-marker 'custom origin "red" "black"))
  (define custom-scene
    (scene-play
     (scene-add (make-scene) custom)
     (animation-group
      (fill-color-to custom "blue")
      (stroke-color-to custom "white"))
     #:duration 2))
  (check-equal? (visual-fill-color (visual-at custom-scene 1 'custom))
                (rgba-color 255/2 0 255/2 1))
  (check-equal? (visual-stroke-color (visual-at custom-scene 2 'custom)) "white")

  (struct invalid-fill-marker (id position fill)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual) (invalid-fill-marker-id visual))
     (define (visual-position visual) (invalid-fill-marker-position visual))
     (define (visual-with-position visual position)
       (struct-copy invalid-fill-marker visual [position position]))]
    #:methods gen:fill-color-visual
    [(define (visual-fill-color visual) (invalid-fill-marker-fill visual))
     (define (visual-with-fill-color visual _color) visual)])

  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"must install the requested fill color"
                         (exn-message value))))
   (lambda ()
     (define invalid (invalid-fill-marker 'invalid origin "red"))
     (scene-play (scene-add (make-scene) invalid)
                 (fill-color-to invalid "blue")
                 #:duration 2)))

  ;; Endpoint validation is representation-exact for semantic RGBA values too.
  ;; A custom setter may not silently turn an exact requested channel into an
  ;; inexact-but-numerically-equal value. Test fill and stroke separately because
  ;; they have distinct protocol replacement paths.
  (define (coerce-red-channel color)
    (if (rgba-color? color)
        (rgba-color (exact->inexact (rgba-color-red color))
                    (rgba-color-green color)
                    (rgba-color-blue color)
                    (rgba-color-alpha color))
        color))

  (struct coercing-color-marker (id position fill stroke)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual) (coercing-color-marker-id visual))
     (define (visual-position visual) (coercing-color-marker-position visual))
     (define (visual-with-position visual position)
       (struct-copy coercing-color-marker visual [position position]))]
    #:methods gen:fill-color-visual
    [(define (visual-fill-color visual) (coercing-color-marker-fill visual))
     (define (visual-with-fill-color visual color)
       (struct-copy coercing-color-marker visual
                    [fill (coerce-red-channel color)]))]
    #:methods gen:stroke-color-visual
    [(define (visual-stroke-color visual) (coercing-color-marker-stroke visual))
     (define (visual-with-stroke-color visual color)
       (struct-copy coercing-color-marker visual
                    [stroke (coerce-red-channel color)]))])

  (define coercing
    (coercing-color-marker 'coercing origin "red" "black"))
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"must install the requested fill color"
                         (exn-message value))))
   (lambda ()
     (scene-play
      (scene-add (make-scene) coercing)
      (fill-color-to coercing (rgba-color 1 2 3 1))
      #:duration 1)))
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"must install the requested stroke color"
                         (exn-message value))))
   (lambda ()
     (scene-play
      (scene-add (make-scene) coercing)
      (stroke-color-to coercing (rgba-color 1 2 3 1))
      #:duration 1))))
