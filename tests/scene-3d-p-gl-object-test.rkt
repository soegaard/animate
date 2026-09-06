#lang racket/base

;;; SCENE-3D-P: fake-GL resource lifecycle and generation safety

(require rackunit
         "../private/3d/opengl/gl-object.rkt")

(module+ test
  ;; No GUI or OpenGL binding is involved here.  The wrapper receives a fake
  ;; deletion procedure, which makes its lifecycle state machine portable.
  (define host
    (make-gl-resource-context 7))
  (define deleted '())
  (define buffer
    (gl-buffer (gl-resource-context-current-identity host) 41 128 #f "fake-vbo"
               (lambda (id) (set! deleted (cons id deleted)))))

  (check-true (gl-resource-live? buffer))
  (check-not-exn (lambda () (gl-resource-check-current! buffer host)))
  (check-true (gl-resource-delete-current! buffer host))
  (check-equal? deleted '(41))
  (check-false (gl-resource-live? buffer))
  ;; Cleanup after a partial constructor is idempotent.
  (check-false (gl-resource-delete-current! buffer host))
  (check-equal? deleted '(41))

  (define stale
    (gl-buffer (gl-resource-context-current-identity host) 42 0 #f "stale-vbo" void))
  (define restarted-host (make-gl-resource-context 8))
  ;; A context restart invalidates every old GLuint before it can be used.
  (check-exn exn:fail:contract?
             (lambda () (gl-resource-check-current! stale restarted-host)))

  ;; Same generation is not enough: independent hosts never share native GL
  ;; ownership merely because both begin at zero.
  (define other-host (make-gl-resource-context 7))
  (check-exn exn:fail:contract?
             (lambda () (gl-resource-check-current! stale other-host))))
