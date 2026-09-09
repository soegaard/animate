#lang racket/base

;;; OpenGL persistent identity is based on effective pixel implementation

(require rackunit
         "../private/3d/opengl/cache-identity.rkt")

(module+ test
  (define implementation-a
    '("Example GPU" "Example renderer" (4 1) (4 10) core-or-compatible))
  (define implementation-b
    '("Example GPU" "Other renderer" (4 1) (4 10) core-or-compatible))
  (define shaders-a
    '((surface "vertex-a" "fragment-a")
      (stroke "vertex-b" "fragment-b")))
  (define shaders-b
    '((surface "vertex-a" "fragment-changed")
      (stroke "vertex-b" "fragment-b")))
  (define live-a (make-opengl-live-cache-identity 4 implementation-a shaders-a))
  (check-equal? (opengl-effective-samples 4 8) 4)
  (check-equal? (opengl-effective-samples 16 8) 8)
  (check-equal? (opengl-effective-samples 16 1) 1)
  ;; Persistent identity names the effective sample count. Requests that clamp
  ;; to the same count share pixels and therefore a cache entry.
  (check-equal? (make-opengl-live-cache-identity
                 (opengl-effective-samples 16 4) implementation-a shaders-a)
                (make-opengl-live-cache-identity
                 (opengl-effective-samples 4 4) implementation-a shaders-a))
  (check-not-equal? (make-opengl-live-cache-identity
                     (opengl-effective-samples 16 4) implementation-a shaders-a)
                    (make-opengl-live-cache-identity
                     (opengl-effective-samples 2 4) implementation-a shaders-a))
  (check-equal? live-a
                (make-opengl-live-cache-identity 4 implementation-a shaders-a))
  (check-not-equal? live-a
                    (make-opengl-live-cache-identity 4 implementation-b shaders-a))
  (check-not-equal? live-a
                    (make-opengl-live-cache-identity 4 implementation-a shaders-b))
  (check-not-equal? live-a
                    (make-opengl-live-cache-identity 1 implementation-a shaders-a))
  ;; A fallback key names the backend that drew the pixels, not resource-cache
  ;; capacity or a requested-but-unavailable OpenGL configuration.
  (check-equal?
   (make-opengl-fallback-cache-identity '(animate-software-renderer3d-v1 reference))
   '(animate-opengl-renderer3d-cache-v3
     backend software-fallback
     delegate (animate-software-renderer3d-v1 reference))))
