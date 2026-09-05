#lang racket/base

;;;
;;; Animated Write
;;;

;; Writes a semantic SVG and a tagged TeX formula.  Both endpoints retain their
;; usual renderers; only the animation interval uses expanded vector paths.

(require racket/runtime-path
         animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define-runtime-path assets-directory "assets")

(define (make-demo-scene)
  (define rocket
    (svg->visual
     (build-path assets-directory "roadmap-rocket.svg")
     #:id 'rocket-drawing
     #:center (vec2 -3/2 -1/4)
     #:scale 3/5))
  (define equation
    (tagged-formula
     #:id 'equation
     #:center (vec2 2 -1/4)
     #:font-size 1/2
     (formula-fragment 'left "c^2")
     (formula-fragment 'equals "=")
     (formula-fragment 'right-a "a^2")
     (formula-fragment 'plus "+")
     (formula-fragment 'right-b "b^2")))
  (define title
    (plain-text "SCENE-BU: Manim-style animated write"
                #:id 'title
                #:center (vec2 0 3)
                #:font-size 2/5
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define svg-label
    (plain-text "semantic SVG"
                #:id 'svg-label
                #:center (vec2 -3/2 -13/5)
                #:font-size 1/3
                #:font-family 'swiss
                #:color "darkslategray"))
  (define formula-label
    (plain-text "tagged TeX"
                #:id 'formula-label
                #:center (vec2 2 -13/5)
                #:font-size 1/3
                #:font-family 'swiss
                #:color "darkslategray"))
  (define start
    (scene-add (make-scene) title svg-label formula-label))
  (define svg-written
    (scene-play start
                (write-in rocket #:order 'document)
                #:duration 2))
  (define formula-written
    (scene-play svg-written
                (write-in equation #:order 'left-to-right)
                #:duration 2))
  ;; `unwrite` reverses both glyph order and each glyph's path traversal.
  ;; The equation's original tagged-formula Visual remains the exact initial
  ;; state of this clip, then is removed at the end.
  (define held
    (scene-wait formula-written 1))
  (define erased
    (scene-play held
                (unwrite 'equation #:order 'left-to-right)
                #:duration 2))
  ;; PNG/video frames sample the left edge of their intervals.  Keep the
  ;; completed removal visible in the encoded video instead of leaving its
  ;; final frame one 30 fps interval before `unwrite` completes.
  (scene-wait erased 1/2))

(module+ main
  (run-demo "animated-write.rkt" make-demo-scene))
