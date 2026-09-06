#lang racket/base

;;; SCENE-3D-J: Spatial Maps and Homotopies

;; The three viewports deliberately use different map semantics in one shared
;; timeline: an exact affine wrapper, a pointwise mesh deformation, and a
;; phase-evaluated homotopy. None of them inherits geometry from a previous
;; frame.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define (camera target)
  (perspective-camera3d #:position (vec3 5 4 7) #:look-at target
                        #:vertical-field-of-view (/ pi 5)))

;; A deliberately dense rectangular mesh makes the homotopy visible. A sphere
;; is rotationally symmetric, so twisting it would demonstrate the API but not
;; teach the eye what is changing.
(define (twist-sheet)
  (define columns 25)
  (define rows 25)
  (define (index column row) (+ column (* columns row)))
  (define vertices
    (for*/vector ([row (in-range rows)] [column (in-range columns)])
      (vec3 (- (* 2 (/ column (sub1 columns))) 1)
            0
            (- (* 2 (/ row (sub1 rows))) 1))))
  (define triangles
    (list->vector
     (apply append
            (for*/list ([row (in-range (sub1 rows))]
                        [column (in-range (sub1 columns))])
              (list (vector (index column row)
                            (index (add1 column) row)
                            (index (add1 column) (add1 row)))
                    (vector (index column row)
                            (index (add1 column) (add1 row))
                            (index column (add1 row))))))))
  (mesh3d #:id 'sheet #:vertices vertices #:triangles triangles
          #:material (material3d #:color "#d86faacc" #:shading 'smooth
                                 #:double-sided? #t)))

(define (make-demo-scene)
  (define linear-world
    (view3d
     (list (linear-transformation-diagram3d #:id 'diagram #:vector (vec3 3/2 1 1)))
     #:id 'linear-world #:center (vec2 -9/2 1/4) #:width 5 #:height 3
     #:background "aliceblue" #:render-mode 'opaque #:camera (camera (vec3 1/2 1/2 1/2))))
  (define ellipsoid-world
    (view3d
     (list (sphere3d 1 #:id 'sphere #:longitude-segments 40 #:latitude-segments 20
                     #:color "#4f9dffcc"))
     #:id 'ellipsoid-world #:center origin #:width 5 #:height 3
     #:background "aliceblue" #:render-mode 'opaque #:camera (camera origin3)))
  (define twist-world
    (view3d
     (list (twist-sheet))
     #:id 'twist-world #:center (vec2 9/2 1/4) #:width 5 #:height 3
     #:background "aliceblue" #:render-mode 'opaque #:camera (camera origin3)))
  (define title
    (plain-text "SCENE-3D-J: spatial maps and homotopies"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define left-caption
    (plain-text "linear shear" #:id 'left-caption #:center (vec2 -9/2 -19/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define middle-caption
    (plain-text "pointwise ellipsoid" #:id 'middle-caption #:center (vec2 0 -19/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define right-caption
    (plain-text "direct twist homotopy" #:id 'right-caption #:center (vec2 9/2 -19/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define caption
    (plain-text "Affine maps preserve mesh topology; nonlinear maps use the authored vertices."
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene)
              linear-world ellipsoid-world twist-world
              title left-caption middle-caption right-caption caption)
   (animation-group
    ;; x' = x + z: a real matrix wrapper transforms cube, coordinate planes,
    ;; basis arrows, and the arbitrary vector as one coherent spatial tree.
    (apply-linear3 '(linear-world diagram)
                   (linear3 1 0 1
                            0 1 0
                            0 0 1))
    ;; Vertex positions are sampled at each time. Normals are recomputed from
    ;; that instantaneous mesh; no adaptive remeshing is implied.
    (apply-pointwise3 '(ellipsoid-world sphere)
                      (lambda (point)
                        (vec3 (* 3/2 (vec3-x point))
                              (* 3/4 (vec3-y point))
                              (* 5/4 (vec3-z point)))))
    ;; H(point, alpha) is evaluated directly: alpha squared below is visibly
    ;; different from merely interpolating a start mesh and an end mesh.
    (apply-homotopy3
     '(twist-world sheet)
     (lambda (point alpha)
       (define angle (* (/ pi 2) alpha alpha (vec3-z point)))
       (vec3 (- (* (cos angle) (vec3-x point))
                (* (sin angle) (vec3-y point)))
             (+ (* (sin angle) (vec3-x point))
                (* (cos angle) (vec3-y point)))
             (vec3-z point))))
    (camera3d-orbit-by 'linear-world #:center (vec3 1/2 1/2 1/2) #:azimuth (/ pi 3))
    (camera3d-orbit-by 'ellipsoid-world #:center origin3 #:azimuth (/ pi 3))
    (camera3d-orbit-by 'twist-world #:center origin3 #:azimuth (/ pi 3)))
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "spatial-maps-and-homotopies.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory) (set! output-video mp4-file))
  (render-frames! (make-demo-scene) output-directory #:fps 30)
  (when output-video (encode-mp4! output-directory output-video #:fps 30)))
