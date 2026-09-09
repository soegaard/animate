#lang racket/base

;;;
;;; Themed Section Rendering Tests
;;;

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

(module+ test
  (define warm
    (color-theme #:id 'section-warm
                 #:extends animate-light-theme
                 #:palette (color-palette #:id 'section-warm-palette
                                          #:extends animate-palette
                                          #:colors (hash 'aqua-c "#d02020"))))
  (define cool
    (color-theme #:id 'section-cool
                 #:extends animate-light-theme
                 #:palette (color-palette #:id 'section-cool-palette
                                          #:extends animate-palette
                                          #:colors (hash 'aqua-c "#2060d0"))))
  (define timeline
    (make-authored-timeline
     (scene-wait
      (scene-add
       (make-scene #:camera (make-camera #:width 80 #:height 60 #:world-width 4))
       (circle #:id 'dot #:radius 1 #:fill aqua-c #:stroke #f))
      1)
     #:sections (list (section 'only 0 1))))
  (define root (make-temporary-file "animate-themed-section-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define warm-report
       (render-timeline-section/report! timeline 'only root #:fps 1 #:theme warm))
     (define warm-pixel (center-argb (car (section-render-report-paths warm-report))))
     ;; A different appearance must not reuse the prior section manifest.
     (define cool-report
       (render-timeline-section/report! timeline 'only root #:fps 1 #:theme cool))
     (check-false (section-render-report-cache-hit? cool-report))
     (check-not-equal?
      warm-pixel
      (center-argb (car (section-render-report-paths cool-report)))))
   (lambda () (delete-directory/files root))))
