#lang racket/base

;;;
;;; SCENE-P Rendering Tests
;;;

;; Tests renderer-aware formula layout, fitted card composition, animation
;; frames, renderer-dependent placement, and deterministic PNG output.


;;;
;;; Imports
;;;

(require racket/file
         (only-in racket/list take)
         rackunit
         (only-in pict
                  filled-rectangle
                  pict-height
                  pict-width)
         "../main.rkt"
         "../render.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed camera with twenty pixels per world unit.
  (define test-camera
    (make-camera #:width 400
                 #:height 240
                 #:world-width 20
                 #:background "white"))

  (struct formula-metric-renderer (width-factor)
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (formula-visual? visual))
     (define (pict-renderer-render renderer visual _camera)
       (define width
         (* (formula-metric-renderer-width-factor renderer)
            (+ 10
               (* 6
                  (string-length
                   (formula-visual-source visual))))))
       (define height
         (case (string->symbol (formula-visual-source visual))
           [(title) 16]
           [(identity) 28]
           [(sum) 48]
           [else 20]))
       (filled-rectangle width height #:draw-border? #f))])

  ;; formula-metric-renderer provides deterministic test metrics and prevents
  ;; the mandatory suite from launching TeX.

  ; formula-renderers : (listof pict-renderer?)
  ;;   Gives the main deterministic metric renderer before built-in renderers.
  (define formula-renderers
    (cons (formula-metric-renderer 1)
          default-pict-renderers))

  ; wide-formula-renderers : (listof pict-renderer?)
  ;;   Gives a second metric environment with twice the formula width.
  (define wide-formula-renderers
    (cons (formula-metric-renderer 2)
          default-pict-renderers))

  ; make-content : -> (listof formula-visual?)
  ;;   Creates formulas whose initial anchors deliberately coincide.
  (define (make-content)
    (list
     (latex-formula "title" #:id 'title)
     (latex-formula "identity" #:id 'identity)
     (latex-formula "sum" #:id 'sum)))

  ; arrange-content : (listof pict-renderer?) -> (listof formula-visual?)
  ;;   Arranges one formula set vertically and centers its union at the origin.
  (define (arrange-content renderers)
    (arrange-visuals-vertically
     (make-content)
     #:gap 1/2
     #:center origin
     #:camera test-camera
     #:renderers renderers))

  ; content : (listof formula-visual?)
  ;;   Gives the primary non-overlapping formula layout.
  (define content
    (arrange-content formula-renderers))

  ; content-box : layout-box?
  ;;   Gives the complete formula render box in local world coordinates.
  (define content-box
    (visuals-layout-box content
                        #:camera test-camera
                        #:renderers formula-renderers))

  ; background : rectangle-visual?
  ;;   Gives a fitted card with one half-unit padding on every side.
  (define background
    (rectangle #:id 'background
               #:center (layout-box-center content-box)
               #:width (+ (layout-box-width content-box) 1)
               #:height (+ (layout-box-height content-box) 1)
               #:fill "aliceblue"
               #:stroke "navy"
               #:stroke-width 2))

  ; card : group-visual?
  ;;   Gives the fitted background and arranged formulas in drawing order.
  (define card
    (group (cons background content)
           #:id 'formula-card
           #:center (vec2 -4 1)
           #:rotation -1/12
           #:scale 4/5
           #:opacity 9/10))

  ;; The measured content has exact requested gaps and fits inside the card.
  (for ([upper (in-list content)]
        [lower (in-list (cdr content))])
    (define upper-box
      (visual-layout-box upper
                         #:camera test-camera
                         #:renderers formula-renderers))
    (define lower-box
      (visual-layout-box lower
                         #:camera test-camera
                         #:renderers formula-renderers))
    (check-equal? (- (layout-box-bottom upper-box)
                     (layout-box-top lower-box))
                  1/2))

  ; background-box : layout-box?
  ;;   Gives the fitted rectangle box before group inheritance.
  (define background-box
    (visual-layout-box background #:camera test-camera))

  (check-equal? (- (layout-box-left content-box)
                   (layout-box-left background-box))
                1/2)
  (check-equal? (- (layout-box-right background-box)
                   (layout-box-right content-box))
                1/2)
  (check-equal? (- (layout-box-bottom content-box)
                   (layout-box-bottom background-box))
                1/2)
  (check-equal? (- (layout-box-top background-box)
                   (layout-box-top content-box))
                1/2)

  ;; Formula width changes in a different renderer environment alter horizontal
  ;; arrangement, so callers must use the same camera and renderers for layout
  ;; and final rendering.
  ; horizontal-normal : (listof formula-visual?)
  ;;   Gives two formulas arranged with the primary renderer metrics.
  (define horizontal-normal
    (arrange-visuals-horizontally
     (take (make-content) 2)
     #:gap 1/2
     #:camera test-camera
     #:renderers formula-renderers))

  ; horizontal-wide : (listof formula-visual?)
  ;;   Gives the same formulas arranged with doubled renderer widths.
  (define horizontal-wide
    (arrange-visuals-horizontally
     (take (make-content) 2)
     #:gap 1/2
     #:camera test-camera
     #:renderers wide-formula-renderers))

  (check-true
   (> (vec2-x (visual-position (cadr horizontal-wide)))
      (vec2-x (visual-position (cadr horizontal-normal)))))

  ; local-card : group-visual?
  ;;   Gives the complete card at its local origin for Pict dimension checks.
  (define local-card
    (visual-with-position card origin))

  ; local-card-pict : pict?
  ;;   Gives the recursively rendered fitted card.
  (define local-card-pict
    (visual->pict local-card
                  test-camera
                  #:renderers formula-renderers))

  (check-true (> (pict-width local-card-pict) 1))
  (check-true (> (pict-height local-card-pict) 1))

  ; entrance : scene?
  ;;   Fades, moves, rotates, and scales the laid-out card into place.
  (define entrance
    (scene-play (make-scene)
                (move-to card origin)
                (rotate-to card 0)
                (scale-to card 1)
                (fade-in card)
                #:duration 1))

  ; animation : scene?
  ;;   Holds the completed fitted layout for one quarter second.
  (define animation
    (scene-wait entrance 1/4))

  (check-equal? (scene-frame-count animation #:fps 4) 5)

  ; temporary-root : path?
  ;;   Gives an isolated directory root for PNG comparisons.
  (define temporary-root
    (make-temporary-file "visual-animation-scene-p~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      ; first-paths : (listof path?)
      ;;   Gives the first complete rendering of the layout animation.
      (define first-paths
        (render-frames! animation
                        (build-path temporary-root "first")
                        #:fps 4
                        #:camera test-camera
                        #:renderers formula-renderers))

      ; second-paths : (listof path?)
      ;;   Gives the second complete rendering of the same animation.
      (define second-paths
        (render-frames! animation
                        (build-path temporary-root "second")
                        #:fps 4
                        #:camera test-camera
                        #:renderers formula-renderers))

      (check-equal? (length first-paths) 5)
      (check-equal? (length second-paths) 5)
      (check-equal? (map file->bytes first-paths)
                    (map file->bytes second-paths))
      (check-false
       (equal? (file->bytes (car first-paths))
               (file->bytes (car (reverse first-paths))))))
    (lambda ()
      (delete-directory/files temporary-root))))
