#lang racket/base

;;;
;;; Preview Theme Switching Tests
;;;

(require rackunit
         "../colors.rkt"
         "../main.rkt"
         "../preview.rkt")

(module+ test
  (define warm
    (color-theme #:id 'preview-warm
                 #:extends animate-light-theme
                 #:palette (color-palette #:id 'preview-warm-palette
                                          #:extends animate-palette
                                          #:colors (hash 'aqua-c "#d02020"))))
  (define cool
    (color-theme #:id 'preview-cool
                 #:extends animate-light-theme
                 #:palette (color-palette #:id 'preview-cool-palette
                                          #:extends animate-palette
                                          #:colors (hash 'aqua-c "#2060d0"))))
  (define session
    (open-preview-controller
     (scene-wait (make-scene) 1)
     #:theme warm
     #:prefetch 0
     #:producer (lambda (_document _sample _spec _token) 'frame)
     #:byte-size (lambda (_value) 1)))
  (dynamic-wind
   void
   (lambda ()
     (check-eq? (preview-color-theme session) warm)
     (define before (preview-session-status session))
     (define after (preview-set-color-theme! session cool))
     (check-eq? (preview-color-theme session) cool)
     (check-true (> (preview-status-render-generation after)
                    (preview-status-render-generation before))))
   (lambda () (preview-close! session))))
