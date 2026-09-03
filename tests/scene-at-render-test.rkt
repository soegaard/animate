#lang racket/base

;;;
;;; SCENE-AT Color Rendering Tests
;;;

(require racket/class
         racket/file
         rackunit
         (only-in pict pict->bitmap)
         "../main.rkt")

(module+ test
  (define (bitmap->argb-bytes bitmap)
    (define width (send bitmap get-width))
    (define height (send bitmap get-height))
    (define pixels (make-bytes (* width height 4)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    pixels)

  (define camera
    (make-camera #:width 320
                 #:height 180
                 #:world-width 12
                 #:background "white"))

  (define (scene-time->argb-bytes scene time)
    (bitmap->argb-bytes
     (pict->bitmap (scene->pict scene time) 'aligned)))
  (define (bitmap-rgb-at bitmap x y)
    (define width (send bitmap get-width))
    (define pixels (bitmap->argb-bytes bitmap))
    (define offset (* 4 (+ x (* y width))))
    (list (bytes-ref pixels (+ offset 1))
          (bytes-ref pixels (+ offset 2))
          (bytes-ref pixels (+ offset 3))))
  (define disk
    (circle #:id 'disk
            #:radius 1
            #:fill "red"
            #:stroke "black"
            #:stroke-width 4))
  (define scene
    (scene-play
     (scene-add (make-scene #:camera camera) disk)
     (animation-group
      (fill-color-to disk "blue")
      (stroke-color-to disk "gold")
      (move-to disk (vec2 3 0)))
     #:duration 2))

  ;; Renderer dimensions remain stable while semantic RGBA values change.
  (for ([frame-index (in-range (scene-frame-count scene #:fps 2))])
    (define bitmap (scene-frame->bitmap scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 320)
    (check-equal? (send bitmap get-height) 180))
  (check-equal? (visual-fill-color
                 (scene-state-ref (scene-sample scene 1) 'disk))
                (rgba-color 255/2 0 255/2 1))
  (check-equal? (visual-stroke-color
                 (scene-state-ref (scene-sample scene 1) 'disk))
                (rgba-color 255/2 215/2 0 1))
  (check-equal? (visual-fill-color
                 (scene-state-ref (scene-sample scene 2) 'disk))
                "blue")

  (define sampled-bytes
    (for/list ([frame-index (in-range 4)])
      (bitmap->argb-bytes
       (scene-frame->bitmap scene frame-index #:fps 2))))
  (for ([left-bytes (in-list sampled-bytes)]
        [right-bytes (in-list (cdr sampled-bytes))])
    (check-false (equal? left-bytes right-bytes)))

  ;; Every built-in color-protocol rendering path is checked independently so a
  ;; working adapter for one Visual cannot mask another adapter that ignores the
  ;; sampled semantic color.
  (define renderer-cases
    (list
     (list (circle #:id 'circle-fill
                   #:radius 1 #:fill "red" #:stroke #f)
           (lambda () (fill-color-to 'circle-fill "blue")))
     (list (circle #:id 'circle-stroke
                   #:radius 1 #:fill #f #:stroke "black" #:stroke-width 6)
           (lambda () (stroke-color-to 'circle-stroke "red")))
     (list (rectangle #:id 'rectangle-fill
                      #:width 3 #:height 2 #:fill "red" #:stroke #f)
           (lambda () (fill-color-to 'rectangle-fill "blue")))
     (list (rectangle #:id 'rectangle-stroke
                      #:width 3 #:height 2 #:fill #f #:stroke "black"
                      #:stroke-width 6)
           (lambda () (stroke-color-to 'rectangle-stroke "red")))
     (list (polygon (list (vec2 -1 -1) (vec2 1 -1)
                          (vec2 1 1) (vec2 -1 1))
                    #:id 'path-fill #:fill "red" #:stroke #f)
           (lambda () (fill-color-to 'path-fill "blue")))
     (list (line (vec2 -2 0) (vec2 2 0)
                 #:id 'path-stroke #:stroke "black" #:stroke-width 6)
           (lambda () (stroke-color-to 'path-stroke "red")))
     (list (arrow (vec2 -2 0) (vec2 2 0)
                  #:id 'arrow-stroke #:stroke "black" #:stroke-width 6)
           (lambda () (stroke-color-to 'arrow-stroke "red")))
     (list (axes #:id 'axes-stroke
                 #:x-range (axis-range -1 1 1)
                 #:y-range (axis-range -1 1 1)
                 #:x-length 4 #:y-length 4
                 #:stroke "black" #:stroke-width 5)
           (lambda () (stroke-color-to 'axes-stroke "red")))
     (list (number-line (axis-range -1 1 1)
                        #:id 'number-line-stroke
                        #:length 4 #:stroke "black" #:stroke-width 5)
           (lambda () (stroke-color-to 'number-line-stroke "red")))
     (list (point-marker #:id 'marker-fill
                         #:shape 'diamond #:size 2
                         #:fill "red" #:stroke #f)
           (lambda () (fill-color-to 'marker-fill "blue")))
     (list (point-marker #:id 'marker-stroke
                         #:shape 'diamond #:size 2
                         #:fill #f #:stroke "black" #:stroke-width 5)
           (lambda () (stroke-color-to 'marker-stroke "red")))))

  (for ([renderer-case (in-list renderer-cases)])
    (define visual (car renderer-case))
    (define request ((cadr renderer-case)))
    (define color-only-scene
      (scene-play
       (scene-add (make-scene #:camera camera) visual)
       request
       #:duration 1))
    (check-false
     (equal? (scene-time->argb-bytes color-only-scene 0)
             (scene-time->argb-bytes color-only-scene 1))
     (format "default renderer ignored semantic color for ~a"
             (visual-id visual))))

  ;; `#:fill #f` is an actual transparent interior, rather than the black
  ;; fallback used by Pict's filled-shape constructors. Check both built-in
  ;; closed shapes at their centres, well away from their strokes.
  (for ([unfilled
         (list (circle #:id 'transparent-circle #:radius 1
                       #:fill #f #:stroke "black" #:stroke-width 4)
               (rectangle #:id 'transparent-rectangle #:width 2 #:height 2
                          #:fill #f #:stroke "black" #:stroke-width 4))])
    (define bitmap
      (pict->bitmap
       (scene->pict
        (scene-add (make-scene #:camera camera) unfilled)
        0)
       'aligned))
    (check-equal? (bitmap-rgb-at bitmap 160 90)
                  '(255 255 255)
                  (format "~a filled its transparent interior"
                          (visual-id unfilled))))

  ;; Alpha-bearing semantic colors reach racket/draw only at adapter conversion.
  (define alpha-scene
    (scene-play
     (scene-add
      (make-scene #:camera camera)
      (rectangle #:id 'alpha-box
                 #:width 4
                 #:height 3
                 #:fill (rgba-color 255 0 0 1)
                 #:stroke #f))
     (fill-color-to 'alpha-box (rgba-color 0 0 255 1/4))
     #:duration 1))
  (check-false
   (equal? (bitmap->argb-bytes (scene-frame->bitmap alpha-scene 0 #:fps 2))
           (bitmap->argb-bytes (scene-frame->bitmap alpha-scene 1 #:fps 2))))

  ;; Textual transparent remains renderable at the exact endpoint even though
  ;; the semantic sampler deliberately preserves the caller's original string.
  (define transparent-scene
    (scene-play
     (scene-add
      (make-scene #:camera camera)
      (circle #:id 'transparent-disk
              #:fill "red"
              #:stroke #f))
     (fill-color-to 'transparent-disk "transparent")
     #:duration 1))
  (check-equal?
   (visual-fill-color
    (scene-state-ref (scene-sample transparent-scene 1) 'transparent-disk))
   "transparent")
  (check-equal?
   (send (pict->bitmap (scene->pict transparent-scene 1) 'aligned) get-width)
   320)

  ;; Repeated filesystem rendering remains byte-for-byte deterministic.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-at-~a" 'directory))
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
