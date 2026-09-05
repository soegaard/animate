#lang racket/base

;;;
;;; SCENE-EM Example Public Imports
;;;

;; Examples teach public module boundaries. They may use their local run-demo
;; helper, but they must never reach into animate's private implementation.

(require rackunit
         racket/file
         racket/runtime-path
         racket/string)

(define-runtime-path examples-directory "../examples")

(define render-operation-pattern
  #px"(render-frames!?|render-frames/report!?|render-frame-indices!?|render-frame-indices/report!?|render-diagnostics(?:-|\\?)|encode-mp4!|assemble-authored-mp4!|mux-authored-video!|concatenate-mp4!|render-authored-mp4!)")

(define obsolete-local-public-module-pattern
  #px"\\.\\./(?:\\.\\./)?(?:main|authoring|preview|render|project|experimental)\\.rkt")

(define (example-source-files)
  (find-files
   (lambda (path)
     (and (file-exists? path)
          (or (regexp-match? #px"\\.rkt$" (path->string path))
              (regexp-match? #px"\\.rhm$" (path->string path)))))
   examples-directory))

(module+ test
  (for ([path (in-list (example-source-files))])
    (define source (file->string path))
    (check-false
     (regexp-match? #px"(?:animate/|\\.\\./)private/" source)
     (path->string path))
    ;; A checkout's examples are author-facing documentation. They exercise
    ;; installed public collection paths, not a relative hop around package
    ;; boundaries to a neighbouring implementation module. The local run-demo
    ;; helper is still allowed because it is not an Animate API module.
    (check-false
     (regexp-match? obsolete-local-public-module-pattern source)
     (path->string path))
    (when (regexp-match? render-operation-pattern source)
      (check-true
       (regexp-match? #px"(?:animate/render|render\\.rkt)" source)
       (path->string path)))))
