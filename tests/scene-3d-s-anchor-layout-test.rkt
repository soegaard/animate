#lang racket/base

;;; SCENE-3D-S Anchor and Direct Layout Determinism

(require racket/class
         racket/draw
         rackunit
         "../3d.rkt"
         "../main.rkt"
         "../project.rkt")

(module+ test
  (define world (view3d (list (cube3d 2 #:id 'cube)) #:id 'world))
  (define anchor (vertex-anchor3d '(world cube) 0))
  (define resolved (anchor3d-resolve anchor world))
  (check-equal? (resolved-anchor3d-world-point resolved) (vec3 -1 -1 -1))
  (check-equal? (anchor3d-identity anchor) (vector 'vertex '(world cube) 0))
  (define plane
    (parametric-surface3d (lambda (u v) (vec3 u v 0))
                         #:u-range '(-1 1) #:v-range '(-1 1)
                         #:resolution '(3 3) #:id 'plane))
  (define surface-world (view3d (list plane) #:id 'surface-world))
  (define surface-anchor (surface-anchor3d '(surface-world plane) #:u 0 #:v 0))
  (check-= (vec3-z (anchor3d-normal surface-anchor surface-world)) 1 1e-12)
  (check-= (vec3-x (anchor3d-tangent surface-anchor surface-world)) 1 1e-12)
  (define placement (label-placement3d '(east north) 16 2 #t #t '() 1 8))
  (define items
    (list (label-layout-item3d 'first (vector 50 50) 30 10 0 placement)
          (label-layout-item3d 'second (vector 50 50) 30 10 0 placement)))
  (define first-layout (layout-labels3d items #:width 100 #:height 100))
  (define second-layout (layout-labels3d items #:width 100 #:height 100))
  (check-equal? first-layout second-layout)
  (check-equal? (map label-layout-candidate3d-item-id (label-layout3d-placements first-layout))
                '(first second))
  ;; Equal priorities retain declaration order, not lexical ID order.
  (define declaration-layout
    (layout-labels3d
     (list (label-layout-item3d 'zeta (vector 20 20) 5 5 0 placement)
           (label-layout-item3d 'alpha (vector 80 80) 5 5 0 placement))
     #:width 100 #:height 100))
  (check-equal? (map label-layout-candidate3d-item-id
                     (label-layout3d-placements declaration-layout))
                '(zeta alpha))
  ;; With equal geometric cost, preferred order is decisive. `east` precedes
  ;; `north` for this policy even though the global compass order is north-first.
  (define preferred-layout
    (layout-labels3d
     (list (label-layout-item3d
            'preferred (vector 50 50) 5 5 0
            (label-placement3d '(east north) 10 2 #t #t '() 1 8)))
     #:width 100 #:height 100))
  (check-eq? (label-layout-candidate3d-direction
              (car (label-layout3d-placements preferred-layout)))
             'east)
  ;; Prepared layout can retain a direction through a small direct-mode flip.
  ;; Its output is an immutable table, so arbitrary frame lookup remains pure.
  (define prepared
    (prepare-label-layout3d
     (list (cons 0 (list (label-layout-item3d 'moving (vector 50 50) 8 8 0 placement)))
           (cons 1 (list (label-layout-item3d 'moving (vector 51 50) 8 8 0 placement))))
     #:width 100 #:height 100 #:switch-penalty 100 #:movement-penalty 1))
  (check-equal? (prepared-label-layout3d-frames prepared) #(0 1))
  (check-equal? (prepared-label-layout3d-ref prepared 1)
                (prepared-label-layout3d-ref prepared 1))
  (check-equal? (hash-ref (label-layout3d-diagnostics
                           (prepared-label-layout3d-ref prepared 0))
                          'mode)
                'prepared)

  ;; A higher-level scene preparation samples the same stable label slots that
  ;; the final compositor will use.  It needs neither a previous displayed
  ;; frame nor a live 3D renderer while it measures the concrete templates.
  (define label-world
    (view3d (list (cube3d 1 #:id 'shape))
            #:id 'label-world #:width 6 #:height 4
            #:camera (perspective-camera3d #:position (vec3 3 2 6)
                                            #:look-at origin3)
            #:render-mode 'opaque))
  (define label-a
    (follow-projected-point
     (plain-text "A" #:id 'label-a #:font-size 1/3)
     #:view 'label-world #:point (vec3 -1/2 0 0)
     #:placement (label-placement3d '(north east) 18 2 #t #t '() 1 6)))
  (define label-b
    (follow-projected-point
     (plain-text "B" #:id 'label-b #:font-size 1/3)
     #:view 'label-world #:point (vec3 1/2 0 0)
     #:placement (label-placement3d '(north east) 18 2 #t #t '() 1 6)))
  (define label-scene
    (scene-play
     (scene-add (make-scene) label-world label-a label-b)
     (camera3d-orbit-by 'label-world #:azimuth 1/2)
     #:duration 1))
  (define scene-prepared
    (prepare-scene-label-layout3d
     label-scene #:frames '(0 1) #:view 'label-world #:fps 2
     #:switch-penalty 80 #:movement-penalty 1))
  (check-equal? (prepared-label-layout3d-frames scene-prepared) #(0 1))
  (check-equal?
   (length (label-layout3d-placements
            (prepared-label-layout3d-ref scene-prepared 0)))
   2)
  ;; Workers consume the prepared data only by exact source-frame lookup.  A
  ;; successful bitmap proves the table reaches final composition without an
  ;; order-dependent mutable cache.
  (check-not-exn
   (lambda ()
     (scene-frame->bitmap label-scene 1 #:fps 2
                          #:prepared-label-layout scene-prepared)))
  ;; This deliberately altered immutable table proves the final compositor
  ;; reads the prepared slot, not merely that the worker API accepts it.
  (define direct-layout (prepared-label-layout3d-ref scene-prepared 1))
  (define shifted-layout
    (label-layout3d
     (for/list ([candidate (in-list (label-layout3d-placements direct-layout))])
       (if (eq? (label-layout-candidate3d-item-id candidate) 'label-a-layout-0)
           (struct-copy label-layout-candidate3d candidate
                        [box (vector 40 280
                                     (vector-ref (label-layout-candidate3d-box candidate) 2)
                                     (vector-ref (label-layout-candidate3d-box candidate) 3))])
           candidate))
     (label-layout3d-candidates direct-layout)
     (label-layout3d-diagnostics direct-layout)))
  (define shifted-prepared
    (prepared-label-layout3d
     #(1) (vector->immutable-vector (vector shifted-layout)) 0 0))
  (define (bitmap-argb bitmap)
    (define bytes (make-bytes (* 4 (send bitmap get-width) (send bitmap get-height))))
    (send bitmap get-argb-pixels 0 0 (send bitmap get-width) (send bitmap get-height) bytes)
    bytes)
  (check-false
   (bytes=?
    (bitmap-argb (scene-frame->bitmap label-scene 1 #:fps 2))
    (bitmap-argb
     (scene-frame->bitmap label-scene 1 #:fps 2
                          #:prepared-label-layout shifted-prepared))))

  ;; The project-level API chooses the project's FPS, output camera, raster
  ;; size, renderer list, and supersampling policy before it delegates to the
  ;; same scene preparation operation.
  (define label-project
    (animate-project
     #:id 'prepared-label-layout
     #:source (scene-source label-scene)
     #:render (render-spec #:fps 2 #:width 640 #:height 360)
     #:output (output-spec #:root "media" #:name "prepared-label-layout")))
  (define project-prepared
    (prepare-project-label-layout3d
     label-project #:view 'label-world #:frames '(0 1)
     #:switch-penalty 80 #:movement-penalty 1))
  (check-equal? (prepared-label-layout3d-frames project-prepared) #(0 1)))
