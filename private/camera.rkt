#lang racket/base

;;;
;;; Camera Model
;;;

;; Defines immutable orthographic camera values used by the renderer.
;;
;; World coordinates have positive y upward. Pixel coordinates have positive y
;; downward. This module performs only deterministic coordinate conversion.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "geometry.rkt")

;; Exports
(provide camera?
         camera-width
         camera-height
         camera-world-width
         camera-center
         camera-background
         make-camera
         default-camera
         camera-scale
         camera-world-height
         camera-length->pixels
         camera-world->pixel
         camera-pixel->world)


;;;
;;; Data Representation
;;;

(struct camera (width height world-width center background)
  #:transparent)

;; camera represents one immutable orthographic view of a scene.
;;  - width        exact-positive-integer?  output width in pixels.
;;  - height       exact-positive-integer?  output height in pixels.
;;  - world-width  positive finite real?    visible width in world units.
;;  - center       vec2?                    world point at the frame center.
;;  - background   any/c                    opaque style interpreted by a renderer.


;;;
;;; Construction
;;;

; make-camera : [#:width exact-positive-integer?]
;               [#:height exact-positive-integer?]
;               [#:world-width positive-real?]
;               [#:center vec2?]
;               [#:background any/c]
;               -> camera?
;;   Creates an immutable orthographic camera value.
(define (make-camera #:width [width 1280]
                     #:height [height 720]
                     #:world-width [world-width 14]
                     #:center [center origin]
                     #:background [background "white"])
  (unless (exact-positive-integer? width)
    (raise-argument-error 'make-camera "exact-positive-integer?" width))
  (unless (exact-positive-integer? height)
    (raise-argument-error 'make-camera "exact-positive-integer?" height))
  (unless (and (finite-real? world-width)
               (positive? world-width))
    (raise-argument-error
     'make-camera
     "positive finite real?"
     world-width))
  (unless (vec2? center)
    (raise-argument-error 'make-camera "vec2?" center))
  (camera width height world-width center background))

; default-camera : camera?
;;   Gives the default 1280 by 720 camera.
(define default-camera
  (make-camera))


;;;
;;; Coordinate Conversion
;;;

; camera-scale : camera? -> positive-real?
;;   Returns the number of pixels per world unit.
(define (camera-scale camera)
  (/ (camera-width camera)
     (camera-world-width camera)))

; camera-world-height : camera? -> positive-real?
;;   Returns the visible frame height in world units.
(define (camera-world-height camera)
  (/ (camera-height camera)
     (camera-scale camera)))

; camera-length->pixels : camera? finite-real? -> real?
;;   Converts a world-space length to a pixel-space length.
(define (camera-length->pixels camera length)
  (unless (camera? camera)
    (raise-argument-error 'camera-length->pixels "camera?" camera))
  (unless (finite-real? length)
    (raise-argument-error
     'camera-length->pixels
     "finite real?"
     length))
  (* (camera-scale camera) length))

; camera-world->pixel : camera? vec2? -> (values real? real?)
;;   Converts a world point to pixel coordinates.
(define (camera-world->pixel camera point)
  (unless (camera? camera)
    (raise-argument-error 'camera-world->pixel "camera?" camera))
  (unless (vec2? point)
    (raise-argument-error 'camera-world->pixel "vec2?" point))
  (define scale
    (camera-scale camera))
  (define center
    (camera-center camera))
  (values
   (+ (/ (camera-width camera) 2)
      (* scale (- (vec2-x point) (vec2-x center))))
   (- (/ (camera-height camera) 2)
      (* scale (- (vec2-y point) (vec2-y center))))))

; camera-pixel->world : camera? real? real? -> vec2?
;; Inverts camera-world->pixel exactly in the same pixel coordinate convention:
;; origin at the upper-left and positive pixel y downward. This belongs in the
;; pure camera model so hit testing can be renderer-independent.
(define (camera-pixel->world camera pixel-x pixel-y)
  (unless (camera? camera)
    (raise-argument-error 'camera-pixel->world "camera?" camera))
  (unless (finite-real? pixel-x)
    (raise-argument-error 'camera-pixel->world "finite real?" pixel-x))
  (unless (finite-real? pixel-y)
    (raise-argument-error 'camera-pixel->world "finite real?" pixel-y))
  (define scale (camera-scale camera))
  (define center (camera-center camera))
  (vec2 (+ (vec2-x center)
           (/ (- pixel-x (/ (camera-width camera) 2)) scale))
        (- (vec2-y center)
           (/ (- pixel-y (/ (camera-height camera) 2)) scale))))
