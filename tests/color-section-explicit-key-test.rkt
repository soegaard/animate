#lang racket/base

;;;
;;; Explicit Section Cache Appearance Tests
;;;

;; A caller cache key names authored source, never the rendering context. These
;; checks use the same theme ID deliberately: only its resolved appearance is
;; allowed to decide whether a prior PNG can be reused.

(require racket/class
         racket/draw
         racket/file
         rackunit
         "../authoring.rkt"
         "../colors.rkt"
         "../main.rkt"
         "../render.rkt")

(define (center-argb path)
  (define bitmap (read-bitmap path))
  (define pixels (make-bytes 4))
  (send bitmap get-argb-pixels 40 30 1 1 pixels)
  (bytes->list pixels))

(define (accent-theme colour [display-name "Cache fixture"])
  (color-theme #:id 'same-id-different-appearance
               #:extends animate-light-theme
               #:display-name display-name
               #:roles (hash 'accent colour)))

(define timeline
  (make-authored-timeline
   (scene-wait
    (scene-add
     (make-scene #:camera (make-camera #:width 80 #:height 60 #:world-width 4))
     (circle #:id 'dot #:radius 1 #:fill theme-accent #:stroke #f))
    1)
   #:sections (list (section 'only 0 1))))

(module+ test
  (define warm (accent-theme "#d02020"))
  (define cool (accent-theme "#2060d0"))
  (define equivalent (accent-theme "#2060d0" "Different display metadata"))
  (define root (make-temporary-file "animate-explicit-section-~a" 'directory))
  (define disabled-root
    (make-temporary-file "animate-disabled-section-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define warm-first
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:theme warm #:cache-key 'opaque-source-v1))
     (define warm-pixel (center-argb (car (section-render-report-paths warm-first))))
     (check-false (section-render-report-cache-hit? warm-first))
     (define warm-second
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:theme warm #:cache-key 'opaque-source-v1))
     (check-true (section-render-report-cache-hit? warm-second))
     ;; The same source identity must miss under a different appearance even
     ;; though both theme snapshots intentionally share their ID.
     (define cool-first
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:theme cool #:cache-key 'opaque-source-v1))
     (check-false (section-render-report-cache-hit? cool-first))
     (check-not-equal?
      warm-pixel
      (center-argb (car (section-render-report-paths cool-first))))
     (define cool-second
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:theme cool #:cache-key "opaque-source-v1"))
     ;; A string is a different caller source identity from the original
     ;; symbol, and therefore misses once before it can be reused.
     (check-false (section-render-report-cache-hit? cool-second))
     (define cool-string-reuse
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:theme cool #:cache-key "opaque-source-v1"))
     (check-true (section-render-report-cache-hit? cool-string-reuse))
     ;; Non-appearance metadata does not invalidate a compatible artifact.
     (define equivalent-hit
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:theme equivalent #:cache-key "opaque-source-v1"))
     (check-true (section-render-report-cache-hit? equivalent-hit))
     ;; Disabled caching always renders and leaves no reusable manifest.
     (define disabled-first
       (render-timeline-section/report!
        timeline 'only disabled-root #:fps 1 #:theme warm #:cache-key #f))
     (define disabled-second
       (render-timeline-section/report!
        timeline 'only disabled-root #:fps 1 #:theme warm #:cache-key #f))
     (check-false (section-render-report-cache-hit? disabled-first))
     (check-false (section-render-report-cache-hit? disabled-second))
     (check-false
      (file-exists? (build-path disabled-root ".animate-section-cache.rktd")))
     ;; Theme validation happens before a matching manifest can be accepted.
     (check-exn
      exn:fail:contract?
      (lambda ()
        (render-timeline-section/report!
         timeline 'only root #:fps 1 #:theme 'not-a-theme
         #:cache-key "opaque-source-v1"))))
   (lambda ()
     (delete-directory/files root)
     (delete-directory/files disabled-root))))
