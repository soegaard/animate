#lang racket/base

;;; SCENE-3D-V2: linear-light colour and final output semantics

(require racket/runtime-path
         rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../private/color-style.rkt"
         "../private/3d/raster-target3d.rkt")

(define-runtime-path opengl-module-path "../3d/opengl.rkt")

(define (within? actual expected [epsilon 1e-10])
  (<= (abs (- actual expected)) epsilon))

(define (argb-pixel bytes index)
  (define offset (* 4 index))
  (vector (bytes-ref bytes offset)
          (bytes-ref bytes (add1 offset))
          (bytes-ref bytes (+ offset 2))
          (bytes-ref bytes (+ offset 3))))

(define (bright-triangle-view)
  (define material
    (material3d #:color (rgba-color 128 40 220 1)
                #:shading 'unlit
                #:emission "white" #:emission-strength 3/2))
  (define mesh
    (mesh3d #:id 'triangle
            #:vertices (vector (vec3 -2 -2 0) (vec3 2 -2 0) (vec3 0 2 0))
            #:triangles (vector (vector 0 1 2))
            #:material material))
  (view3d (list mesh) #:id 'world #:width 4 #:height 4 #:render-mode 'opaque
          #:camera (orthographic-camera3d #:position (vec3 0 0 3) #:look-at origin3)
          #:tone-map (tone-map3d 'reinhard 1 1)))

(define (render backend view)
  (define request (view3d->render3d-request view 64 64))
  (renderer3d-render backend (renderer3d-prepare backend request) request))

(module+ test
  ;; IEC 61966-2-1 standard transfer-curve vectors.  These exact numerical
  ;; values make the CPU implementation's curve independently auditable.
  (check-equal? (srgb-channel->linear 0) 0)
  (check-equal? (srgb-channel->linear 1) 1.0)
  (check-true (within? (srgb-channel->linear 0.04045) 0.0031308049535603713))
  (check-true (within? (srgb-channel->linear 1/2) 0.21404114048223255))
  (check-true (within? (linear-channel->srgb 0.0031308) 0.040449936))
  (check-true (within? (linear-channel->srgb 0.21404114048223255) 1/2))
  (check-exn exn:fail? (lambda () (srgb-channel->linear -1/100)))
  (check-exn exn:fail? (lambda () (linear-channel->srgb 11/10)))

  (define semantic (rgba-color 128 64 0 1/3))
  (define linear (rgba-srgb->linear semantic))
  (check-true (linear-rgba3d? linear))
  (check-true (within? (linear-rgba3d-red linear) (srgb-channel->linear (/ 128.0 255))))
  ;; Alpha is coverage, not light: conversion preserves it exactly.
  (check-equal? (linear-rgba3d-alpha linear) 1/3)
  (define round-trip (rgba-linear->srgb linear))
  (check-true (within? (rgba-color-red round-trip) 128))
  (check-true (within? (rgba-color-green round-trip) 64))
  (check-equal? (rgba-color-alpha round-trip) 1/3)

  (define clamp-policy (tone-map3d 'clamp 1/2 4))
  (define reinhard-policy (tone-map3d 'reinhard 2 1))
  (define hdr (linear-rgba3d 2 1/2 1/4 2/5))
  (define clamped (tone-map3d-apply clamp-policy hdr))
  (check-equal? (linear-rgba3d-red clamped) 1)
  (check-equal? (linear-rgba3d-green clamped) 1/4)
  (check-equal? (linear-rgba3d-alpha clamped) 2/5)
  (define reinhard (tone-map3d-apply reinhard-policy hdr))
  (check-equal? (linear-rgba3d-red reinhard) 4/5)
  (check-equal? (linear-rgba3d-green reinhard) 1/2)
  (check-equal? (linear-rgba3d-alpha reinhard) 2/5)
  (check-exn exn:fail? (lambda () (tone-map3d 'other 1 1)))
  (check-exn exn:fail? (lambda () (tone-map3d 'clamp -1 1)))

  ;; The target retains unclipped linear energy and only encodes at its final
  ;; output boundary.  Its ARGB cache therefore agrees with the public pure
  ;; policy without making the raw linear value unavailable for composition.
  (define target (make-raster-target3d 1 1 "black" #:tone-map reinhard-policy))
  (raster-target3d-write-linear! target 0 hdr #:blend? #f)
  (check-equal? (raster-target3d-pixel-linear target 0) hdr)
  (define encoded
    (rgba-linear->srgb (tone-map3d-apply reinhard-policy hdr)))
  (check-equal? (argb-pixel (raster-target3d->argb-bytes target) 0)
                (vector (inexact->exact (round (* 255 (rgba-color-alpha encoded))))
                        (inexact->exact (round (rgba-color-red encoded)))
                        (inexact->exact (round (rgba-color-green encoded)))
                        (inexact->exact (round (rgba-color-blue encoded)))))

  ;; Source-over is done before tone mapping in linear light.  Blue at 1/2
  ;; alpha over opaque red leaves an even linear red/blue mixture, which then
  ;; encodes near 188 sRGB (not the old 128 display-space midpoint).
  (define composite (make-raster-target3d 1 1 "black"))
  (raster-target3d-write-srgb! composite 0 (rgba-color 255 0 0 1) #:blend? #f)
  (raster-target3d-write-srgb! composite 0 (rgba-color 0 0 255 1/2) #:blend? #t)
  (define mixed (raster-target3d-pixel-linear composite 0))
  (check-true (within? (linear-rgba3d-red mixed) 1/2))
  (check-true (within? (linear-rgba3d-blue mixed) 1/2))
  (check-equal? (argb-pixel (raster-target3d->argb-bytes composite) 0)
                (vector 255 188 0 188))

  ;; Output policy is immutable semantic view data and therefore part of the
  ;; compiled value used by both renderer backends.
  (define view (bright-triangle-view))
  (check-equal? (view3d-tone-map view) (tone-map3d 'reinhard 1 1))
  (check-equal? (compiled-view3d-tone-map (compile-view3d view))
                (view3d-tone-map view)))

;; A live lane compares only a safely interior pixel so edge sampling rules
;; and MSAA coverage do not obscure the colour-space contract.  It also forces
;; compilation and execution of the amended GLSL transfer curve.
(module+ test
  (when (equal? (getenv "ANIMATE_OPENGL_INTEGRATION") "1")
    (define make-opengl-renderer
      (dynamic-require opengl-module-path 'opengl-renderer3d))
    (define make-opengl-spec
      (dynamic-require opengl-module-path 'opengl-renderer3d-spec))
    (define renderer
      (make-opengl-renderer
       (make-opengl-spec #:samples 1 #:cache-megabytes 16 #:fallback 'error)))
    (dynamic-wind
     void
     (lambda ()
       (define view (bright-triangle-view))
       (define expected (render (software-renderer3d) view))
       (define actual (render renderer view))
       (define index (+ 32 (* 32 64)))
       (define expected-pixel (argb-pixel (renderer3d-render-result-argb-bytes expected) index))
       (define actual-pixel (argb-pixel (renderer3d-render-result-argb-bytes actual) index))
       (for ([expected-channel (in-vector expected-pixel)]
             [actual-channel (in-vector actual-pixel)])
         (check-true (<= (abs (- expected-channel actual-channel)) 5)))
       (check-true (> (vector-ref actual-pixel 1) 0)))
     (lambda () (renderer3d-release renderer)))))
