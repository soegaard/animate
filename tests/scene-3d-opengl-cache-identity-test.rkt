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
   '(animate-opengl-renderer3d-cache-v2
     backend software-fallback
     delegate (animate-software-renderer3d-v1 reference))))
