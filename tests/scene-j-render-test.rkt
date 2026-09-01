#lang racket/base

;;;
;;; SCENE-J Rendering Tests
;;;

;; Tests global Pict opacity, renderer-independent opacity application, fade
;; frame sampling, transparent endpoints, and deterministic PNG output.


;;;
;;; Imports
;;;

(require racket/file
         rackunit
         (only-in pict
                  filled-rectangle
                  pict-height
                  pict-width)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 240
                 #:height 160
                 #:world-width 24
                 #:background "white"))

  ; opaque-panel : rectangle-visual?
  ;;   Gives a fully opaque rectangle centered in the frame.
  (define opaque-panel
    (rectangle #:id 'panel
               #:width 8
               #:height 6
               #:fill "royalblue"
               #:stroke "navy"
               #:stroke-width 2))

  ; half-panel : rectangle-visual?
  ;;   Gives the same rectangle at half opacity.
  (define half-panel
    (visual-with-opacity opaque-panel 1/2))

  ; invisible-panel : rectangle-visual?
  ;;   Gives the same rectangle at zero opacity.
  (define invisible-panel
    (visual-with-opacity opaque-panel 0))

  ; opaque-pict : pict?
  ;;   Gives the fully opaque panel Pict.
  (define opaque-pict
    (visual->pict opaque-panel test-camera))

  ; half-pict : pict?
  ;;   Gives the half-opacity panel Pict.
  (define half-pict
    (visual->pict half-panel test-camera))

  ; invisible-pict : pict?
  ;;   Gives the zero-opacity panel Pict.
  (define invisible-pict
    (visual->pict invisible-panel test-camera))

  ;; Opacity changes drawing only. It preserves the renderer's layout box.

  (check-equal? (pict-width opaque-pict)
                (pict-width half-pict))
  (check-equal? (pict-width opaque-pict)
                (pict-width invisible-pict))
  (check-equal? (pict-height opaque-pict)
                (pict-height half-pict))
  (check-equal? (pict-height opaque-pict)
                (pict-height invisible-pict))

  ;; Semantic opacity is applied after renderer dispatch, so a third-party
  ;; Visual and renderer receive the same behavior without renderer changes.

  (struct opacity-marker (id position opacity)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (opacity-marker-id marker))
     (define (visual-position marker)
       (opacity-marker-position marker))
     (define (visual-with-position marker position)
       (struct-copy opacity-marker marker [position position]))]
    #:methods gen:opacity-visual
    [(define (visual-opacity marker)
       (opacity-marker-opacity marker))
     (define (visual-with-opacity marker opacity)
       (struct-copy opacity-marker marker [opacity opacity]))])

  ;; opacity-marker represents a custom position-only opacity Visual.
  ;;  - id        symbol?   stable Visual identity.
  ;;  - position  vec2?     world-space reference position.
  ;;  - opacity   opacity?  global rendering opacity.

  ; marker-shape : pict?
  ;;   Gives the full-strength local Pict returned by the custom renderer.
  (define marker-shape
    (filled-rectangle 80
                      40
                      #:color "darkorange"
                      #:border-color "saddlebrown"
                      #:border-width 2))

  (struct invalid-opacity-marker (id position)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (invalid-opacity-marker-id marker))
     (define (visual-position marker)
       (invalid-opacity-marker-position marker))
     (define (visual-with-position marker position)
       (struct-copy invalid-opacity-marker marker [position position]))]
    #:methods gen:opacity-visual
    [(define (visual-opacity _marker)
       2)
     (define (visual-with-opacity marker _opacity)
       marker)])

  ;; invalid-opacity-marker deliberately violates the opacity protocol.
  ;;  - id        symbol?  stable Visual identity.
  ;;  - position  vec2?    world-space reference position.

  (struct opacity-marker-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (or (opacity-marker? visual)
           (invalid-opacity-marker? visual)))
     (define (pict-renderer-render _renderer _visual _camera)
       marker-shape)])

  ;; opacity-marker-renderer draws custom Visuals without handling opacity.

  ; marker-renderers : (listof pict-renderer?)
  ;;   Gives a renderer set with the custom renderer before built-ins.
  (define marker-renderers
    (cons (opacity-marker-renderer)
          default-pict-renderers))

  ; full-marker : opacity-marker?
  ;;   Gives a fully opaque custom Visual.
  (define full-marker
    (opacity-marker 'marker origin 1))

  ; zero-marker : opacity-marker?
  ;;   Gives a transparent custom Visual.
  (define zero-marker
    (opacity-marker 'marker origin 0))

  ; full-marker-pict : pict?
  ;;   Gives the rendered opaque custom Visual.
  (define full-marker-pict
    (visual->pict full-marker
                  test-camera
                  #:renderers marker-renderers))

  ; zero-marker-pict : pict?
  ;;   Gives the rendered transparent custom Visual.
  (define zero-marker-pict
    (visual->pict zero-marker
                  test-camera
                  #:renderers marker-renderers))

  (check-eq? full-marker-pict marker-shape)
  (check-equal? (pict-width full-marker-pict)
                (pict-width zero-marker-pict))
  (check-equal? (pict-height full-marker-pict)
                (pict-height zero-marker-pict))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (visual->pict (invalid-opacity-marker 'invalid origin)
                   test-camera
                   #:renderers marker-renderers)))

  ;; Static scenes make opacity differences visible in the encoded PNG bytes.
  ;; A zero-opacity Visual produces the same pixels as an empty scene.

  ; scene-with : visual? -> scene?
  ;;   Creates a quarter-second static scene containing visual.
  (define (scene-with visual)
    (scene-wait (scene-add (make-scene) visual)
                1/4))

  ; empty-static-scene : scene?
  ;;   Gives a quarter-second scene with only the camera background.
  (define empty-static-scene
    (scene-wait (make-scene) 1/4))

  ; temporary-root : path?
  ;;   Gives the isolated root directory for opacity PNG tests.
  (define temporary-root
    (make-temporary-file "visual-animation-scene-j~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      ; render-one-frame! : scene? path-string?
      ;                     [#:renderers (listof pict-renderer?)]
      ;                     -> bytes?
      ;;   Renders one four-fps frame and returns its PNG bytes.
      (define (render-one-frame! scene directory
                                 #:renderers
                                 [renderers default-pict-renderers])
        (define frame-paths
          (render-frames! scene
                          directory
                          #:fps 4
                          #:camera test-camera
                          #:renderers renderers))
        (check-equal? (length frame-paths) 1)
        (file->bytes (car frame-paths)))

      ; opaque-bytes : bytes?
      ;;   Gives one fully opaque built-in frame.
      (define opaque-bytes
        (render-one-frame! (scene-with opaque-panel)
                           (build-path temporary-root "opaque")))

      ; half-bytes : bytes?
      ;;   Gives one half-opacity built-in frame.
      (define half-bytes
        (render-one-frame! (scene-with half-panel)
                           (build-path temporary-root "half")))

      ; invisible-bytes : bytes?
      ;;   Gives one zero-opacity built-in frame.
      (define invisible-bytes
        (render-one-frame! (scene-with invisible-panel)
                           (build-path temporary-root "invisible")))

      ; empty-bytes : bytes?
      ;;   Gives one background-only frame.
      (define empty-bytes
        (render-one-frame! empty-static-scene
                           (build-path temporary-root "empty")))

      (check-false (equal? opaque-bytes half-bytes))
      (check-false (equal? half-bytes invisible-bytes))
      (check-equal? invisible-bytes empty-bytes)

      ; full-marker-bytes : bytes?
      ;;   Gives one opaque custom-renderer frame.
      (define full-marker-bytes
        (render-one-frame! (scene-with full-marker)
                           (build-path temporary-root "marker-full")
                           #:renderers marker-renderers))

      ; zero-marker-bytes : bytes?
      ;;   Gives one transparent custom-renderer frame.
      (define zero-marker-bytes
        (render-one-frame! (scene-with zero-marker)
                           (build-path temporary-root "marker-zero")
                           #:renderers marker-renderers))

      (check-false (equal? full-marker-bytes zero-marker-bytes))
      (check-equal? zero-marker-bytes empty-bytes)

      ;; A complete fade-in followed by fade-out produces a transparent start,
      ;; a fully visible middle, and a removed structural endpoint.

      ; entering-token : circle-visual?
      ;;   Gives the Visual introduced and removed by the fade timeline.
      (define entering-token
        (circle #:id 'entering-token
                #:radius 3
                #:fill "mediumseagreen"
                #:stroke "darkgreen"
                #:stroke-width 3))

      ; fade-scene : scene?
      ;;   Fades one circle in, fades it out, and holds the empty endpoint.
      (define fade-scene
        (scene-wait
         (scene-play
          (scene-play (make-scene)
                      (fade-in entering-token)
                      #:duration 1)
          (fade-out entering-token)
          #:duration 1)
         1/4))

      (check-equal? (scene-frame-count fade-scene #:fps 4)
                    9)
      (check-not-false
       (scene-frame->bitmap fade-scene
                            0
                            #:fps 4
                            #:camera test-camera))
      (check-not-false
       (scene-frame->bitmap fade-scene
                            4
                            #:fps 4
                            #:camera test-camera))
      (check-not-false
       (scene-frame->bitmap fade-scene
                            8
                            #:fps 4
                            #:camera test-camera))

      ; fade-directory : path?
      ;;   Gives the numbered output directory for the fade timeline.
      (define fade-directory
        (build-path temporary-root "timeline"))

      ; fade-paths : (listof path?)
      ;;   Gives the nine numbered fade-frame paths.
      (define fade-paths
        (render-frames! fade-scene
                        fade-directory
                        #:fps 4
                        #:camera test-camera))

      (check-equal? (length fade-paths) 9)

      ; start-bytes : bytes?
      ;;   Gives the transparent fade-in start frame.
      (define start-bytes
        (file->bytes
         (build-path fade-directory "frame-000000.png")))

      ; half-in-bytes : bytes?
      ;;   Gives the half-visible fade-in frame.
      (define half-in-bytes
        (file->bytes
         (build-path fade-directory "frame-000002.png")))

      ; full-bytes : bytes?
      ;;   Gives the fully visible boundary frame.
      (define full-bytes
        (file->bytes
         (build-path fade-directory "frame-000004.png")))

      ; half-out-bytes : bytes?
      ;;   Gives the half-visible fade-out frame.
      (define half-out-bytes
        (file->bytes
         (build-path fade-directory "frame-000006.png")))

      ; endpoint-bytes : bytes?
      ;;   Gives the held frame after structural removal.
      (define endpoint-bytes
        (file->bytes
         (build-path fade-directory "frame-000008.png")))

      (check-equal? start-bytes endpoint-bytes)
      (check-equal? half-in-bytes half-out-bytes)
      (check-false (equal? start-bytes half-in-bytes))
      (check-false (equal? half-in-bytes full-bytes))

      ;; Re-rendering the same timeline is byte-identical.

      (render-frames! fade-scene
                      fade-directory
                      #:fps 4
                      #:camera test-camera)
      (check-equal?
       start-bytes
       (file->bytes
        (build-path fade-directory "frame-000000.png")))
      (check-equal?
       half-in-bytes
       (file->bytes
        (build-path fade-directory "frame-000002.png")))
      (check-equal?
       full-bytes
       (file->bytes
        (build-path fade-directory "frame-000004.png")))
      (check-equal?
       endpoint-bytes
       (file->bytes
        (build-path fade-directory "frame-000008.png"))))
    (lambda ()
      (delete-directory/files temporary-root))))
