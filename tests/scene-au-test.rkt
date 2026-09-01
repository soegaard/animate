#lang racket/base

;;;
;;; SCENE-AU Unified Style Transition Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define (visual-at scene time id)
    (scene-state-ref (scene-sample scene time) id))

  (define dot
    (circle #:id 'dot
            #:radius 1
            #:fill "red"
            #:stroke "black"
            #:stroke-width 2
            #:opacity 1))

  ;; style-to is a first-class composition node and rejects a vacuous request.
  (check-true
   (style-to-animation-request?
    (style-to dot #:fill "blue")))
  (check-exn exn:fail:contract?
             (lambda () (style-to dot)))

  ;; All four style components share one interval while retaining the primitive
  ;; AS/AT interpolation and exact endpoint semantics.
  (define full-style-scene
    (scene-play
     (scene-add (make-scene) dot)
     (style-to dot
               #:fill "blue"
               #:stroke "gold"
               #:stroke-width 10
               #:opacity 1/2)
     #:duration 4))
  (define full-start (visual-at full-style-scene 0 'dot))
  (define full-mid (visual-at full-style-scene 2 'dot))
  (define full-end (visual-at full-style-scene 4 'dot))
  (check-equal? (visual-fill-color full-start) "red")
  (check-equal? (visual-stroke-color full-start) "black")
  (check-equal? (visual-stroke-width full-start) 2)
  (check-equal? (visual-opacity full-start) 1)
  (check-equal? (visual-fill-color full-mid)
                (rgba-color 255/2 0 255/2 1))
  (check-equal? (visual-stroke-color full-mid)
                (rgba-color 255/2 215/2 0 1))
  (check-equal? (visual-stroke-width full-mid) 6)
  (check-equal? (visual-opacity full-mid) 3/4)
  (check-equal? (visual-fill-color full-end) "blue")
  (check-equal? (visual-stroke-color full-end) "gold")
  (check-equal? (visual-stroke-width full-end) 10)
  (check-equal? (visual-opacity full-end) 1/2)

  ;; AU is composition syntax only: it must sample identically to the primitive
  ;; requests it expands to, including inherited non-linear easing.
  (define (square progress)
    (* progress progress))
  (define primitive-style-scene
    (scene-play
     (scene-add (make-scene) dot)
     (fill-color-to dot "blue")
     (stroke-color-to dot "gold")
     (stroke-width-to dot 10)
     (fade-to dot 1/2)
     #:duration 4
     #:easing square))
  (define unified-style-scene
    (scene-play
     (scene-add (make-scene) dot)
     (style-to dot
               #:fill "blue"
               #:stroke "gold"
               #:stroke-width 10
               #:opacity 1/2)
     #:duration 4
     #:easing square))
  (for ([time (in-list '(0 1 2 3 4))])
    (check-equal? (visual-at unified-style-scene time 'dot)
                  (visual-at primitive-style-scene time 'dot)))

  ;; Any nonempty subset is valid. Direct Visual targets reuse the primitive
  ;; capability validation; symbolic targets defer it until scene compilation.
  (define vector
    (arrow (vec2 -2 0) (vec2 2 0)
           #:id 'vector
           #:stroke "black"
           #:stroke-width 3))
  (check-not-exn
   (lambda ()
     (style-to vector #:stroke "purple" #:stroke-width 7 #:opacity 1/2)))
  (check-exn exn:fail:contract?
             (lambda () (style-to vector #:fill "red")))
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"fill-color Visual" (exn-message value))))
   (lambda ()
     (scene-play
      (scene-add (make-scene) vector)
      (style-to 'vector #:fill "red"))))

  ;; A target need implement only the protocols for properties actually supplied.
  ;; Explicit #f is the documented omitted-property sentinel.
  (define title
    (plain-text "style" #:id 'title #:opacity 1))
  (check-not-exn
   (lambda () (style-to title #:opacity 1/2)))
  (check-not-exn
   (lambda () (style-to dot #:fill #f #:opacity 1/2)))
  (define title-style-scene
    (scene-play
     (scene-add (make-scene) title)
     (style-to title #:opacity 1/2)
     #:duration 2))
  (check-equal? (visual-opacity (visual-at title-style-scene 1 'title)) 3/4)

  ;; Unified fill/stroke syntax inherits AT's missing-paint rule rather than
  ;; interpreting #f source paint as transparent.
  (define unfilled
    (circle #:id 'unfilled #:fill #f #:stroke "black"))
  (check-exn exn:fail?
             (lambda () (style-to unfilled #:fill "red")))

  ;; Unified style is not one coarse conflict component. It can overlap affine
  ;; motion, and an omitted opacity can overlap a separate fade-to.
  (define independent-scene
    (scene-play
     (scene-add (make-scene) dot)
     (animation-group
      (style-to dot #:fill "blue" #:stroke-width 10)
      (move-to dot (vec2 4 0))
      (fade-to dot 1/2))
     #:duration 4))
  (define independent-mid (visual-at independent-scene 2 'dot))
  (check-equal? (visual-position independent-mid) (vec2 2 0))
  (check-equal? (visual-opacity independent-mid) 3/4)
  (check-equal? (visual-stroke-width independent-mid) 6)
  (check-equal? (visual-fill-color independent-mid)
                (rgba-color 255/2 0 255/2 1))

  ;; Expansion happens before conflict checking, so primitive and unified
  ;; requests collide only on properties actually present in style-to.
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"fill-color" (exn-message value))))
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (animation-group
       (style-to dot #:fill "blue" #:stroke-width 8)
       (fill-color-to dot "green"))
      #:duration 2)))
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"opacity" (exn-message value))))
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (animation-group
       (style-to dot #:opacity 1/2)
       (fade-to dot 1/4))
      #:duration 2)))
  (check-not-exn
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (animation-group
       (style-to dot #:fill "blue")
       (stroke-color-to dot "gold")
       (stroke-width-to dot 8)
       (fade-to dot 1/2))
      #:duration 2)))

  ;; A style transition behaves as one composition child for succession timing,
  ;; and later transitions compile from exact prior style endpoints.
  (define successive-style-scene
    (scene-play
     (scene-add (make-scene) dot)
     (succession
      (style-to dot #:stroke-width 6 #:fill "blue")
      (style-to dot #:stroke-width 10 #:fill "green"))
     #:duration 4))
  (define successive-boundary
    (visual-at successive-style-scene 2 'dot))
  (define successive-mid-second
    (visual-at successive-style-scene 3 'dot))
  (check-equal? (visual-stroke-width successive-boundary) 6)
  (check-equal? (visual-fill-color successive-boundary) "blue")
  (check-equal? (visual-stroke-width successive-mid-second) 8)
  (check-equal? (visual-fill-color successive-mid-second)
                (rgba-color 0 255/2 255/2 1))
  (check-equal? (visual-stroke-width
                 (visual-at successive-style-scene 4 'dot))
                10)
  (check-equal? (visual-fill-color
                 (visual-at successive-style-scene 4 'dot))
                "green")

  ;; style-to is timable and may be nested in the other composition forms.
  (define timed-style-scene
    (scene-play
     (scene-add (make-scene) dot)
     (timed
      (style-to dot #:stroke-width 10 #:opacity 1/2)
      #:start 1
      #:duration 2)
     #:duration 4))
  (check-equal? (visual-stroke-width (visual-at timed-style-scene 1 'dot)) 2)
  (check-equal? (visual-stroke-width (visual-at timed-style-scene 2 'dot)) 6)
  (check-equal? (visual-stroke-width (visual-at timed-style-scene 3 'dot)) 10)
  (check-equal? (visual-stroke-width (visual-at timed-style-scene 4 'dot)) 10)
  (check-equal? (visual-opacity (visual-at timed-style-scene 2 'dot)) 3/4)

  (define lagged-style-scene
    (scene-play
     (scene-add
      (make-scene)
      dot
      (circle #:id 'other
              #:center (vec2 0 -3)
              #:fill "red"
              #:stroke "black"
              #:stroke-width 2))
     (lagged-start
      (style-to 'dot #:fill "blue")
      (style-to 'other #:fill "green")
      #:lag-ratio 1)
     #:duration 4))
  (check-equal? (visual-fill-color (visual-at lagged-style-scene 2 'dot))
                "blue")
  (check-equal? (visual-fill-color (visual-at lagged-style-scene 2 'other))
                "red")
  (check-equal? (visual-fill-color (visual-at lagged-style-scene 4 'other))
                "green")

  ;; Structural introduction composes normally because style-to expands to
  ;; leaves compiled after the exact fade-in boundary.
  (define introduced
    (circle #:id 'introduced
            #:fill "red"
            #:stroke "black"
            #:stroke-width 2))
  (define introduction-scene
    (scene-play
     (make-scene)
     (succession
      (fade-in introduced)
      (style-to 'introduced
                #:fill "blue"
                #:stroke-width 8
                #:opacity 1/2))
     #:duration 4))
  (check-equal? (visual-fill-color
                 (visual-at introduction-scene 2 'introduced))
                "red")
  (check-equal? (visual-opacity
                 (visual-at introduction-scene 2 'introduced))
                1)
  (check-equal? (visual-fill-color
                 (visual-at introduction-scene 4 'introduced))
                "blue")
  (check-equal? (visual-stroke-width
                 (visual-at introduction-scene 4 'introduced))
                8)
  (check-equal? (visual-opacity
                 (visual-at introduction-scene 4 'introduced))
                1/2))
