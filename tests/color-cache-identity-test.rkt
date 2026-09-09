#lang racket/base

;;;
;;; Theme Cache Identity Tests
;;;

(require rackunit
         "../authoring.rkt"
         "../colors.rkt"
         "../main.rkt"
         "../preview.rkt"
         "../private/section-renderer.rkt")

(module+ test
  (define warm
    (color-theme #:id 'cache-warm
                 #:extends animate-light-theme
                 #:palette (color-palette #:id 'cache-warm-palette
                                          #:extends animate-palette
                                          #:colors (hash 'aqua-c "#d02020"))))
  (define cool
    (color-theme #:id 'cache-cool
                 #:extends animate-light-theme
                 #:palette (color-palette #:id 'cache-cool-palette
                                          #:extends animate-palette
                                          #:colors (hash 'aqua-c "#2060d0"))))
  (define timeline
    (make-authored-timeline
     (scene-wait
      (scene-add (make-scene) (circle #:id 'dot #:fill aqua-c #:stroke #f))
      1)
     #:sections (list (section 'only 0 1))))
  (define entry (timeline-section timeline 'only))
  (check-not-equal?
   (automatic-section-cache-key timeline entry #:fps 1 #:camera #f
                                #:renderers '() #:theme warm
                                #:asset-files '())
   (automatic-section-cache-key timeline entry #:fps 1 #:camera #f
                                #:renderers '() #:theme cool
                                #:asset-files '()))
  (define document (make-preview-document (authored-timeline-scene timeline)))
  (define sample (frame-sample 0 1))
  (check-not-equal?
   (make-preview-frame-key document 0 sample
                           (make-preview-render-spec #:fps 1 #:theme warm))
   (make-preview-frame-key document 0 sample
                           (make-preview-render-spec #:fps 1 #:theme cool))))
