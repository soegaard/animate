#lang racket/base

;;; SCENE-3D-N: reproducible renderer workload measurements

;; This is intentionally a measurement tool, not a performance test. Machines
;; differ substantially in software-raster speed; the useful contract is that
;; each named workload reports its exact renderer counters alongside elapsed
;; time, making cache and triangle-count regressions visible without CI timing
;; thresholds.

(require racket/cmdline
         racket/list
         racket/math
         "../3d.rkt"
         "../3d/render.rkt"
         "../private/3d/software-render-diagnostics.rkt")

(provide (struct-out benchmark3d-workload)
         benchmark-3d-n-workloads
         run-3d-n-benchmarks)

(struct benchmark3d-workload (name views renderer-capacity) #:transparent)

(define base-material
  (material3d #:color "cornflowerblue" #:shading 'flat #:ambient 1/2 #:diffuse 1/2))
(define translucent-material
  (material3d #:color "#5d8fd3aa" #:shading 'flat #:ambient 1/2 #:diffuse 1/2))

(define (camera-at azimuth)
  (define position (vec3 (* 7 (cos azimuth)) 4 (* 7 (sin azimuth))))
  (perspective-camera3d #:position position #:look-at origin3
                        #:vertical-field-of-view (/ pi 5)))

(define (opaque-view id camera children)
  (view3d children #:id id #:width 8 #:height 5 #:camera camera
          #:background "aliceblue" #:render-mode 'opaque))

(define (high-surface id transform)
  (sphere3d 3/2 #:id id #:latitude-segments 32 #:longitude-segments 64
            #:transform transform #:material base-material))

(define (cube-instance id position [side 1])
  (cube3d side #:id id
          #:transform (make-transform3 #:translation position)
          #:material base-material))

(define (orbit-views children)
  (for/list ([phase (in-range 8)])
    (opaque-view 'orbit (camera-at (* 2 pi (/ phase 8))) children)))

(define (screen-stroke-workload)
  ;; This was deliberately listed as an N placeholder.  O makes it a real
  ;; retained-renderer workload: a dense, ordered set of camera-sized marks
  ;; plus a screen marker and arrowhead, sampled under a camera orbit.
  (orbit-views
   (append
    (for/list ([index (in-range 80)])
      (define y (- (/ (modulo index 10) 3) 3/2))
      (line3d (vec3 -4 y (- (/ index 40)))
              (vec3 4 y (- (/ index 40)))
              #:id (string->symbol (format "stroke-~a" index))
              #:style (stroke3d #:width 2 #:dash '(4 3))))
    (list (point3d origin3 #:id 'stroke-point #:style (point-style3d #:size 10))
          (arrow3d (vec3 -3 -2 0) (vec3 3 -2 0) #:id 'stroke-arrow)))))

(define benchmark-3d-n-workloads
  (list
   (benchmark3d-workload
    'static-high-surface
    (list (opaque-view 'static (camera-at 0)
                       (list (high-surface 'surface identity-transform3))))
    4)
   (benchmark3d-workload
    'camera-orbit
    (orbit-views (list (high-surface 'surface identity-transform3)))
    4)
   (benchmark3d-workload
    'moving-instance
    (for/list ([phase (in-range 8)])
      (opaque-view 'moving (camera-at 0)
                   (list (cube-instance 'moving-cube
                                        (vec3 (- phase 7/2) 0 0)))))
    4)
   (benchmark3d-workload
    'shared-geometry
    (list
     (opaque-view
      'shared (camera-at 0)
      (for/list ([index (in-range 24)])
        (cube-instance (string->symbol (format "cube-~a" index))
                       (vec3 (- (modulo index 6) 5/2)
                             (- 3/2 (quotient index 6)) 0)))))
    4)
   (benchmark3d-workload
    'many-instances
    (orbit-views
     (for/list ([index (in-range 36)])
       (cube-instance (string->symbol (format "instance-~a" index))
                      (vec3 (- (modulo index 9) 4)
                            (- 3/2 (quotient index 9)) 0)
                      3/5)))
    8)
   (benchmark3d-workload
    'many-unique-geometries
    (list
     (opaque-view
      'unique (camera-at 0)
      (for/list ([index (in-range 12)])
        (cube-instance (string->symbol (format "unique-~a" index))
                       (vec3 (- index 11/2) 0 0)
                       (+ 1/2 (/ index 16))))))
    4)
   (benchmark3d-workload
    'transparent-overlap
    (list
     (view3d
      (for/list ([index (in-range 12)])
        (cube3d 3/2 #:id (string->symbol (format "glass-~a" index))
                #:transform (make-transform3 #:translation (vec3 0 0 (/ index 10)))
                #:material translucent-material))
      #:id 'transparent #:width 8 #:height 5 #:camera (camera-at 0)
      #:background "aliceblue" #:render-mode 'opaque))
    4)
   (benchmark3d-workload
    'clipped-surface
    (list
     (opaque-view
      'clipped (camera-at 0)
      (list
       (clip3d
        (high-surface 'surface identity-transform3)
        (clip-plane3d (plane3 origin3 x-axis3) #:keep 'positive)
        #:id 'half))))
    4)
   (benchmark3d-workload
    'geometry-cache-churn
    (for/list ([index (in-range 8)])
      (opaque-view
       'churn (camera-at 0)
       (list (cube-instance 'changing origin3 (+ 1 (/ index 8))))))
    2)
   (benchmark3d-workload
    'screen-strokes
    (screen-stroke-workload)
    4)))

; run-3d-n-benchmarks : [#:width exact-positive-integer?]
;                       [#:height exact-positive-integer?]
;                       -> (listof hash?)
;; Runs every named workload and returns reproducible semantic counters plus
;; local elapsed milliseconds. No result is compared to a timing baseline.
(define (run-3d-n-benchmarks #:width [width 320] #:height [height 180])
  (unless (exact-positive-integer? width)
    (raise-argument-error 'run-3d-n-benchmarks "exact-positive-integer?" width))
  (unless (exact-positive-integer? height)
    (raise-argument-error 'run-3d-n-benchmarks "exact-positive-integer?" height))
  (for/list ([workload (in-list benchmark-3d-n-workloads)])
    (define renderer
      (retained-software-renderer3d #:capacity (benchmark3d-workload-renderer-capacity workload)))
    (define start (current-inexact-milliseconds))
    (define results
      (for/list ([view (in-list (benchmark3d-workload-views workload))])
        (define request (view3d->render3d-request view width height))
        (renderer3d-render renderer (renderer3d-prepare renderer request) request)))
    (hasheq 'name (benchmark3d-workload-name workload)
            'frame-count (length (benchmark3d-workload-views workload))
            'elapsed-milliseconds (- (current-inexact-milliseconds) start)
            'statistics (renderer3d-statistics-snapshot renderer)
            'stroke-diagnostics
            (for/list ([result (in-list results)])
              (define diagnostics (renderer3d-render-result-diagnostics result))
              (if (software-render-diagnostics? diagnostics)
                  (hasheq 'visible-stroke-pixels
                          (software-render-diagnostics-visible-stroke-pixel-count diagnostics)
                          'hidden-stroke-pixels
                          (software-render-diagnostics-hidden-stroke-pixel-count diagnostics)
                          'always-stroke-pixels
                          (software-render-diagnostics-always-stroke-pixel-count diagnostics)
                          'silhouette-edge-count
                          (software-render-diagnostics-silhouette-edge-count diagnostics)
                          'crease-edge-count
                          (software-render-diagnostics-crease-edge-count diagnostics)
                          'boundary-edge-count
                          (software-render-diagnostics-boundary-edge-count diagnostics))
                  #hasheq())))))

(module+ main
  (define width 320)
  (define height 180)
  (command-line
   #:program "benchmark-3d-n.rkt"
   #:once-each
   ["--width" pixels "Output width" (set! width (string->number pixels))]
   ["--height" pixels "Output height" (set! height (string->number pixels))])
  (for ([result (in-list (run-3d-n-benchmarks #:width width #:height height))])
    (write result)
    (newline)))
