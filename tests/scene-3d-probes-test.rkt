#lang racket/base

;;; SCENE-3D: stage-aware visual-probe evidence

(require racket/file
         rackunit
         "../tools/run-3d-probes.rkt")

(module+ test
  (check-equal?
   known-3d-probe-stages
   '(SCENE-3D-B SCENE-3D-C SCENE-3D-D SCENE-3D-E SCENE-3D-F SCENE-3D-G
     SCENE-3D-H SCENE-3D-I SCENE-3D-J SCENE-3D-K SCENE-3D-L SCENE-3D-M
     SCENE-3D-N SCENE-3D-O SCENE-3D-P))
  (define m-probes (stage->probes 'SCENE-3D-M))
  (check-equal? (map probe3d-id m-probes) '(retained-renderer))
  (check-equal? (probe3d-times (car m-probes)) '(0 5/2 5))
  (define temporary-root
    (make-temporary-file "animate-3d-probes-test-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define m-directory (build-path temporary-root "3d-m"))
     (check-equal?
      (write-3d-probes! 'SCENE-3D-M m-directory #:width 96 #:height 54)
      m-directory)
     (define m-manifest
       (call-with-input-file (build-path m-directory "manifest.rktd") read))
     (check-equal? (hash-ref m-manifest 'requested-stage) 'SCENE-3D-M)
     (check-equal? (hash-ref m-manifest 'renderer-id) 'retained-software-reference)
     (define m-frames
       (hash-ref (car (hash-ref m-manifest 'probes)) 'frames))
     (check-equal? (length m-frames) 3)
     (for ([frame (in-list m-frames)])
       (check-true (string? (hash-ref frame 'sha1)))
       (check-equal? (string-length (hash-ref frame 'sha1)) 40)
       (check-true
        (file-exists?
         (build-path m-directory "probe-01-retained-renderer"
                     (hash-ref frame 'file)))))

     (define n-directory (build-path temporary-root "3d-n"))
     (check-equal?
      (write-3d-probes! 'SCENE-3D-N n-directory #:width 96 #:height 54)
      n-directory)
     (define n-manifest
       (call-with-input-file (build-path n-directory "manifest.rktd") read))
     (check-equal? (hash-ref n-manifest 'requested-stage) 'SCENE-3D-N)
     (define n-frames
       (hash-ref (car (hash-ref n-manifest 'probes)) 'frames))
     (for ([frame (in-list n-frames)])
       (define descriptions (hash-ref frame 'renderer-fingerprints))
       (check-true (positive? (hash-ref (car descriptions) 'geometry-count)))
       (check-true (positive? (hash-ref (car descriptions) 'instance-count)))
       (check-true (pair? (hash-ref (car descriptions) 'geometry-keys))))

     (define o-directory (build-path temporary-root "3d-o"))
     (check-equal?
      (write-3d-probes! 'SCENE-3D-O o-directory #:width 96 #:height 54)
      o-directory)
     (define o-manifest
       (call-with-input-file (build-path o-directory "manifest.rktd") read))
     (check-equal? (hash-ref o-manifest 'requested-stage) 'SCENE-3D-O)
     (define o-probes (hash-ref o-manifest 'probes))
     (check-equal? (length o-probes) 8)
     (for ([probe (in-list o-probes)])
       (for ([frame (in-list (hash-ref probe 'frames))])
         (define descriptions (hash-ref frame 'renderer-fingerprints))
         (check-true (pair? descriptions))
         (check-true (exact-nonnegative-integer?
                      (hash-ref (car descriptions) 'stroke-command-count)))
         (check-true (list? (hash-ref (car descriptions) 'stroke-width-modes))))))
   (lambda () (delete-directory/files temporary-root))))
