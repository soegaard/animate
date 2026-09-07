#lang racket/base

;;; SCENE-3D-S: Depth-tested Textured Billboards

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

;; A tiny immutable ARGB texture is sufficient to make orientation, alpha, and
;; depth behavior visible without importing a GUI bitmap into the semantic
;; scene. The transparent border also shows that alpha pixels do not form an
;; opaque rectangular card.
(define (badge-image)
  (define width 20)
  (define height 14)
  (define pixels (make-bytes (* 4 width height) 0))
  (for* ([y (in-range 2 (- height 2))]
         [x (in-range 2 (- width 2))])
    (define index (* 4 (+ x (* y width))))
    (bytes-set! pixels index 235)
    (bytes-set! pixels (add1 index) (if (< x 10) 244 40))
    (bytes-set! pixels (+ index 2) (if (< x 10) 188 128))
    (bytes-set! pixels (+ index 3) (if (< x 10) 50 220)))
  (billboard-image3d width height pixels))

(define (make-world)
  (define texture (badge-image))
  (view3d
   (list
    (cube3d 2 #:id 'cube
            #:material (material3d #:color "slateblue" #:shading 'smooth))
    ;; This badge always occupies 54 output pixels, but its transparent pixels
    ;; and opaque pixels both still observe the cube's depth buffer.
    (billboard3d texture (vec3 -3/4 3/4 6/5) #:id 'screen-badge
                 #:style (billboard-style3d #:width 54 #:size-mode 'screen
                                            #:depth-mode 'test))
    ;; The upright sign is a true world plane: it turns around y as the camera
    ;; orbits, preserving its world height rather than its pixel height.
    (billboard3d texture (vec3 0 0 -6/5) #:id 'upright-sign
                 #:style (billboard-style3d #:width 3/2 #:size-mode 'world
                                            #:facing 'axis #:axis y-axis3
                                            #:depth-mode 'test)))
   #:id 'world #:center (vec2 0 -1/4) #:width 6 #:height 9/2
   #:background "aliceblue" #:render-mode 'opaque
   #:camera (perspective-camera3d #:position (vec3 4 3 7) #:look-at origin3
                                  #:vertical-field-of-view (/ pi 5))))

(define (make-demo-scene)
  (scene-play
   (scene-add
    (make-scene) (make-world)
    (plain-text "SCENE-3D-S: depth-tested textured billboards"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "The badge keeps screen size; the sign stays upright in world space. Both use the depth buffer."
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:azimuth (* 3/2 pi) #:elevation (/ pi 18))
   #:duration 4))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "textured-billboards.rkt"
                #:args ([directory "frames"] [video #f])
                (set! output-directory directory)
                (set! output-video video))
  (render-frames! (make-demo-scene) output-directory #:fps 30)
  (when output-video (encode-mp4! output-directory output-video #:fps 30)))
