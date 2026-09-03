#lang racket/base

;;;
;;; Affine-degeneracy gallery regression coverage
;;;

;; The gallery exercises shapes that currently use the generic Pict affine
;; renderer, plus SVG and the formula slot (which falls back to Pict text if
;; the optional LaTeX renderer is not available).  Rendering the start,
;; near-singular, singular, and endpoint samples guards against crashes while
;; the gallery video makes the remaining visual policy visible for review.

(require racket/class
         rackunit
         (only-in racket/draw bitmap%)
         (prefix-in gallery: "../examples/affine-degeneracy-gallery.rkt")
         "../main.rkt")

;; nonwhite-pixel-bounds : bitmap% -> integer? integer? integer? integer?
;; Uses a bare white scene in the midpoint checks below, so the bounds describe
;; exactly one subject rather than the gallery's labels and guide lines.
(define (nonwhite-pixel-bounds bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define pixels (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height pixels)
  (define coordinates
    (for*/list ([y (in-range height)]
                [x (in-range width)]
                #:when
                (let ([offset (* 4 (+ x (* y width)))])
                  (not (and (= (bytes-ref pixels (+ offset 1)) 255)
                            (= (bytes-ref pixels (+ offset 2)) 255)
                            (= (bytes-ref pixels (+ offset 3)) 255)))))
      (cons x y)))
  (values (apply min (map car coordinates))
          (apply max (map car coordinates))
          (apply min (map cdr coordinates))
          (apply max (map cdr coordinates))))

(define (bitmap-has-nonwhite-pixel? bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define pixels (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height pixels)
  (for/or ([offset (in-range 0 (bytes-length pixels) 4)])
    (not (and (= (bytes-ref pixels (+ offset 1)) 255)
              (= (bytes-ref pixels (+ offset 2)) 255)
              (= (bytes-ref pixels (+ offset 3)) 255)))))

;; A vertical reflection interpolates through the rank-one map [0 0; 0 1].
(define (vertical-reflection-scene visual camera)
  (scene-play
   (scene-add (make-scene #:camera camera) visual)
   (apply-matrix (visual-id visual)
                 (linear2 -1 0
                          0 1))
   #:duration 2))

;; Geometry-backed subjects must remain visible as a narrow vertical image at
;; that instant; Pict-space affine transforms previously made them vanish.
(define (rank-one-bounds visual camera)
  (define reflected (vertical-reflection-scene visual camera))
  (nonwhite-pixel-bounds
   (scene-frame->bitmap reflected 1 #:fps 1 #:camera camera)))

(define (check-rank-one-vertical-image name visual camera
                                       minimum-height minimum-width maximum-width)
  (define-values (minimum-x maximum-x minimum-y maximum-y)
    (rank-one-bounds visual camera))
  (check-true (<= minimum-width (- maximum-x minimum-x) maximum-width) name)
  (check-true (>= (- maximum-y minimum-y) minimum-height) name))

(module+ test
  (define midpoint-camera
    (make-camera #:width 400 #:height 400 #:world-width 4
                 #:center origin #:background "white"))
  ;; Every primitive below is vertically centred at the origin.  At the
  ;; midpoint it must occupy only a few pixels in x while retaining its
  ;; original y span.  The lower bounds deliberately allow cosmetic strokes
  ;; and arrowhead insets to vary by a pixel or two across drawing backends.
  (check-rank-one-vertical-image
   "circle midpoint"
   (circle #:id 'circle #:radius 3/5 #:fill "lightskyblue" #:stroke "steelblue")
   midpoint-camera 116 0 4)
  (check-rank-one-vertical-image
   "rectangle midpoint"
   (rectangle #:id 'rectangle #:width 7/5 #:height 6/5
              #:fill "gold" #:stroke "goldenrod")
   midpoint-camera 116 0 4)
  (check-rank-one-vertical-image
   "arrow midpoint"
   (vector-arrow (vec2 3/5 3/5) #:start (vec2 -3/5 -3/5)
                 #:id 'arrow #:stroke "crimson")
   midpoint-camera 116 15 35)
  (check-rank-one-vertical-image
   "axes midpoint"
   (axes #:id 'axes #:x-range (axis-range -1 1 1) #:y-range (axis-range -1 1 1)
         #:x-length 2 #:y-length 2 #:stroke "darkorchid")
   midpoint-camera 196 15 35)

  ;; Semantic arrowheads are redrawn for the whole affine animation.  The
  ;; frames immediately before and at the former near-singular cutover must
  ;; therefore have almost the same horizontal head extent rather than snap
  ;; from a sheared triangle to a cosmetic one.
  (define boundary-arrow-scene
    (vertical-reflection-scene
     (vector-arrow (vec2 3/5 3/5) #:start (vec2 -3/5 -3/5)
                   #:id 'boundary-arrow #:stroke "crimson")
     midpoint-camera))
  (define (frame-nonwhite-width frame-index)
    (define-values (minimum-x maximum-x _minimum-y _maximum-y)
      (nonwhite-pixel-bounds
       (scene-frame->bitmap boundary-arrow-scene frame-index
                            #:fps 30 #:camera midpoint-camera)))
    (- maximum-x minimum-x))
  (check-true
   (<= (abs (- (frame-nonwhite-width 29)
               (frame-nonwhite-width 30)))
       3)
   "arrowhead stays continuous at the former cutover")

  ;; Text represents the Pict-only class shared by bitmap images, imported SVG
  ;; with unsupported geometry, and formula Picts.  Such material has no
  ;; meaningful rank-one outline, so it fades away rather than leaving a
  ;; malformed thin remnant.
  (define text-reflection
    (scene-play
     (scene-add
      (make-scene #:camera midpoint-camera)
      (plain-text "Pict-only" #:id 'pict-text #:font-size 1/2 #:color "black"))
     (apply-matrix 'pict-text
                   (linear2 -1 0
                            0 1))
     #:duration 2))
  (check-true
   (bitmap-has-nonwhite-pixel?
    (scene-frame->bitmap text-reflection 0 #:fps 1 #:camera midpoint-camera))
   "Pict-only text starts visible")
  (check-false
   (bitmap-has-nonwhite-pixel?
    (scene-frame->bitmap text-reflection 1 #:fps 1 #:camera midpoint-camera))
   "Pict-only text fades completely at rank one")

  (define scene (gallery:make-demo-scene))
  (for ([id (in-list '(title explanation
                        circle rectangle arrow axes svg formula
                        circle-label rectangle-label arrow-label axes-label
                        svg-label formula-label
                        circle-bottom-guide circle-top-guide
                        rectangle-bottom-guide rectangle-top-guide
                        arrow-bottom-guide arrow-top-guide
                        axes-bottom-guide axes-top-guide
                        svg-bottom-guide svg-top-guide
                        formula-bottom-guide formula-top-guide))])
    (check-not-false (scene-visual-at scene id 0) (symbol->string id)))

  ;; The reflection lasts three seconds.  These samples include the exact
  ;; rank-one midpoint at frame 45 and both thin neighbouring intervals.
  (for ([frame-index (in-list '(0 30 44 45 46 60 90))])
    (define bitmap
      (scene-frame->bitmap scene frame-index #:fps 30))
    (define frame-label (number->string frame-index))
    (check-true (is-a? bitmap bitmap%) frame-label)
    (check-equal? (send bitmap get-width) 1280 frame-label)
    (check-equal? (send bitmap get-height) 720 frame-label)))
