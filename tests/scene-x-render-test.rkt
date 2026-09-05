#lang racket/base

;;;
;;; SCENE-X Frame-Space Rendering Tests
;;;

;; Tests camera-independent overlay placement, renderer-aware frame layout,
;; callout target tracking, camera-fit separation, and deterministic PNG output.


;;;
;;; Imports
;;;

(require racket/file
         rackunit
         (only-in pict blank pict-height pict-width)
         "../main.rkt"
         "../render.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a small exact camera that makes frame-space measurements simple.
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center origin
                 #:background "white"))

  ; label : rectangle-visual?
  ;;   Gives deterministic overlay geometry with no font dependencies.
  (define label
    (rectangle #:id 'label
               #:center (vec2 3 2)
               #:width 4
               #:height 2
               #:fill "gold"
               #:stroke #f
               #:stroke-width 0))

  ; overlay : fixed-in-frame-visual?
  ;;   Gives a label captured at ten pixels per frame unit.
  (define overlay
    (fixed-in-frame label #:camera test-camera))

  ;; Local rendering remains twenty frame pixels wide per two frame units and
  ;; therefore does not adopt a later world-camera zoom.
  (define zoomed-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 5
                 #:center (vec2 50 -30)
                 #:background "white"))
  (define overlay-pict
    (visual->pict overlay zoomed-camera))
  (check-equal? (pict-width overlay-pict) 40)
  (check-equal? (pict-height overlay-pict) 20)

  ;; Explicit renderer dispatch sees the derived frame camera for a frame-space
  ;; wrapper rather than the later zoomed world camera. This preserves the
  ;; renderer protocol as an extension point for custom overlay Visuals.
  (struct frame-probe-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (fixed-in-frame-visual? visual))
     (define (pict-renderer-render _renderer _visual camera)
       (blank (camera-world-width camera) 7))])

  (define frame-probe-renderers
    (cons (frame-probe-renderer)
          default-pict-renderers))
  (define custom-overlay-pict
    (visual->pict overlay
                  zoomed-camera
                  #:renderers frame-probe-renderers))
  (check-equal? (pict-width custom-overlay-pict) 20)
  (check-equal? (pict-height custom-overlay-pict) 7)

  ;; Renderer-aware layout reports frame-coordinate extents, not zoomed world
  ;; extents, and remains stable under pan/zoom of the world camera.
  (check-equal? (visual-layout-box overlay #:camera test-camera)
                (layout-box 1 1 5 3))
  (check-equal? (visual-layout-box overlay #:camera zoomed-camera)
                (layout-box 1 1 5 3))

  (define second-overlay
    (fixed-in-frame
     (rectangle #:id 'second-label
                #:center (vec2 -3 2)
                #:width 2
                #:height 2
                #:fill "lightblue"
                #:stroke #f
                #:stroke-width 0)
     #:camera test-camera))
  (check-equal?
   (visuals-layout-box (list overlay second-overlay)
                       #:camera zoomed-camera)
   (layout-box -4 1 5 3))

  ;; Two frame-space Visuals can share layout only when they were captured in
  ;; the same frame coordinate system. Different visible widths are distinct
  ;; coordinate domains even when output pixel dimensions happen to match.
  (define narrow-frame-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 10
                 #:center origin
                 #:background "white"))
  (define narrow-overlay
    (fixed-in-frame
     (rectangle #:id 'narrow-label
                #:center origin
                #:width 1
                #:height 1
                #:fill "white"
                #:stroke #f
                #:stroke-width 0)
     #:camera narrow-frame-camera))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (visuals-layout-box (list overlay narrow-overlay)
                         #:camera test-camera)))

  ;; World and frame-space values cannot be combined in one relative-layout
  ;; coordinate calculation.
  (define world-box
    (rectangle #:id 'world-box
               #:center origin
               #:width 2
               #:height 2
               #:fill "gray"
               #:stroke #f
               #:stroke-width 0))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (visuals-layout-box (list world-box overlay)
                         #:camera test-camera)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (visual-place-above overlay
                         world-box
                         #:camera test-camera)))

  ;; Camera fitting ignores overlays when fitting an entire scene and rejects
  ;; explicit frame-space fit requests.
  (define mixed-scene
    (scene-add (make-scene #:camera test-camera)
               world-box
               overlay))
  (define world-only-scene
    (scene-add (make-scene #:camera test-camera)
               world-box))
  (define fit-mixed
    (scene-play mixed-scene
                (camera-fit-scene mixed-scene #:padding 1)
                #:duration 1))
  (define fit-world-only
    (scene-play world-only-scene
                (camera-fit-scene world-only-scene #:padding 1)
                #:duration 1))
  (check-equal? (scene-current-camera fit-mixed)
                (scene-current-camera fit-world-only))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-fit-visuals (list overlay)
                         #:camera test-camera)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-fit-scene mixed-scene
                       #:targets (list 'label))))

  ;; A scene containing only frame-space content has no world bounds to fit.
  (define overlay-only-scene
    (scene-add (make-scene #:camera test-camera)
               overlay))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-fit-scene overlay-only-scene)))

  ;; A missing symbolic callout target is rejected at scene rendering, where
  ;; sampled top-level target identity can be resolved.
  (define missing-target-callout
    (callout
     (rectangle #:id 'missing-note
                #:center (vec2 4 3)
                #:width 2
                #:height 1
                #:fill "white"
                #:stroke "black"
                #:stroke-width 1)
     'missing-target
     #:camera test-camera))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-state->pict
      (scene-current-state
       (scene-add (make-scene #:camera test-camera)
                  missing-target-callout))
      #:camera test-camera)))

  ; fixed-directory : path?
  ;;   Gives isolated PNG output for the fixed-overlay camera-motion test.
  (define fixed-directory
    (make-temporary-file "visual-animation-scene-x-fixed~a" 'directory))

  ; callout-directory : path?
  ;;   Gives isolated PNG output for the moving callout-connector test.
  (define callout-directory
    (make-temporary-file "visual-animation-scene-x-callout~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      ;; With only fixed frame content visible, world-camera pan and zoom cannot
      ;; change any pixel in the rendered frame.
      (define fixed-scene
        (scene-play
         (scene-add (make-scene #:camera test-camera)
                    overlay)
         (camera-pan-by (vec2 8 -4))
         (camera-zoom-by 4)
         #:duration 1))
      (define fixed-paths
        (render-frames! fixed-scene
                        fixed-directory
                        #:fps 2))
      (check-equal? (length fixed-paths) 2)
      (define fixed-first-bytes
        (file->bytes
         (build-path fixed-directory "frame-000000.png")))
      (define fixed-second-bytes
        (file->bytes
         (build-path fixed-directory "frame-000001.png")))
      (check-equal? fixed-first-bytes
                    fixed-second-bytes)

      ;; A callout label remains fixed while its leader follows the sampled world
      ;; target through simultaneous target motion, camera pan, and camera zoom.
      (define target
        (circle #:id 'target
                #:center (vec2 -6 -2)
                #:radius 1/4
                #:opacity 0
                #:fill "red"
                #:stroke #f
                #:stroke-width 0))
      (define note
        (callout
         (rectangle #:id 'note
                    #:center (vec2 5 3)
                    #:width 3
                    #:height 1
                    #:fill "white"
                    #:stroke "navy"
                    #:stroke-width 2)
         target
         #:camera test-camera
         #:connector-stroke "navy"
         #:connector-width 2))
      (define callout-scene
        (scene-play
         (scene-add (make-scene #:camera test-camera)
                    target
                    note)
         (move-to target (vec2 6 -2))
         (camera-pan-by (vec2 2 1))
         (camera-zoom-by 2)
         #:duration 1))
      (define callout-paths
        (render-frames! callout-scene
                        callout-directory
                        #:fps 2))
      (check-equal? (length callout-paths) 2)
      (define callout-first-bytes
        (file->bytes
         (build-path callout-directory "frame-000000.png")))
      (define callout-second-bytes
        (file->bytes
         (build-path callout-directory "frame-000001.png")))
      (check-false (bytes=? callout-first-bytes
                            callout-second-bytes))

      ;; Re-rendering both behaviors is byte-identical.
      (render-frames! fixed-scene
                      fixed-directory
                      #:fps 2)
      (render-frames! callout-scene
                      callout-directory
                      #:fps 2)
      (check-equal?
       fixed-first-bytes
       (file->bytes
        (build-path fixed-directory "frame-000000.png")))
      (check-equal?
       callout-second-bytes
       (file->bytes
        (build-path callout-directory "frame-000001.png"))))
    (lambda ()
      (delete-directory/files fixed-directory)
      (delete-directory/files callout-directory))))
