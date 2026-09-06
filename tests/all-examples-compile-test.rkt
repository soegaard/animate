#lang racket/base

;;;
;;; SCENE-EM Racket Example Compilation Tests
;;;

;; Rhombus sources have their own optional toolchain and are intentionally
;; omitted by info.rkt. Every ordinary Racket example must at least expand and
;; instantiate its declaration module without starting its module+ main output.

(require rackunit
         racket/file
         racket/list
         racket/path
         racket/runtime-path)

(define-runtime-path examples-directory "../examples")

(define (racket-example-paths)
  (sort
   (append
    (for/list ([path (in-list (directory-list examples-directory #:build? #t))]
               #:when (and (file-exists? path)
                           (equal? (path-get-extension path) #".rkt")))
      path)
    ;; Spatial examples live below an intentional topical directory.  Keep
    ;; those public declarations in the ordinary example compilation gate.
    (for/list ([path (in-list (directory-list (build-path examples-directory "3d")
                                              #:build? #t))]
               #:when (and (file-exists? path)
                           (equal? (path-get-extension path) #".rkt")))
      path))
   path<?))

(module+ test
  (define paths (racket-example-paths))
  (check-true (pair? paths))
  (for ([path (in-list paths)])
    (check-not-exn
     (lambda () (dynamic-require path #f))
     (path->string path))))
