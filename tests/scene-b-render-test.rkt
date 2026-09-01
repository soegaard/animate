#lang racket/base

;;;
;;; SCENE-B Rendering Tests
;;;

;; Tests built-in rectangle rendering, ordered renderer dispatch, third-party
;; Visual extension, and renderer propagation through PNG output.


;;;
;;; Imports
;;;

(require rackunit
         racket/file
         (only-in pict
                  disk
                  filled-rectangle
                  pict-height
                  pict-width)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 160
                 #:height 90
                 #:world-width 16))

  ; sample-circle : circle-visual?
  ;;   Gives the built-in circle used by renderer-order tests.
  (define sample-circle
    (circle #:id 'circle
            #:radius 1
            #:fill "dodgerblue"))

  ; sample-rectangle : rectangle-visual?
  ;;   Gives the built-in rectangle used by Pict dimension tests.
  (define sample-rectangle
    (rectangle #:id 'rectangle
               #:width 4
               #:height 2
               #:fill "goldenrod"))

  ;; Built-in renderers preserve camera-scaled semantic dimensions.

  ; circle-pict : pict?
  ;;   Gives sample-circle rendered by the default renderer set.
  (define circle-pict
    (visual->pict sample-circle test-camera))

  ; rectangle-pict : pict?
  ;;   Gives sample-rectangle rendered by the default renderer set.
  (define rectangle-pict
    (visual->pict sample-rectangle test-camera))
  (check-equal? (pict-width circle-pict) 20)
  (check-equal? (pict-height circle-pict) 20)
  (check-equal? (pict-width rectangle-pict) 40)
  (check-equal? (pict-height rectangle-pict) 20)
  (check-true (pict-renderer-list? default-pict-renderers))
  (check-false (pict-renderer-list? (list 'not-a-renderer)))

  ;; Renderer order is significant: the first supporting implementation wins.

  (struct circle-override-pict-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (circle-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       (filled-rectangle 7 9 #:color "purple"))])

  ;; circle-override-pict-renderer replaces the built-in circle representation
  ;; when it occurs before the default renderer set.

  ; override-renderer : pict-renderer?
  ;;   Gives a test renderer that also supports circle Visuals.
  (define override-renderer
    (circle-override-pict-renderer))

  ; override-first : (listof pict-renderer?)
  ;;   Gives a renderer set where the custom circle renderer has precedence.
  (define override-first
    (cons override-renderer default-pict-renderers))

  ; override-last : (listof pict-renderer?)
  ;;   Gives a renderer set where the built-in circle renderer has precedence.
  (define override-last
    (append default-pict-renderers (list override-renderer)))
  (check-equal?
   (pict-width
    (visual->pict sample-circle
                  test-camera
                  #:renderers override-first))
   7)
  (check-equal?
   (pict-height
    (visual->pict sample-circle
                  test-camera
                  #:renderers override-first))
   9)
  (check-equal?
   (pict-width
    (visual->pict sample-circle
                  test-camera
                  #:renderers override-last))
   20)

  ;; A third-party Visual can remain semantic and supply a separate renderer.

  (struct marker-visual (id center diameter)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (marker-visual-id marker))
     (define (visual-position marker)
       (marker-visual-center marker))
     (define (visual-with-position marker position)
       (unless (vec2? position)
         (raise-argument-error 'visual-with-position "vec2?" position))
       (struct-copy marker-visual marker [center position]))])

  ;; marker-visual represents a test-only semantic Visual.
  ;;  - id        symbol?                 stable visual identity.
  ;;  - center    vec2?                   center in world coordinates.
  ;;  - diameter  positive finite real?   diameter in world units.

  (struct marker-pict-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (marker-visual? visual))
     (define (pict-renderer-render _renderer visual camera)
       (disk (camera-length->pixels camera
                                    (marker-visual-diameter visual))
             #:color "forestgreen"
             #:border-color "darkgreen"
             #:border-width 1))])

  ;; marker-pict-renderer is the independent Pict adapter for marker-visual.

  ; marker : marker-visual?
  ;;   Gives the custom Visual used by renderer-extension tests.
  (define marker
    (marker-visual 'marker (vec2 -1 0) 1))

  ; marker-renderers : (listof pict-renderer?)
  ;;   Gives the custom renderer followed by all built-in renderers.
  (define marker-renderers
    (cons (marker-pict-renderer)
          default-pict-renderers))
  (check-exn exn:fail:contract?
             (lambda ()
               (visual->pict marker test-camera)))
  (check-equal?
   (pict-width
    (visual->pict marker
                  test-camera
                  #:renderers marker-renderers))
   10)

  ;; Renderer implementations are checked at their protocol boundary.

  (struct invalid-result-pict-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (marker-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       'not-a-pict)])

  ;; invalid-result-pict-renderer deliberately violates the result invariant.

  (struct invalid-support-pict-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer _visual)
       'supported)
     (define (pict-renderer-render _renderer _visual _camera)
       (disk 1))])

  ;; invalid-support-pict-renderer deliberately returns a non-boolean result.

  (check-exn
   exn:fail:contract?
   (lambda ()
     (visual->pict marker
                   test-camera
                   #:renderers
                   (list (invalid-result-pict-renderer)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (visual->pict marker
                   test-camera
                   #:renderers
                   (list (invalid-support-pict-renderer)))))

  ;; A mixed built-in scene renders through the same ordered renderer set.

  ; mixed-state : scene-state?
  ;;   Gives a rectangle behind a circle at the same reference position.
  (define mixed-state
    (scene-current-state
     (scene-add (make-scene)
                sample-rectangle
                sample-circle)))

  ; mixed-pict : pict?
  ;;   Gives mixed-state rendered at fixed camera dimensions.
  (define mixed-pict
    (scene-state->pict mixed-state #:camera test-camera))
  (check-equal? (pict-width mixed-pict) 160)
  (check-equal? (pict-height mixed-pict) 90)

  ;; Custom renderers propagate through scene, bitmap, and PNG adapters.

  ; marker-scene : scene?
  ;;   Gives a custom Visual movement followed by a visible endpoint wait.
  (define marker-scene
    (scene-wait
     (scene-play
      (scene-add (make-scene) marker)
      (move-to marker (vec2 1 0))
      #:duration 1/5)
     1/10))
  (check-equal? (scene-frame-count marker-scene #:fps 10) 3)
  (check-not-false
   (scene-frame->bitmap marker-scene
                        2
                        #:fps 10
                        #:camera test-camera
                        #:renderers marker-renderers))

  ; temporary-directory : path?
  ;;   Gives the isolated output directory for custom renderer PNG tests.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-b~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define frame-paths
        (render-frames! marker-scene
                        temporary-directory
                        #:fps 10
                        #:camera test-camera
                        #:renderers marker-renderers))
      (check-equal? (length frame-paths) 3)
      (check-true
       (file-exists?
        (build-path temporary-directory "frame-000000.png")))
      (check-true
       (file-exists?
        (build-path temporary-directory "frame-000002.png")))
      (check-false
       (bytes=?
        (file->bytes
         (build-path temporary-directory "frame-000000.png"))
        (file->bytes
         (build-path temporary-directory "frame-000002.png")))))
    (lambda ()
      (delete-directory/files temporary-directory))))
