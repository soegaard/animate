#lang racket/base

;;;
;;; SCENE-BQ/BR Concurrent Frame Output and Diagnostics Tests
;;;

(require racket/file
         rackunit
         "../main.rkt")

(module+ test
  (define viewport
    (make-camera #:width 180 #:height 100 #:world-width 12 #:background "white"))
  ;; Position changes do not change the plain-text appearance cache key, which
  ;; makes resource-cache telemetry deterministic even with several workers.
  (define label
    (plain-text "parallel output"
                #:id 'label
                #:center (vec2 -3 0)
                #:font-size 3/4
                #:color "navy"))
  (define animation
    (scene-play
     (scene-add (make-scene #:camera viewport) label)
     (move-to label (vec2 3 0))
     #:duration 2))
  (define root (make-temporary-file "animate-render-jobs~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define parallel-directory (build-path root "parallel"))
      (define sequential-directory (build-path root "sequential"))
      (define report
        (render-frames/report! animation parallel-directory #:fps 2 #:workers 3))
      (check-true (render-diagnostics? report))
      (check-equal? (render-diagnostics-frame-count report) 4)
      (check-equal? (render-diagnostics-workers report) 3)
      (check-equal? (length (render-diagnostics-paths report)) 4)
      (check-equal? (length (render-diagnostics-frame-milliseconds report)) 4)
      (check-true (andmap (lambda (value) (>= value 0))
                           (render-diagnostics-frame-milliseconds report)))
      (check-true (>= (render-diagnostics-elapsed-milliseconds report) 0))
      ;; One text appearance is loaded once and reused by the remaining frames.
      (check-equal? (render-diagnostics-cache-misses report) 1)
      (check-equal? (render-diagnostics-cache-hits report) 3)
      (check-equal? (render-diagnostics-cache-evictions report) 0)
      (define sequential-paths
        (render-frames! animation sequential-directory #:fps 2 #:workers 1))
      ;; Concurrent writing does not change file names, ordering, or pixels.
      (check-equal?
       (for/list ([path (in-list (render-diagnostics-paths report))])
         (file->bytes path))
       (for/list ([path (in-list sequential-paths)])
         (file->bytes path)))
      (define empty-report
        (render-frames/report! (make-scene) (build-path root "empty") #:workers 4))
      (check-equal? (render-diagnostics-paths empty-report) '())
      (check-equal? (render-diagnostics-workers empty-report) 0)
      (check-exn exn:fail:contract?
                 (lambda ()
                   (render-frames! animation (build-path root "bad") #:workers 0))))
    (lambda ()
      (delete-directory/files root))))
