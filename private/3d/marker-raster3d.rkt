#lang racket/base

;;;
;;; Screen Marker Preparation and Rasterization
;;;

(require racket/list
         racket/math
         "../color-style.rkt"
         "../geometry.rkt"
         "affine3.rkt"
         "camera3d.rkt"
         "clipping3d.rkt"
         "marker3d.rkt"
         "raster-target3d.rkt"
         "vec3.rkt")

(provide (struct-out prepared-point-marker3d)
         (struct-out prepared-arrow-marker3d)
         prepare-point-marker3d
         prepare-arrow-marker3d
         rasterize-prepared-point-markers!
         rasterize-prepared-arrow-markers!)

(struct prepared-point-marker3d
  (path x y depth radius color style drawing-index world-position)
  #:transparent)

(struct prepared-arrow-marker3d
  (path tip-x tip-y depth base-x base-y half-width color style drawing-index tip-world)
  #:transparent)

(define (prepare-point-marker3d path position transform style inherited-opacity
                                clip-planes camera aspect width height drawing-index)
  (define world-position (affine3-apply-point transform position))
  (define view-position (camera3d-world->view camera world-position))
  (define projected (camera3d-project-view camera view-position #:aspect aspect))
  (and (point-kept-by-clips? world-position clip-planes)
       projected
       (let ([screen (ndc->screen projected width height)])
         (prepared-point-marker3d
          path (car screen) (cdr screen) (- (vec3-z view-position))
          (point-radius-pixels style world-position camera aspect width height)
          (resolve-color (point-style3d-color style)
                         (* inherited-opacity (point-style3d-opacity style)))
          style drawing-index world-position))))

(define (prepare-arrow-marker3d path from to transform style inherited-opacity
                                clip-planes camera aspect width height drawing-index)
  (define first-world (affine3-apply-point transform from))
  (define second-world (affine3-apply-point transform to))
  (define clipped (clip-world-marker-segment camera first-world second-world clip-planes))
  (define first-visible-world (and clipped (first clipped)))
  (define second-visible-world (and clipped (second clipped)))
  (define first-view (and first-visible-world (camera3d-world->view camera first-visible-world)))
  (define second-view (and second-visible-world (camera3d-world->view camera second-visible-world)))
  (define first-projected (and first-view (camera3d-project-view camera first-view #:aspect aspect)))
  (define second-projected (and second-view (camera3d-project-view camera second-view #:aspect aspect)))
  (and first-projected second-projected
       (let* ([first-screen (ndc->screen first-projected width height)]
              [second-screen (ndc->screen second-projected width height)]
              [dx (- (car second-screen) (car first-screen))]
              [dy (- (cdr second-screen) (cdr first-screen))]
              [length (sqrt (+ (* dx dx) (* dy dy)))])
         (and (> length 1e-8)
              (let* ([head-length (arrow-length-pixels style first-visible-world second-visible-world camera aspect width height)]
                     [unit-x (/ dx length)]
                     [unit-y (/ dy length)]
                     [base-x (- (car second-screen) (* head-length unit-x))]
                     [base-y (- (cdr second-screen) (* head-length unit-y))]
                     [half-width (/ (arrow-width-pixels style first-visible-world second-visible-world camera aspect width height) 2)])
                (prepared-arrow-marker3d
                 path (car second-screen) (cdr second-screen) (- (vec3-z second-view))
                 base-x base-y half-width
                 (resolve-color (arrow-style3d-color style)
                                (* inherited-opacity (arrow-style3d-opacity style)))
                 style drawing-index second-visible-world))))))

(define (point-kept-by-clips? point clips)
  (for/and ([clip (in-list clips)])
    (define sign (if (eq? (clip-plane3d-keep clip) 'positive) 1 -1))
    (>= (* sign (plane-signed-distance (clip-plane3d-plane clip) point)) 0)))

(define (clip-world-marker-segment camera first-point second-point clips)
  (let loop ([first-point first-point] [second-point second-point] [remaining clips])
    (cond [(null? remaining)
           (clip-camera-depth-segment camera first-point second-point)]
          [else
           (define result (clip-marker-segment-by-plane first-point second-point (car remaining)))
           (and result (loop (first result) (second result) (cdr remaining)))])))

(define (clip-marker-segment-by-plane first-point second-point clip)
  (define sign (if (eq? (clip-plane3d-keep clip) 'positive) 1 -1))
  (define first-distance (* sign (plane-signed-distance (clip-plane3d-plane clip) first-point)))
  (define second-distance (* sign (plane-signed-distance (clip-plane3d-plane clip) second-point)))
  (cond [(and (>= first-distance 0) (>= second-distance 0)) (list first-point second-point)]
        [(and (< first-distance 0) (< second-distance 0)) #f]
        [else
         (define t (/ first-distance (- first-distance second-distance)))
         (define crossing (vec3-lerp first-point second-point t))
         (if (>= first-distance 0)
             (list first-point crossing)
             (list crossing second-point))]))

(define (clip-camera-depth-segment camera first-point second-point)
  (define first-depth (camera3d-view-depth camera first-point))
  (define second-depth (camera3d-view-depth camera second-point))
  (define direction (- second-depth first-depth))
  (cond [(zero? direction)
         (and (<= (camera3d-near camera) first-depth (camera3d-far camera))
              (list first-point second-point))]
        [else
         (define lower (/ (- (camera3d-near camera) first-depth) direction))
         (define upper (/ (- (camera3d-far camera) first-depth) direction))
         (define start (max 0 (min lower upper)))
         (define finish (min 1 (max lower upper)))
         (and (<= start finish)
              (list (vec3-lerp first-point second-point start)
                    (vec3-lerp first-point second-point finish)))]))

(define (rasterize-prepared-point-markers! target markers pass)
  (for/sum ([marker (in-list markers)]
            #:when (eq? (point-style3d-depth-mode (prepared-point-marker3d-style marker)) pass))
    (rasterize-point! target marker)))

(define (rasterize-prepared-arrow-markers! target markers pass)
  (for/sum ([marker (in-list markers)]
            #:when (eq? (arrow-style3d-depth-mode (prepared-arrow-marker3d-style marker)) pass))
    (rasterize-arrow! target marker)))

(define (rasterize-point! target marker)
  (define radius (prepared-point-marker3d-radius marker))
  (define x (prepared-point-marker3d-x marker))
  (define y (prepared-point-marker3d-y marker))
  (define left (max 0 (inexact->exact (floor (- x radius)))))
  (define right (min (sub1 (raster-target3d-width target)) (inexact->exact (ceiling (+ x radius)))))
  (define top (max 0 (inexact->exact (floor (- y radius)))))
  (define bottom (min (sub1 (raster-target3d-height target)) (inexact->exact (ceiling (+ y radius)))))
  (for*/fold ([written 0]) ([pixel-y (in-range top (add1 bottom))]
                         [pixel-x (in-range left (add1 right))])
    (define dx (- (+ pixel-x 1/2) x))
    (define dy (- (+ pixel-y 1/2) y))
    (if (and (<= (+ (* dx dx) (* dy dy)) (* radius radius))
             (marker-depth-accepts? (point-style3d-depth-mode (prepared-point-marker3d-style marker))
                                    (point-style3d-depth-bias (prepared-point-marker3d-style marker))
                                    (prepared-point-marker3d-depth marker)
                                    (target-depth target pixel-x pixel-y)))
        (begin (blend-color! target pixel-x pixel-y (prepared-point-marker3d-color marker))
               (add1 written))
        written)))

(define (rasterize-arrow! target marker)
  (define tip-x (prepared-arrow-marker3d-tip-x marker))
  (define tip-y (prepared-arrow-marker3d-tip-y marker))
  (define base-x (prepared-arrow-marker3d-base-x marker))
  (define base-y (prepared-arrow-marker3d-base-y marker))
  (define half-width (prepared-arrow-marker3d-half-width marker))
  (define dx (- tip-x base-x))
  (define dy (- tip-y base-y))
  (define length (sqrt (+ (* dx dx) (* dy dy))))
  (define normal-x (/ (- dy) length))
  (define normal-y (/ dx length))
  (define first-base (cons (+ base-x (* normal-x half-width)) (+ base-y (* normal-y half-width))))
  (define second-base (cons (- base-x (* normal-x half-width)) (- base-y (* normal-y half-width))))
  (define left (max 0 (inexact->exact (floor (min tip-x (car first-base) (car second-base))))))
  (define right (min (sub1 (raster-target3d-width target))
                     (inexact->exact (ceiling (max tip-x (car first-base) (car second-base))))))
  (define top (max 0 (inexact->exact (floor (min tip-y (cdr first-base) (cdr second-base))))))
  (define bottom (min (sub1 (raster-target3d-height target))
                      (inexact->exact (ceiling (max tip-y (cdr first-base) (cdr second-base))))))
  (for*/fold ([written 0]) ([pixel-y (in-range top (add1 bottom))]
                         [pixel-x (in-range left (add1 right))])
    (define inside?
      (point-in-triangle? (+ pixel-x 1/2) (+ pixel-y 1/2)
                          (cons tip-x tip-y) first-base second-base))
    (if (and inside?
             (marker-depth-accepts? (arrow-style3d-depth-mode (prepared-arrow-marker3d-style marker))
                                    (arrow-style3d-depth-bias (prepared-arrow-marker3d-style marker))
                                    (prepared-arrow-marker3d-depth marker)
                                    (target-depth target pixel-x pixel-y)))
        (begin (blend-color! target pixel-x pixel-y (prepared-arrow-marker3d-color marker))
               (add1 written))
        written)))

(define (point-in-triangle? x y first second third)
  (define (cross start end)
    (- (* (- (car end) (car start)) (- y (cdr start)))
       (* (- (cdr end) (cdr start)) (- x (car start)))))
  (define first-cross (cross first second))
  (define second-cross (cross second third))
  (define third-cross (cross third first))
  (or (and (>= first-cross 0) (>= second-cross 0) (>= third-cross 0))
      (and (<= first-cross 0) (<= second-cross 0) (<= third-cross 0))))

(define (marker-depth-accepts? mode bias depth old-depth)
  (case mode
    [(always) #t]
    [(test) (<= (- depth bias) old-depth)]
    [(hidden) (and (not (eqv? old-depth +inf.0)) (> (+ depth bias) old-depth))]))

(define (target-depth target x y)
  (vector-ref (raster-target3d-depth-values target)
              (+ x (* y (raster-target3d-width target)))))

(define (point-radius-pixels style point camera aspect width height)
  (if (eq? (point-style3d-size-mode style) 'screen)
      (/ (point-style3d-size style) 2)
      (/ (diameter-pixels (point-style3d-size style) point camera aspect width height) 2)))

(define (arrow-length-pixels style from to camera aspect width height)
  (if (eq? (arrow-style3d-length-mode style) 'screen)
      (arrow-style3d-length style)
      (diameter-pixels (arrow-style3d-length style) to camera aspect width height)))

(define (arrow-width-pixels style from to camera aspect width height)
  (if (eq? (arrow-style3d-length-mode style) 'screen)
      (arrow-style3d-width style)
      (diameter-pixels (arrow-style3d-width style) to camera aspect width height)))

(define (diameter-pixels diameter point camera aspect width height)
  (define half (/ diameter 2))
  (define first (camera3d-project camera (vec3- point (vec3-scale half (camera3d-right camera))) #:aspect aspect))
  (define second (camera3d-project camera (vec3+ point (vec3-scale half (camera3d-right camera))) #:aspect aspect))
  (if (and first second)
      (distance2 (ndc->screen first width height) (ndc->screen second width height))
      0))

(define (ndc->screen point width height)
  (cons (* width (/ (+ (vec2-x point) 1) 2))
        (* height (/ (- 1 (vec2-y point)) 2))))

(define (distance2 first second)
  (sqrt (+ (sqr (- (car second) (car first)))
           (sqr (- (cdr second) (cdr first))))))

(define (resolve-color source opacity)
  (define color (color-spec->rgba-color source 'marker-raster3d))
  (rgba-color (rgba-color-red color) (rgba-color-green color) (rgba-color-blue color)
              (* opacity (rgba-color-alpha color))))

(define (blend-color! target x y source)
  (define bytes (raster-target3d-color-bytes target))
  (define byte-index (* 4 (+ x (* y (raster-target3d-width target)))))
  (define alpha (rgba-color-alpha source))
  (define old-alpha (/ (bytes-ref bytes byte-index) 255.0))
  (define out-alpha (+ alpha (* (- 1 alpha) old-alpha)))
  (define (channel new old)
    (if (zero? out-alpha) 0
        (/ (+ (* alpha new) (* (- 1 alpha) old-alpha old)) out-alpha)))
  (bytes-set! bytes byte-index (to-byte (* 255 out-alpha)))
  (bytes-set! bytes (add1 byte-index)
              (to-byte (channel (rgba-color-red source) (bytes-ref bytes (add1 byte-index)))))
  (bytes-set! bytes (+ byte-index 2)
              (to-byte (channel (rgba-color-green source) (bytes-ref bytes (+ byte-index 2)))))
  (bytes-set! bytes (+ byte-index 3)
              (to-byte (channel (rgba-color-blue source) (bytes-ref bytes (+ byte-index 3))))))

(define (to-byte number)
  (inexact->exact (round (max 0 (min 255 number)))))
