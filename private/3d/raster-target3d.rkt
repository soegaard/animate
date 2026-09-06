#lang racket/base

;;; Software Raster Target

(require "../color-style.rkt")

(provide (struct-out raster-target3d)
         make-raster-target3d
         raster-target3d-clear!
         raster-target3d->argb-bytes)

;; Color is mutable ARGB bytes because `bitmap%` accepts that exact layout.
;; Depth and owner use mutable vectors to keep all decisions deterministic.
(struct raster-target3d (width height color-bytes depth-values owner-values)
  #:transparent)

(define (make-raster-target3d width height [background "white"])
  (unless (exact-positive-integer? width)
    (raise-argument-error 'make-raster-target3d "exact-positive-integer?" width))
  (unless (exact-positive-integer? height)
    (raise-argument-error 'make-raster-target3d "exact-positive-integer?" height))
  (unless (color-spec? background)
    (raise-argument-error 'make-raster-target3d "color-spec?" background))
  (define target
    (raster-target3d width height
                     (make-bytes (* 4 width height))
                     (make-vector (* width height) +inf.0)
                     (make-vector (* width height) -1)))
  (raster-target3d-clear! target background)
  target)

(define (raster-target3d-clear! target background)
  (unless (raster-target3d? target)
    (raise-argument-error 'raster-target3d-clear! "raster-target3d?" target))
  (define color (color-spec->rgba-color background 'raster-target3d-clear!))
  (define alpha (channel-byte (* 255 (rgba-color-alpha color))))
  (define red (channel-byte (rgba-color-red color)))
  (define green (channel-byte (rgba-color-green color)))
  (define blue (channel-byte (rgba-color-blue color)))
  (define bytes (raster-target3d-color-bytes target))
  (for ([index (in-range 0 (bytes-length bytes) 4)])
    (bytes-set! bytes index alpha)
    (bytes-set! bytes (add1 index) red)
    (bytes-set! bytes (+ index 2) green)
    (bytes-set! bytes (+ index 3) blue))
  (for ([index (in-range (vector-length (raster-target3d-depth-values target)))])
    (vector-set! (raster-target3d-depth-values target) index +inf.0)
    (vector-set! (raster-target3d-owner-values target) index -1))
  (void))

(define (raster-target3d->argb-bytes target)
  (unless (raster-target3d? target)
    (raise-argument-error 'raster-target3d->argb-bytes "raster-target3d?" target))
  (bytes-copy (raster-target3d-color-bytes target)))

(define (channel-byte value)
  (inexact->exact (round (max 0 (min 255 value)))))
