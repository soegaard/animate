#lang racket/base

;;; Software Raster Target

(require "../color-style.rkt"
         "color-space3d.rkt")

(provide (struct-out raster-target3d)
         make-raster-target3d
         raster-target3d-clear!
         raster-target3d-pixel-linear
         raster-target3d-write-linear!
         raster-target3d-write-srgb!
         raster-target3d->argb-bytes)

;; `linear-colors` owns the scene-linear, straight-alpha result.  `color-bytes`
;; is its encoded ARGB presentation cache for bitmap%, inspection, and the
;; public renderer protocol.  Keeping both makes output policy explicit while
;; retaining the target's old byte-oriented inspection surface.
(struct raster-target3d (width height color-bytes linear-colors depth-values owner-values tone-map)
  #:transparent)

(define (make-raster-target3d width height [background "white"]
                              #:tone-map [tone-map default-tone-map3d])
  (unless (exact-positive-integer? width)
    (raise-argument-error 'make-raster-target3d "exact-positive-integer?" width))
  (unless (exact-positive-integer? height)
    (raise-argument-error 'make-raster-target3d "exact-positive-integer?" height))
  (unless (color-spec? background)
    (raise-argument-error 'make-raster-target3d "color-spec?" background))
  (unless (tone-map3d? tone-map)
    (raise-argument-error 'make-raster-target3d "tone-map3d? as #:tone-map" tone-map))
  (define target
    (raster-target3d width height
                     (make-bytes (* 4 width height))
                     (make-vector (* width height) (linear-rgba3d 0 0 0 0))
                     (make-vector (* width height) +inf.0)
                     (make-vector (* width height) -1)
                     tone-map))
  (raster-target3d-clear! target background)
  target)

(define (raster-target3d-clear! target background)
  (unless (raster-target3d? target)
    (raise-argument-error 'raster-target3d-clear! "raster-target3d?" target))
  (define color (rgba-srgb->linear
                 (color-spec->rgba-color background 'raster-target3d-clear!)))
  (for ([index (in-range (vector-length (raster-target3d-linear-colors target)))])
    (vector-set! (raster-target3d-linear-colors target) index color)
    (sync-presentation-pixel! target index))
  (for ([index (in-range (vector-length (raster-target3d-depth-values target)))])
    (vector-set! (raster-target3d-depth-values target) index +inf.0)
    (vector-set! (raster-target3d-owner-values target) index -1))
  (void))

(define (raster-target3d->argb-bytes target)
  (unless (raster-target3d? target)
    (raise-argument-error 'raster-target3d->argb-bytes "raster-target3d?" target))
  (bytes-copy (raster-target3d-color-bytes target)))

(define (raster-target3d-pixel-linear target index)
  (check-index 'raster-target3d-pixel-linear target index)
  (vector-ref (raster-target3d-linear-colors target) index))

(define (raster-target3d-write-linear! target index color #:blend? [blend? #f])
  (check-index 'raster-target3d-write-linear! target index)
  (unless (linear-rgba3d? color)
    (raise-argument-error 'raster-target3d-write-linear! "linear-rgba3d?" color))
  (unless (boolean? blend?)
    (raise-argument-error 'raster-target3d-write-linear! "boolean? as #:blend?" blend?))
  (define result
    (if blend?
        (linear-rgba3d-over color (raster-target3d-pixel-linear target index))
        color))
  (vector-set! (raster-target3d-linear-colors target) index result)
  (sync-presentation-pixel! target index)
  (void))

(define (raster-target3d-write-srgb! target index color #:blend? [blend? #t])
  (unless (rgba-color? color)
    (raise-argument-error 'raster-target3d-write-srgb! "rgba-color?" color))
  (raster-target3d-write-linear! target index (rgba-srgb->linear color) #:blend? blend?))

(define (sync-presentation-pixel! target index)
  (define display
    (rgba-linear->srgb
     (tone-map3d-apply (raster-target3d-tone-map target)
                       (raster-target3d-pixel-linear target index))))
  (define byte-index (* index 4))
  (define bytes (raster-target3d-color-bytes target))
  (bytes-set! bytes byte-index (channel-byte (* 255 (rgba-color-alpha display))))
  (bytes-set! bytes (add1 byte-index) (channel-byte (rgba-color-red display)))
  (bytes-set! bytes (+ byte-index 2) (channel-byte (rgba-color-green display)))
  (bytes-set! bytes (+ byte-index 3) (channel-byte (rgba-color-blue display))))

(define (check-index who target index)
  (unless (raster-target3d? target)
    (raise-argument-error who "raster-target3d?" target))
  (unless (and (exact-nonnegative-integer? index)
               (< index (vector-length (raster-target3d-linear-colors target))))
    (raise-argument-error who "pixel index within target" index)))

(define (channel-byte value)
  (inexact->exact (round (max 0 (min 255 value)))))
