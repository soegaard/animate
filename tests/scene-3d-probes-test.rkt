#lang racket/base

;;; SCENE-3D: stage-aware visual-probe evidence

(require racket/file
         rackunit
         "../tools/run-3d-probes.rkt")

(module+ test
  (check-equal?
   known-3d-probe-stages
   '(SCENE-3D-B SCENE-3D-C SCENE-3D-D SCENE-3D-E SCENE-3D-F SCENE-3D-G
     SCENE-3D-H SCENE-3D-I SCENE-3D-J SCENE-3D-K SCENE-3D-L SCENE-3D-M))
  (define m-probes (stage->probes 'SCENE-3D-M))
  (check-equal? (map probe3d-id m-probes) '(retained-renderer))
  (check-equal? (probe3d-times (car m-probes)) '(0 5/2 5))
  (define temporary-root
    (make-temporary-file "animate-3d-probes-test-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define output-directory (build-path temporary-root "3d-m"))
     (check-equal?
      (write-3d-probes! 'SCENE-3D-M output-directory #:width 96 #:height 54)
      output-directory)
     (define manifest
       (call-with-input-file (build-path output-directory "manifest.rktd") read))
     (check-equal? (hash-ref manifest 'requested-stage) 'SCENE-3D-M)
     (check-equal? (hash-ref manifest 'renderer-id) 'retained-software-reference)
     (define frames
       (hash-ref (car (hash-ref manifest 'probes)) 'frames))
     (check-equal? (length frames) 3)
     (for ([frame (in-list frames)])
       (check-true (string? (hash-ref frame 'sha1)))
       (check-equal? (string-length (hash-ref frame 'sha1)) 40)
       (check-true
        (file-exists?
         (build-path output-directory
                     "probe-01-retained-renderer"
                     (hash-ref frame 'file))))))
   (lambda () (delete-directory/files temporary-root))))
