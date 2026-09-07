#lang racket/base

;;;
;;; Per-frame Billboard Preparation and Software Rasterization
;;;

;; This module deliberately parallels marker-raster3d: semantic billboards
;; retain only an image and an anchor, while this boundary resolves all camera
;; dependent corners and depth policy.  The OpenGL pass consumes the same
;; prepared vertices, so software and hardware cannot diverge on facing,
;; dimensions, visibility, or depth semantics.

(require racket/list
         "../geometry.rkt"
         "affine3.rkt"
         "billboard3d.rkt"
         "camera3d.rkt"
         "clipping3d.rkt"
         "raster-target3d.rkt"
         "vec3.rkt")

(provide (struct-out prepared-billboard-vertex3d)
         (struct-out prepared-billboard3d)
         prepare-billboard3d
         rasterize-prepared-billboards!)

(struct prepared-billboard-vertex3d (x y depth u v world) #:transparent)
(struct prepared-billboard3d (path vertices image opacity style drawing-index world-position)
  #:transparent)

(define (prepare-billboard3d path position transform image style inherited-opacity
                             clip-planes camera aspect width height drawing-index)
  (define center (affine3-apply-point transform position))
  (cond
    [(not (point-kept-by-clips? center clip-planes)) #f]
    [(eq? (billboard-style3d-size-mode style) 'screen)
     (define projected (camera3d-project camera center #:aspect aspect))
     (and projected
          (let* ([screen (ndc->screen projected width height)]
                 [pixel-width (billboard-style3d-width style)]
                 [pixel-height (resolved-height style image)]
                 [half-width (/ pixel-width 2)]
                 [half-height (/ pixel-height 2)]
                 [depth (camera3d-view-depth camera center)])
            (prepared-billboard3d
             path
             (list (prepared-billboard-vertex3d (- (car screen) half-width)
                                                (- (cdr screen) half-height) depth 0 0 center)
                   (prepared-billboard-vertex3d (+ (car screen) half-width)
                                                (- (cdr screen) half-height) depth 1 0 center)
                   (prepared-billboard-vertex3d (+ (car screen) half-width)
                                                (+ (cdr screen) half-height) depth 1 1 center)
                   (prepared-billboard-vertex3d (- (car screen) half-width)
                                                (+ (cdr screen) half-height) depth 0 1 center))
             image (* inherited-opacity (billboard-style3d-opacity style)) style
             drawing-index center)))]
    [else
     (define-values (right up)
       (world-billboard-basis center transform style camera))
     (define half-width (/ (billboard-style3d-width style) 2))
     (define half-height (/ (resolved-height style image) 2))
     (define corners
       (list (vec3- (vec3- center (vec3-scale half-width right)) (vec3-scale half-height up))
             (vec3+ (vec3- center (vec3-scale half-height up)) (vec3-scale half-width right))
             (vec3+ (vec3+ center (vec3-scale half-width right)) (vec3-scale half-height up))
             (vec3- (vec3+ center (vec3-scale half-height up)) (vec3-scale half-width right))))
     (define uv (list (cons 0 0) (cons 1 0) (cons 1 1) (cons 0 1)))
     (define vertices
       (for/list ([corner (in-list corners)] [tex (in-list uv)])
         (define projected (camera3d-project camera corner #:aspect aspect))
         (and projected
              (let ([screen (ndc->screen projected width height)])
                (prepared-billboard-vertex3d
                 (car screen) (cdr screen) (camera3d-view-depth camera corner)
                 (car tex) (cdr tex) corner)))))
     ;; Conservative all-corners frustum policy is intentional: it avoids
     ;; silently stretching an image over a clipped camera plane. A later
     ;; clipped-quad path can refine this without changing author values.
     (and (andmap values vertices)
          (prepared-billboard3d path vertices image
                                (* inherited-opacity (billboard-style3d-opacity style))
                                style drawing-index center))]))

(define (resolved-height style image)
  (or (billboard-style3d-height style)
      (* (billboard-style3d-width style)
         (/ (billboard-image3d-height image) (billboard-image3d-width image)))))

(define (world-billboard-basis center transform style camera)
  ;; A camera-facing billboard uses the image-plane axes. For axis-facing
  ;; signs, preserve the declared upright axis and face the camera only in its
  ;; perpendicular plane.  Transforming the authored axis preserves normal
  ;; spatial group orientation without introducing a camera-dependent scene
  ;; transform.
  (define (unit vector fallback)
    (if (positive? (vec3-length vector)) (vec3-normalize vector) fallback))
  (case (billboard-style3d-facing style)
    [(camera)
     (values (unit (camera3d-right camera) x-axis3)
             (unit (camera3d-up camera) y-axis3))]
    [(axis)
     (define axis
       (unit (affine3-apply-vector transform (billboard-style3d-axis style)) y-axis3))
     (define toward-camera (vec3- (camera3d-position camera) center))
     (define perpendicular
       (vec3- toward-camera (vec3-scale (vec3-dot toward-camera axis) axis)))
     ;; Looking exactly down the selected axis leaves orientation underdefined.
     ;; The camera's right vector gives a deterministic, still upright fallback.
     (define normal
       (unit perpendicular (camera3d-right camera)))
     (values (unit (vec3-cross axis normal) (camera3d-right camera)) axis)]))

(define (point-kept-by-clips? point clips)
  (for/and ([clip (in-list clips)])
    (define sign (if (eq? (clip-plane3d-keep clip) 'positive) 1 -1))
    (>= (* sign (plane-signed-distance (clip-plane3d-plane clip) point)) 0)))

(define (ndc->screen point width height)
  (cons (* width (/ (+ (vec2-x point) 1) 2))
        (* height (/ (- 1 (vec2-y point)) 2))))

(define (rasterize-prepared-billboards! target billboards pass)
  (for/sum ([billboard (in-list billboards)]
            #:when (eq? (billboard-style3d-depth-mode
                          (prepared-billboard3d-style billboard))
                         pass))
    (define vertices (prepared-billboard3d-vertices billboard))
    (+ (rasterize-billboard-triangle! target billboard
                                      (first vertices) (second vertices) (third vertices))
       (rasterize-billboard-triangle! target billboard
                                      (first vertices) (third vertices) (fourth vertices)))))

(define (rasterize-billboard-triangle! target billboard first second third)
  (define left (max 0 (inexact->exact (floor (min (prepared-billboard-vertex3d-x first)
                                               (prepared-billboard-vertex3d-x second)
                                               (prepared-billboard-vertex3d-x third))))))
  (define right (min (sub1 (raster-target3d-width target))
                     (inexact->exact (ceiling (max (prepared-billboard-vertex3d-x first)
                                                 (prepared-billboard-vertex3d-x second)
                                                 (prepared-billboard-vertex3d-x third))))))
  (define top (max 0 (inexact->exact (floor (min (prepared-billboard-vertex3d-y first)
                                              (prepared-billboard-vertex3d-y second)
                                              (prepared-billboard-vertex3d-y third))))))
  (define bottom (min (sub1 (raster-target3d-height target))
                      (inexact->exact (ceiling (max (prepared-billboard-vertex3d-y first)
                                                  (prepared-billboard-vertex3d-y second)
                                                  (prepared-billboard-vertex3d-y third))))))
  (define denominator
    (edge-value first second (prepared-billboard-vertex3d-x third)
                (prepared-billboard-vertex3d-y third)))
  (if (zero? denominator)
      0
      (for*/fold ([written 0]) ([pixel-y (in-range top (add1 bottom))]
                               [pixel-x (in-range left (add1 right))])
        (define sample-x (+ pixel-x 1/2))
        (define sample-y (+ pixel-y 1/2))
        (define weight-first (/ (edge-value second third sample-x sample-y) denominator))
        (define weight-second (/ (edge-value third first sample-x sample-y) denominator))
        (define weight-third (- 1 weight-first weight-second))
        (if (and (>= weight-first 0) (>= weight-second 0) (>= weight-third 0))
            (let* ([u (+ (* weight-first (prepared-billboard-vertex3d-u first))
                         (* weight-second (prepared-billboard-vertex3d-u second))
                         (* weight-third (prepared-billboard-vertex3d-u third)))]
                   [v (+ (* weight-first (prepared-billboard-vertex3d-v first))
                         (* weight-second (prepared-billboard-vertex3d-v second))
                         (* weight-third (prepared-billboard-vertex3d-v third)))]
                   [depth (+ (* weight-first (prepared-billboard-vertex3d-depth first))
                             (* weight-second (prepared-billboard-vertex3d-depth second))
                             (* weight-third (prepared-billboard-vertex3d-depth third)))]
                   [color (sample-billboard-color billboard u v)]
                   [style (prepared-billboard3d-style billboard)])
              (if (and (positive? (vector-ref color 3))
                       (depth-accepts? (billboard-style3d-depth-mode style)
                                       (billboard-style3d-depth-bias style) depth
                                       (target-depth target pixel-x pixel-y)))
                  (begin (blend-argb! target pixel-x pixel-y color) (add1 written))
                  written))
            written))))

(define (edge-value first second x y)
  (- (* (- (prepared-billboard-vertex3d-x second)
           (prepared-billboard-vertex3d-x first))
        (- y (prepared-billboard-vertex3d-y first)))
     (* (- (prepared-billboard-vertex3d-y second)
           (prepared-billboard-vertex3d-y first))
        (- x (prepared-billboard-vertex3d-x first)))))

;; Returns straight RGBA bytes as a compact vector. Texture coordinates retain
;; the source's conventional top-left origin, matching both Racket ARGB and
;; the texture upload conversion used by the OpenGL pass.
(define (sample-billboard-color billboard u v)
  (define image (prepared-billboard3d-image billboard))
  (define x (min (sub1 (billboard-image3d-width image))
                 (max 0 (inexact->exact (floor (* u (billboard-image3d-width image)))))))
  (define y (min (sub1 (billboard-image3d-height image))
                 (max 0 (inexact->exact (floor (* v (billboard-image3d-height image)))))))
  (define offset (* 4 (+ x (* y (billboard-image3d-width image)))) )
  (define argb (billboard-image3d-argb image))
  (define opacity (prepared-billboard3d-opacity billboard))
  (vector (bytes-ref argb (add1 offset))
          (bytes-ref argb (+ offset 2))
          (bytes-ref argb (+ offset 3))
          (* opacity (/ (bytes-ref argb offset) 255.0))))

(define (depth-accepts? mode bias depth old-depth)
  (case mode
    [(always) #t]
    [(test) (<= (- depth bias) old-depth)]
    [(hidden) (and (not (eqv? old-depth +inf.0)) (> (+ depth bias) old-depth))]))

(define (target-depth target x y)
  (vector-ref (raster-target3d-depth-values target)
              (+ x (* y (raster-target3d-width target)))))

(define (blend-argb! target x y color)
  (define bytes (raster-target3d-color-bytes target))
  (define index (* 4 (+ x (* y (raster-target3d-width target)))))
  (define alpha (vector-ref color 3))
  (define old-alpha (/ (bytes-ref bytes index) 255.0))
  (define out-alpha (+ alpha (* (- 1 alpha) old-alpha)))
  (define (channel channel old-index)
    (if (zero? out-alpha) 0
        (/ (+ (* alpha channel) (* (- 1 alpha) old-alpha (bytes-ref bytes old-index)))
           out-alpha)))
  (bytes-set! bytes index (to-byte (* 255 out-alpha)))
  (bytes-set! bytes (add1 index) (to-byte (channel (vector-ref color 0) (add1 index))))
  (bytes-set! bytes (+ index 2) (to-byte (channel (vector-ref color 1) (+ index 2))))
  (bytes-set! bytes (+ index 3) (to-byte (channel (vector-ref color 2) (+ index 3)))))

(define (to-byte value) (inexact->exact (round (max 0 (min 255 value)))))
