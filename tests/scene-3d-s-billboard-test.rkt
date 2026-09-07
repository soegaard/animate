#lang racket/base

;;; SCENE-3D-S textured billboard semantics

(require rackunit
         "../3d.rkt"
         "../private/3d/billboard-raster3d.rkt"
         "../private/3d/compiled-view3d.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/software-renderer3d.rkt"
         "../private/3d/spatial-inspection.rkt")

(define (solid-image width height red green blue [alpha 255])
  (define pixels (make-bytes (* 4 width height)))
  (for ([index (in-range 0 (bytes-length pixels) 4)])
    (bytes-set! pixels index alpha)
    (bytes-set! pixels (add1 index) red)
    (bytes-set! pixels (+ index 2) green)
    (bytes-set! pixels (+ index 3) blue))
  (billboard-image3d width height pixels))

(define yellow (solid-image 2 2 255 220 0))
(define camera (perspective-camera3d #:position (vec3 0 0 6) #:look-at origin3))

(define (pixel bytes width x y)
  (define index (* 4 (+ x (* y width))))
  (vector (bytes-ref bytes index) (bytes-ref bytes (add1 index))
          (bytes-ref bytes (+ index 2)) (bytes-ref bytes (+ index 3))))

(module+ test
  ;; The source image is frozen at construction: it retains a straight ARGB
  ;; texture rather than a mutable bitmap or backend object.
  (define source (make-bytes 4 0))
  (bytes-set! source 0 255)
  (bytes-set! source 1 20)
  (define frozen (billboard-image3d 1 1 source))
  (bytes-set! source 1 200)
  (check-equal? (bytes-ref (billboard-image3d-argb frozen) 1) 20)
  (check-exn exn:fail?
             (lambda () (billboard-style3d #:facing 'axis #:size-mode 'screen)))

  ;; A screen-sized camera billboard is depth-tested at its spatial anchor.
  (define basic
    (view3d (list (billboard3d yellow origin3 #:id 'badge
                                #:style (billboard-style3d #:width 32)))
            #:id 'world #:width 4 #:height 3 #:camera camera
            #:background "black" #:render-mode 'opaque))
  (define basic-compiled (compile-view3d basic))
  (check-equal? (vector-length (compiled-view3d-billboards basic-compiled)) 1)
  (define badge-inspection
    (view3d-spatial-inspection-at basic '(world badge)))
  (check-eq? (spatial-inspection-kind badge-inspection) 'billboard)
  (check-equal? (hash-ref (spatial-inspection-metadata badge-inspection)
                         'billboard-image-pixels)
                #(2 2))
  (define basic-result (render-view3d-opaque basic 100 80))
  (define basic-pixels (raster-target3d->argb-bytes (software-render-result-target basic-result)))
  (check-true (> (vector-ref (pixel basic-pixels 100 50 40) 1) 200))
  (check-true (> (vector-ref (pixel basic-pixels 100 50 40) 2) 150))

  ;; Geometry nearer than the anchor occludes a normal billboard. `always`
  ;; remains an explicit diagnostic/annotation overlay, never a change to the
  ;; depth buffer itself.
  (define (occlusion-view mode)
    (view3d
     (list (cube3d 2 #:id 'cube #:color "navy")
           (billboard3d yellow origin3 #:id 'badge
                        #:style (billboard-style3d #:width 32 #:depth-mode mode)))
     #:id 'world #:width 4 #:height 3 #:camera camera
     #:background "black" #:render-mode 'opaque))
  (define hidden-pixels
    (raster-target3d->argb-bytes
     (software-render-result-target (render-view3d-opaque (occlusion-view 'test) 100 80))))
  (define always-pixels
    (raster-target3d->argb-bytes
     (software-render-result-target (render-view3d-opaque (occlusion-view 'always) 100 80))))
  (check-true (< (vector-ref (pixel hidden-pixels 100 50 40) 1) 100))
  (check-true (> (vector-ref (pixel always-pixels 100 50 40) 1) 200))

  ;; Axis-facing world billboards prepare a true world plane instead of an
  ;; image-plane screen rectangle. This gives a stable upright sign under a
  ;; camera orbit and is the common information consumed by both backends.
  (define axis-style
    (billboard-style3d #:width 2 #:size-mode 'world #:facing 'axis #:axis y-axis3))
  (define axis-prepared
    (prepare-billboard3d '(world sign) origin3 identity-affine3 yellow axis-style 1 '()
                         camera 5/4 100 80 0))
  (check-true (prepared-billboard3d? axis-prepared))
  (check-equal? (length (prepared-billboard3d-vertices axis-prepared)) 4))
