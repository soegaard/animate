#lang racket/base

;; SCENE-EH-4 and EH-5: loading occurs in a fresh namespace, but its animate
;; values retain host type identity. A failed replacement cannot dislodge the
;; last known-good immutable compiled scene.

(require rackunit
         racket/file
         racket/path
         "../main.rkt"
         "../authoring.rkt")

(define (write-program! path second-duration)
  (call-with-output-file
   path
   #:exists 'truncate/replace
   (lambda (out)
     (display "#lang racket/base\n" out)
     (display "(require animate animate/authoring)\n" out)
     (display "(define-scene-program hot-program\n" out)
     (display "  #:initial (make-scene)\n" out)
     (display "  (scene-block stable (scene)\n" out)
     (display "    (scene-wait scene 1))\n" out)
     (fprintf out "  (scene-block changed (scene)~n    (scene-wait scene ~a)))~n"
              second-duration)
     (display "(provide hot-program)\n" out))))

(module+ test
  (define temporary-directory (simplify-path (build-path (current-directory) ".." "tmp")))
  (make-directory* temporary-directory)
  (define source-path
    (make-temporary-file "scene-eh-loader-~a.rkt" #f temporary-directory))
  (dynamic-wind
    void
    (lambda ()
      (write-program! source-path 2)
      (define first (load-scene-program source-path 'hot-program))
      (check-true
       (scene? (compiled-scene-program-scene
                (scene-program-loader-compiled first))))
      (check-equal? (scene-duration
                     (compiled-scene-program-scene
                      (scene-program-loader-compiled first)))
                    3)

      ;; Only the suffix source slice changes. The first block checkpoint is
      ;; reused even though the user module has been instantiated afresh.
      (write-program! source-path 3)
      (define second (reload-scene-program first))
      (check-equal? (scene-duration
                     (compiled-scene-program-scene
                      (scene-program-loader-compiled second)))
                    4)
      (check-true
       (scene-block-run-reused?
        (compiled-program-block (scene-program-loader-compiled second) 'stable)))
      (check-false
       (scene-block-run-reused?
        (compiled-program-block (scene-program-loader-compiled second) 'changed)))

      ;; An invalid source is reported as a new candidate failure. `second` is
      ;; still a usable last-good loader and can render/inspect its scene.
      (call-with-output-file source-path #:exists 'truncate/replace
        (lambda (out) (display "#lang racket/base\n(define broken" out)))
      (check-exn exn:fail:scene-program-loader?
                 (lambda () (reload-scene-program second)))
      (check-equal? (scene-duration
                     (compiled-scene-program-scene
                      (scene-program-loader-compiled second)))
                    4)
      (scene-program-loader-close! first)
      (scene-program-loader-close! second))
    (lambda ()
      (when (file-exists? source-path)
        (delete-file source-path)))))
