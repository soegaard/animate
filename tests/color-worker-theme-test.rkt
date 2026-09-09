#lang racket/base

;;;
;;; Subprocess Preview Theme Tests
;;;

(require racket/class
         racket/draw
         racket/runtime-path
         rackunit
         "../colors.rkt"
         "../preview.rkt"
         "../private/preview-worker-process.rkt")

(define-runtime-path fixture "fixtures/preview-worker-theme-scene.rkt")

(define (center-argb bitmap)
  (define pixels (make-bytes 4))
  (send bitmap get-argb-pixels 40 30 1 1 pixels)
  (bytes->list pixels))

(module+ test
  (define warm
    (color-theme #:id 'worker-warm
                 #:extends animate-light-theme
                 #:palette (color-palette #:id 'worker-warm-palette
                                          #:extends animate-palette
                                          #:colors (hash 'aqua-c "#d02020"))))
  (define cool
    (color-theme #:id 'worker-cool
                 #:extends animate-light-theme
                 #:palette (color-palette #:id 'worker-cool-palette
                                          #:extends animate-palette
                                          #:colors (hash 'aqua-c "#2060d0"))))
  (define worker
    (start-project-preview-worker fixture 'worker-theme-scene #:fingerprint 'theme-worker))
  (dynamic-wind
   void
   (lambda ()
     (define (render id theme)
       (preview-worker-render-frame!
        worker
        (preview-render-request #:id id #:document-generation 0
                                #:render-generation id #:sample (frame-sample 0 1)
                                #:quality full-preview-quality #:priority 0)
        (make-preview-render-spec #:fps 1 #:theme theme)))
     (define-values (warm-bitmap _warm-diagnostics) (render 1 warm))
     (define-values (cool-bitmap _cool-diagnostics) (render 2 cool))
     (check-not-equal? (center-argb warm-bitmap) (center-argb cool-bitmap)))
   (lambda () (preview-worker-stop! worker))))
