#lang racket/base

;;;
;;; SCENE-AS Stroke-Width Rendering Tests
;;;

(require racket/class
         racket/file
         rackunit
         (only-in pict blank pict->bitmap)
         "../main.rkt"
         "../render.rkt")

(module+ test
  (define (bitmap->argb-bytes bitmap)
    (define width (send bitmap get-width))
    (define height (send bitmap get-height))
    (define pixels (make-bytes (* width height 4)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    pixels)

  (define (scene-time->argb-bytes scene time)
    (bitmap->argb-bytes
     (pict->bitmap (scene->pict scene time) 'aligned)))

  (define camera
    (make-camera #:width 320
                 #:height 180
                 #:world-width 12
                 #:background "white"))
  (define ring
    (circle #:id 'ring
            #:radius 1
            #:center origin
            #:fill #f
            #:stroke "royalblue"
            #:stroke-width 1))
  (define scene
    (scene-play
     (scene-add (make-scene #:camera camera) ring)
     (animation-group
      (stroke-width-to ring 16)
      (move-to ring (vec2 3 0)))
     #:duration 2))

  ;; Renderer dimensions stay stable while both position and cosmetic width change.
  (for ([frame-index (in-range (scene-frame-count scene #:fps 2))])
    (define bitmap
      (scene-frame->bitmap scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 320)
    (check-equal? (send bitmap get-height) 180))

  (check-equal? (visual-stroke-width
                 (scene-state-ref (scene-sample scene 0) 'ring))
                1)
  (check-equal? (visual-stroke-width
                 (scene-state-ref (scene-sample scene 1) 'ring))
                17/2)
  (check-equal? (visual-stroke-width
                 (scene-state-ref (scene-sample scene 2) 'ring))
                16)

  (define sampled-bytes
    (for/list ([frame-index (in-range 4)])
      (bitmap->argb-bytes
       (scene-frame->bitmap scene frame-index #:fps 2))))
  (for ([left-bytes (in-list sampled-bytes)]
        [right-bytes (in-list (cdr sampled-bytes))])
    (check-false (equal? left-bytes right-bytes)))

  ;; Each built-in protocol implementation independently propagates the sampled
  ;; semantic width into the default renderer. Keep these as separate checks so
  ;; one changing Visual cannot mask a broken adapter for another type.
  (define renderer-cases
    (list
     (circle #:id 'render-circle
             #:radius 1
             #:fill #f
             #:stroke-width 1)
     (rectangle #:id 'render-rectangle
                #:width 3
                #:height 2
                #:fill #f
                #:stroke-width 1)
     (line (vec2 -2 0) (vec2 2 0)
           #:id 'render-path
           #:stroke-width 1)
     (arrow (vec2 -2 0) (vec2 2 0)
            #:id 'render-arrow
            #:stroke-width 1)
     (axes #:id 'render-axes
           #:x-range (axis-range -1 1 1)
           #:y-range (axis-range -1 1 1)
           #:x-length 4
           #:y-length 4
           #:stroke-width 1)
     (number-line (axis-range -1 1 1)
                  #:id 'render-number-line
                  #:length 4
                  #:stroke-width 1)
     (point-marker #:id 'render-marker
                   #:shape 'diamond
                   #:size 2
                   #:fill #f
                   #:stroke-width 1)))

  (for ([visual (in-list renderer-cases)])
    (define width-only-scene
      (scene-play
       (scene-add (make-scene #:camera camera) visual)
       (stroke-width-to (visual-id visual) 8)
       #:duration 1))
    (check-false
     (equal? (scene-time->argb-bytes width-only-scene 0)
             (scene-time->argb-bytes width-only-scene 1))
     (format "default renderer ignored stroke width for ~a"
             (visual-id visual))))

  ;; Semantic width zero is not structural stroke removal. In racket/draw, a
  ;; zero-width pen is a device-dependent hairline, so the default bitmap backend
  ;; still draws it when the stroke style is present.
  (define hairline-scene
    (scene-add
     (make-scene #:camera camera)
     (line (vec2 -3 0) (vec2 3 0)
           #:id 'hairline
           #:stroke "black"
           #:stroke-width 0)))
  (define no-stroke-scene
    (scene-add
     (make-scene #:camera camera)
     (line (vec2 -3 0) (vec2 3 0)
           #:id 'no-stroke
           #:stroke #f
           #:stroke-width 0)))
  (check-false
   (equal? (scene-time->argb-bytes hairline-scene 0)
           (scene-time->argb-bytes no-stroke-scene 0)))

  ;; The semantic model permits wider values for alternate/custom renderers, but
  ;; the default Pict/racket/draw backend supports pen widths only through 255.
  (check-not-exn
   (lambda ()
     (visual->pict
      (circle #:id 'maximum-default-stroke
              #:radius 1
              #:fill #f
              #:stroke-width 255)
      camera)))
  (define oversized-stroke
    (circle #:id 'oversized-stroke
            #:radius 1
            #:fill #f
            #:stroke-width 300))
  (struct wide-stroke-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (circle-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       (blank 10 10))])
  (check-not-exn
   (lambda ()
     (visual->pict oversized-stroke
                   camera
                   #:renderers (list (wide-stroke-renderer)))))
  (check-exn
   (lambda (value)
     (and (exn:fail? value)
          (regexp-match? #rx"0 through 255 pixels" (exn-message value))))
   (lambda ()
     (visual->pict oversized-stroke camera)))

  ;; Repeated filesystem rendering remains byte-for-byte deterministic.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-as-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define first-paths
        (render-frames! scene temporary-directory #:fps 2))
      (define first-pass
        (for/list ([path (in-list first-paths)])
          (file->bytes path)))
      (define second-paths
        (render-frames! scene temporary-directory #:fps 2))
      (check-equal?
       first-pass
       (for/list ([path (in-list second-paths)])
         (file->bytes path))))
    (lambda ()
      (delete-directory/files temporary-directory))))
