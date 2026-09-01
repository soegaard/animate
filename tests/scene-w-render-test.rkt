#lang racket/base

;;;
;;; SCENE-W Camera-Framing Rendering Tests
;;;

;; Tests renderer-aware fit requests, scene-target selection, custom-renderer
;; metrics, frame-position preservation, and deterministic PNG output.


;;;
;;; Imports
;;;

(require racket/file
         rackunit
         (only-in pict filled-rectangle)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a two-to-one frame with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center origin
                 #:background "white"))

  ;; Manual layout-box fitting preserves frame settings and respects height.
  (define fitted-box-request
    (camera-fit-layout-box (layout-box -2 -1 4 3)
                           #:camera test-camera
                           #:padding 1))
  (check-true (camera-fit-request? fitted-box-request))

  (define fitted-box-scene
    (scene-play (make-scene #:camera test-camera)
                fitted-box-request
                #:duration 2))
  (define fitted-box-mid-camera
    (scene-camera-at fitted-box-scene 1))
  (define fitted-box-end-camera
    (scene-current-camera fitted-box-scene))

  (check-equal? (camera-center fitted-box-mid-camera)
                (vec2 1/2 1/2))
  (check-equal? (camera-world-width fitted-box-mid-camera) 16)
  (check-equal? (camera-center fitted-box-end-camera)
                (vec2 1 1))
  (check-equal? (camera-world-width fitted-box-end-camera) 12)
  (check-equal? (camera-width fitted-box-end-camera) 200)
  (check-equal? (camera-height fitted-box-end-camera) 100)
  (check-equal? (camera-background fitted-box-end-camera) "white")

  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-fit-layout-box (layout-box 0 0 0 0)
                            #:camera test-camera
                            #:padding 0)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-fit-layout-box (layout-box 0 0 1 1)
                            #:camera test-camera
                            #:padding -1)))

  ; left-box : rectangle-visual?
  ;;   Gives the left Visual used by union fitting.
  (define left-box
    (rectangle #:id 'left-box
               #:center (vec2 -3 0)
               #:width 2
               #:height 2
               #:fill "gold"
               #:stroke #f
               #:stroke-width 0))

  ; right-box : rectangle-visual?
  ;;   Gives the right Visual used by union fitting.
  (define right-box
    (rectangle #:id 'right-box
               #:center (vec2 3 1)
               #:width 4
               #:height 2
               #:fill "cornflowerblue"
               #:stroke #f
               #:stroke-width 0))

  ;; Visual fitting uses the union of complete rendered boxes.
  (define fitted-visuals-request
    (camera-fit-visuals (list left-box right-box)
                        #:camera test-camera
                        #:padding 1/2))
  (define fitted-visuals-scene
    (scene-play (make-scene #:camera test-camera)
                fitted-visuals-request
                #:duration 1))
  (check-equal? (camera-center
                 (scene-current-camera fitted-visuals-scene))
                (vec2 1/2 1/2))
  (check-equal? (camera-world-width
                 (scene-current-camera fitted-visuals-scene))
                10)

  (struct metric-visual (id position)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual)
       (metric-visual-id visual))
     (define (visual-position visual)
       (metric-visual-position visual))
     (define (visual-with-position visual position)
       (metric-visual (metric-visual-id visual)
                      position))])

  ;; metric-visual is a test-only semantic value rendered by metric-renderer.
  ;;  - id        symbol?  stable Visual identity.
  ;;  - position  vec2?    containing-coordinate reference position.

  (struct metric-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (metric-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       (filled-rectangle 80 20
                         #:color "purple"
                         #:draw-border? #f))])

  ;; metric-renderer gives a stable eighty-by-twenty custom Pict.

  ; custom-renderers : (listof pict-renderer?)
  ;;   Gives explicit custom precedence before the built-in renderers.
  (define custom-renderers
    (cons (metric-renderer)
          default-pict-renderers))

  ; metric : metric-visual?
  ;;   Gives a custom Visual whose renderer determines framing dimensions.
  (define metric
    (metric-visual 'metric (vec2 2 -1)))

  ;; Custom renderer dimensions participate in automatic fitting.
  (define metric-fit-scene
    (scene-play
     (make-scene #:camera test-camera)
     (camera-fit-visuals (list metric)
                         #:camera test-camera
                         #:padding 1
                         #:renderers custom-renderers)
     #:duration 1))
  (check-equal? (camera-center
                 (scene-current-camera metric-fit-scene))
                (vec2 2 -1))
  (check-equal? (camera-world-width
                 (scene-current-camera metric-fit-scene))
                10)

  ;; Scene fitting can select all top-level Visuals or a requested subset.
  (define boxes-scene
    (scene-add (make-scene #:camera test-camera)
               left-box
               right-box))
  (define fit-all-scene
    (scene-play boxes-scene
                (camera-fit-scene boxes-scene #:padding 1/2)
                #:duration 1))
  (check-equal? (scene-current-camera fit-all-scene)
                (scene-current-camera fitted-visuals-scene))

  (define fit-left-scene
    (scene-play boxes-scene
                (camera-fit-scene boxes-scene
                                  #:targets (list 'left-box)
                                  #:padding 0)
                #:duration 1))
  (check-equal? (camera-center
                 (scene-current-camera fit-left-scene))
                (vec2 -3 0))
  (check-equal? (camera-world-width
                 (scene-current-camera fit-left-scene))
                4)

  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-fit-scene (make-scene #:camera test-camera))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-fit-scene boxes-scene
                       #:targets (list 'missing))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-fit-scene boxes-scene
                       #:targets (list 42))))

  ;; Visual-valued targets resolve by identity to the current scene endpoint.
  (define moved-boxes-scene
    (scene-play boxes-scene
                (move-to left-box origin)
                #:duration 1))
  (define fit-current-left-scene
    (scene-play moved-boxes-scene
                (camera-fit-scene moved-boxes-scene
                                  #:targets (list left-box)
                                  #:padding 0)
                #:duration 1))
  (check-equal? (camera-center
                 (scene-current-camera fit-current-left-scene))
                origin)
  (check-equal? (camera-world-width
                 (scene-current-camera fit-current-left-scene))
                4)

  ;; A fit request reserves both camera components.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play boxes-scene
                 (camera-fit-scene boxes-scene)
                 (camera-pan-to origin))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play boxes-scene
                 (camera-fit-scene boxes-scene)
                 (camera-zoom-to 8))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play boxes-scene
                 (camera-fit-scene boxes-scene)
                 (camera-follow left-box))))

  ;; Following without zoom keeps a moving marker's rendered frame unchanged.
  (define tracking-marker
    (circle #:id 'tracking-marker
            #:center (vec2 -4 0)
            #:radius 1/2
            #:fill "crimson"
            #:stroke #f
            #:stroke-width 0))
  (define tracking-scene
    (scene-play
     (scene-add (make-scene #:camera test-camera)
                tracking-marker)
     (move-to tracking-marker (vec2 4 0))
     (camera-follow tracking-marker)
     #:duration 1))

  ; tracking-directory : path?
  ;;   Gives isolated output for camera-follow frames.
  (define tracking-directory
    (make-temporary-file "visual-animation-scene-w-follow~a" 'directory))

  ; fit-directory : path?
  ;;   Gives isolated output for automatic-fit frames.
  (define fit-directory
    (make-temporary-file "visual-animation-scene-w-fit~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      (define tracking-paths
        (render-frames! tracking-scene
                        tracking-directory
                        #:fps 2))
      (check-equal? (length tracking-paths) 2)
      (define tracking-first-bytes
        (file->bytes
         (build-path tracking-directory "frame-000000.png")))
      (define tracking-second-bytes
        (file->bytes
         (build-path tracking-directory "frame-000001.png")))
      (check-equal? tracking-first-bytes
                    tracking-second-bytes)

      (define fit-animation
        (scene-wait
         (scene-play boxes-scene
                     (camera-fit-scene boxes-scene #:padding 1/2)
                     #:duration 1)
         1/2))
      (define fit-paths
        (render-frames! fit-animation
                        fit-directory
                        #:fps 2))
      (check-equal? (length fit-paths) 3)
      (define fit-first-bytes
        (file->bytes
         (build-path fit-directory "frame-000000.png")))
      (define fit-last-bytes
        (file->bytes
         (build-path fit-directory "frame-000002.png")))
      (check-false (bytes=? fit-first-bytes
                            fit-last-bytes))

      ;; Re-rendering both camera behaviors is byte-identical.
      (render-frames! tracking-scene
                      tracking-directory
                      #:fps 2)
      (render-frames! fit-animation
                      fit-directory
                      #:fps 2)
      (check-equal?
       tracking-first-bytes
       (file->bytes
        (build-path tracking-directory "frame-000000.png")))
      (check-equal?
       fit-last-bytes
       (file->bytes
        (build-path fit-directory "frame-000002.png"))))
    (lambda ()
      (delete-directory/files tracking-directory)
      (delete-directory/files fit-directory))))
