#lang racket/base

;;; SCENE-3D-E: Semantic Tetrahedron Relations and Crisp Projected Labels

;; This example has one ordinary Scene timeline.  The tetrahedron and its edge
;; relations live inside `world`; A, B, C, and D are regular 2D TeX labels that
;; follow projected spatial vertices while the group and camera both move.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define vertex-positions
  (hash 'A (vec3 -1 -3/4 -1/2)
        'B (vec3 1 -3/4 -1/2)
        'C (vec3 0 1 0)
        'D (vec3 0 -1/4 1)))

(define tetrahedron-vertices
  (vector (hash-ref vertex-positions 'A)
          (hash-ref vertex-positions 'B)
          (hash-ref vertex-positions 'C)
          (hash-ref vertex-positions 'D)))

(define tetrahedron-triangles
  (vector (vector 0 2 1)
          (vector 0 1 3)
          (vector 0 3 2)
          (vector 1 2 3)))

(define (vertex-marker id)
  ;; The marker establishes a stable spatial anchor; the body mesh supplies
  ;; the visible tetrahedron itself. SCENE-3D-F will add true point primitives.
  (mesh3d #:id id
          #:vertices (vector origin3)
          #:transform (make-transform3 #:translation (hash-ref vertex-positions id))))

(define (make-world)
  (define tetrahedron
    (group3d
     (list
      (mesh3d #:id 'body
              #:vertices tetrahedron-vertices
              #:triangles tetrahedron-triangles
              #:material (material3d #:color "steelblue" #:shading 'flat))
      (vertex-marker 'A) (vertex-marker 'B)
      (vertex-marker 'C) (vertex-marker 'D))
     #:id 'tetrahedron
     #:transform (make-transform3 #:rotation (axis-angle y-axis3 (/ pi 9)))))
  (define edges
    (list
     (segment-between3d '(tetrahedron A) '(tetrahedron B)
                        #:id 'AB #:color "midnightblue" #:width 2)
     (segment-between3d '(tetrahedron A) '(tetrahedron C)
                        #:id 'AC #:color "midnightblue" #:width 2)
     (segment-between3d '(tetrahedron A) '(tetrahedron D)
                        #:id 'AD #:color "midnightblue" #:width 2)
     (segment-between3d '(tetrahedron B) '(tetrahedron C)
                        #:id 'BC #:color "midnightblue" #:width 2)
     (segment-between3d '(tetrahedron B) '(tetrahedron D)
                        #:id 'BD #:color "midnightblue" #:width 2)
     (segment-between3d '(tetrahedron C) '(tetrahedron D)
                        #:id 'CD #:color "midnightblue" #:width 2)))
  (view3d
   (append (list tetrahedron) edges)
   #:id 'world
   #:center (vec2 0 -1/4)
   #:width 7 #:height 9/2
   #:camera
   (perspective-camera3d #:position (vec3 4 3 7)
                         #:look-at origin3
                         #:vertical-field-of-view (/ pi 5))
   #:background "aliceblue"
   ;; Wireframe makes the live mesh-based relation segments visible as well as
   ;; the tetrahedron boundary. Labels themselves remain independent 2D TeX.
   #:render-mode 'wireframe))

(define (vertex-label name offset)
  (projected-label
   (math-tex #:id (string->symbol (format "label-~a" name))
             #:font-size 1/3
             (symbol->string name))
   #:view 'world
   #:target (list 'tetrahedron name)
   #:offset offset))

(define (make-demo-scene)
  (define world (make-world))
  (define title
    (plain-text "SCENE-3D-E: spatial relations and projected labels"
                #:id 'title #:center (vec2 0 15/4)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define caption
    (plain-text "A–D remain crisp 2D labels while their spatial anchors and camera move."
                #:id 'caption #:center (vec2 0 -29/10)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene)
              world title caption
              ;; Deliberately generous screen offsets make the relation
              ;; between a crisp label and its projected vertex legible at
              ;; every camera angle in this compact example.
              (vertex-label 'A (vec2 -20 -18))
              (vertex-label 'B (vec2 20 -18))
              (vertex-label 'C (vec2 0 23))
              (vertex-label 'D (vec2 34 28)))
   (rotate3d-by '(world tetrahedron) (axis-angle y-axis3 (* 2 pi)))
   (move3d-to '(world tetrahedron) (vec3 1/2 1/4 0))
   (camera3d-orbit-by 'world #:azimuth (* 2 pi) #:elevation (/ pi 15))
   #:duration 6))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "projected-labels.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
