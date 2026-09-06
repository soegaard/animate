#lang racket/base

;;; SCENE-3D-L: watertight inspector-example mesh

(require rackunit
         "../3d.rkt"
         "../main.rkt"
         "../examples/3d/spatial-inspector-picking.rkt")

(define (triangle-centre vertices triangle)
  (vec3-scale
   1/3
   (vec3+
    (vec3+ (vector-ref vertices (vector-ref triangle 0))
           (vector-ref vertices (vector-ref triangle 1)))
    (vector-ref vertices (vector-ref triangle 2)))))

(define (triangle-outward-normal vertices triangle)
  (vec3-cross
   (vec3- (vector-ref vertices (vector-ref triangle 1))
          (vector-ref vertices (vector-ref triangle 0)))
   (vec3- (vector-ref vertices (vector-ref triangle 2))
          (vector-ref vertices (vector-ref triangle 0)))))

(module+ test
  (define demo (make-demo-scene))
  (define world (scene-visual-at demo 'world 0))
  (define roof (car (view3d-children world)))
  (define vertices (mesh3d-vertices roof))
  (define triangles (mesh3d-triangles roof))

  ;; A 3D picking example must look like the closed solid it describes. Empty
  ;; boundary edges prevent a later triangle-index edit from reopening a face.
  (check-equal? (vector-length triangles) 14)
  (check-equal? (vector-length (mesh3d-boundary-edges roof)) 0)

  ;; The object interior includes the origin. A positive face-normal dot
  ;; product therefore confirms every triangle faces away from the interior,
  ;; so the opaque renderer's ordinary back-face culling cannot reveal holes.
  (for ([triangle (in-vector triangles)])
    (check-true
     (positive?
      (vec3-dot (triangle-outward-normal vertices triangle)
                (triangle-centre vertices triangle))))))
