#lang racket/base

;;; SCENE-3D-M: reference/retained conformance across camera frames

(require racket/math
         rackunit
         "../3d.rkt"
         "../3d/render.rkt")

(define material
  (material3d #:color "tomato" #:shading 'flat #:ambient 1/3 #:diffuse 2/3))

(define (world-at phase)
  (define angle (* phase pi))
  (define position (vec3 (* 4 (cos angle)) 2 (* 4 (sin angle))))
  (view3d
   (list (cube3d 2 #:id 'front #:material material
                 #:transform (make-transform3 #:translation (vec3 0 0 1/2)))
         (cube3d 2 #:id 'back #:material material
                 #:transform (make-transform3 #:translation (vec3 0 0 -1/2))))
   #:id 'world #:width 5 #:height 3 #:render-mode 'opaque
   #:camera
   (perspective-camera3d #:position position
                         #:rotation (rotation3-look-at (vec3-scale -1 position)))))

(define (render backend request)
  (renderer3d-render backend (renderer3d-prepare backend request) request))

(module+ test
  (define reference (software-renderer3d))
  (define retained (retained-software-renderer3d #:capacity 4))
  ;; Random-access order is deliberately nonmonotonic.  Conformance must not
  ;; depend on prior camera frames or a backend's retained cache history.
  (for ([phase (in-list '(1/2 0 1 1/4 3/4 0))])
    (define request (render3d-request (world-at phase) 96 72 #f))
    (define expected (render reference request))
    (define actual (render retained request))
    (check-equal? (renderer3d-render-result-width actual) 96)
    (check-equal? (renderer3d-render-result-height actual) 72)
    (check-equal? (renderer3d-render-result-argb-bytes actual)
                  (renderer3d-render-result-argb-bytes expected)))
  ;; Repeating the endpoint proves that identity, depth, and representative
  ;; pixels are cache-independent at exact animation endpoints.
  (check-true (positive? (retained-software-renderer3d-cache-hits retained))))
