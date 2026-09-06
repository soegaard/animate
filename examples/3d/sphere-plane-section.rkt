#lang racket/base

;;; SCENE-3D-I: Sphere Cut by a Moving Plane

;; The moving point is a semantic control value in the spatial tree.  A
;; relation rebuilds both the render-only clipped sphere and the real section
;; curve from that point at every sampled time, so no frame inherits geometry
;; from the preceding frame.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define radius 3/2)

(define sphere
  (sphere3d radius #:id 'sphere #:longitude-segments 48 #:latitude-segments 24
            #:material (material3d #:color "#4f9dff80" #:shading 'smooth
                                   #:ambient 1 #:diffuse 1 #:double-sided? #t)))

(define (section-assembly offset)
  (define plane (plane3 (vec3 offset 0 0) x-axis3))
  (group3d
   (list
    ;; This wrapper leaves `sphere` semantically intact; only the viewport
    ;; clips it to the normal-facing side of the current plane.
    (clip3d sphere plane #:id 'remaining-sphere)
    (section-curve3d sphere plane #:id 'section #:color "gold" #:radius 1/32)
    ;; A translucent slab makes the moving cutting plane visible.  It is a
    ;; separate visual, so its transparency policy remains explicit.
    (box3d 1/40 4 4 #:id 'cutting-plane #:color "#f4b94266"
           #:transform (make-transform3 #:translation (vec3 offset 0 0))))
   #:id 'solid-section))

(define (make-world)
  (define driver
    (point3d origin3 #:id 'plane-driver #:radius 1/100 #:color "white" #:opacity 0
             #:transform (make-transform3 #:translation (vec3 -5/4 0 0))))
  (define dynamic-section
    (spatial-relation
     (section-assembly -5/4)
     #:depends-on (list (spatial-visual-dependency '(plane-driver)))
     (lambda (context _template)
       (define offset
         (vec3-x
          (spatial-relation-context-spatial-position context '(plane-driver))))
       ;; Recompute the render clip, actual section, and visible slab from the
       ;; same current plane offset.
       (section-assembly offset))))
  (view3d
   (list driver dynamic-section)
   #:id 'world #:center (vec2 1/2 -1/3) #:width 7 #:height 9/2
   #:background "aliceblue" #:render-mode 'opaque #:transparency-mode 'triangle-sorted
   #:camera (perspective-camera3d #:position (vec3 5 4 7) #:look-at origin3
                                 #:vertical-field-of-view (/ pi 5))))

(define (make-demo-scene)
  (define world (make-world))
  (define title
    (plain-text "SCENE-3D-I: clipping, sections, and transparency"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define formula
    (plain-text "r(d) = √(R² − d²)" #:id 'formula #:center (vec2 -4 -1/4)
                #:font-size 2/5 #:font-family 'roman #:color "midnightblue"))
  (define label
    (follow-projected-spatial
     (plain-text "moving section" #:id 'section-label #:font-size 1/5
                 #:font-family 'swiss #:color "darkgoldenrod")
     #:view 'world #:target '(plane-driver) #:offset (vec2 10 12) #:occlusion 'fade))
  (define caption
    (plain-text "The plane is render-clipped; the gold curve is a real mesh section."
                #:id 'caption #:center (vec2 0 -31/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene) world title formula label caption)
   (animation-group
    (move3d-to '(world plane-driver) (vec3 5/4 0 0))
    (camera3d-orbit-by 'world #:center origin3 #:azimuth (/ pi 2) #:elevation (/ pi 20)))
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "sphere-plane-section.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory) (set! output-video mp4-file))
  (render-frames! (make-demo-scene) output-directory #:fps 30)
  (when output-video (encode-mp4! output-directory output-video #:fps 30)))
