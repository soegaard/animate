#lang racket/base

;;; SCENE-3D-M: backend-neutral retained renderer protocol

(require racket/class
         rackunit
         "../3d.rkt"
         "../3d/render.rkt")

(define material
  (material3d #:color "steelblue" #:shading 'smooth #:specular 1/4))

(define world
  (view3d
   (list (cube3d 2 #:id 'cube #:material material))
   #:id 'world #:width 4 #:height 3 #:render-mode 'opaque
   #:camera
   (perspective-camera3d
    #:position (vec3 3 2 4)
    #:rotation (rotation3-look-at (vec3 -3 -2 -4)))))

(module+ test
  (define request (view3d->render3d-request world 80 60))
  (define reference (software-renderer3d))
  (define retained (retained-software-renderer3d #:capacity 2))

  (check-eq? (renderer3d-id reference) 'software-reference)
  (check-eq? (renderer3d-id retained) 'retained-software-reference)
  (check-true (renderer3d-capability-set-opaque-triangles
               (renderer3d-capabilities retained)))
  (check-true (renderer3d-capability-set-depth-buffer
               (renderer3d-capabilities retained)))
  (check-true (renderer3d-capability-set-transparency
               (renderer3d-capabilities retained)))

  (define reference-result
    (renderer3d-render reference (renderer3d-prepare reference request) request))
  (define first-preparation (renderer3d-prepare retained request))
  (define retained-result
    (renderer3d-render retained first-preparation request))
  (define second-preparation (renderer3d-prepare retained request))

  ;; The retained path is an optimisation only: its complete output equals the
  ;; deterministic software reference, and a second identical request reuses
  ;; the immutable camera-space preparation rather than semantic scene data.
  (check-equal? (renderer3d-render-result-argb-bytes retained-result)
                (renderer3d-render-result-argb-bytes reference-result))
  (check-eq? first-preparation second-preparation)
  (check-equal? (retained-software-renderer3d-cache-misses retained) 1)
  (check-equal? (retained-software-renderer3d-cache-hits retained) 1)
  (check-equal? (retained-software-renderer3d-cache-size retained) 1)

  (define bitmap (renderer3d-render-result->bitmap retained-result))
  (check-equal? (send bitmap get-width) 80)
  (check-equal? (send bitmap get-height) 60)

  (renderer3d-release retained)
  (check-equal? (retained-software-renderer3d-cache-size retained) 0)
  (check-equal? (retained-software-renderer3d-cache-hits retained) 0)
  (check-equal? (retained-software-renderer3d-cache-misses retained) 0)

  ;; A shared default backend is used by preview/PNG workers. Concurrent cache
  ;; lookup and population must therefore have one miss, three hits, and four
  ;; independent but equal render results.
  (define shared (retained-software-renderer3d #:capacity 2))
  (define result-boxes (for/list ([index (in-range 4)]) (box #f)))
  (define workers
    (for/list ([result-box (in-list result-boxes)])
      (thread
       (lambda ()
         (define preparation (renderer3d-prepare shared request))
         (set-box! result-box
                   (renderer3d-render shared preparation request))))))
  (for ([worker (in-list workers)]) (thread-wait worker))
  (define parallel-results (map unbox result-boxes))
  (check-equal? (retained-software-renderer3d-cache-misses shared) 1)
  (check-equal? (retained-software-renderer3d-cache-hits shared) 3)
  (check-true
   (andmap (lambda (result)
             (bytes=? (renderer3d-render-result-argb-bytes result)
                      (renderer3d-render-result-argb-bytes (car parallel-results))))
           (cdr parallel-results))))
