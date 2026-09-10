#lang racket/base

;;;
;;; Semantic Typography Preview-Worker Transport Tests
;;;

(require racket/class
         racket/runtime-path
         rackunit
         "../main.rkt"
         "../preview.rkt"
         "../private/preview-worker-process.rkt")

(define-runtime-path fixture "fixtures/preview-worker-typography-scene.rkt")

(define (bitmap-bytes bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define bytes (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height bytes)
  bytes)

(module+ test
  (define enlarged-title-theme
    (typography-theme
     #:id 'worker-enlarged-title
     #:extends animate-typography-theme
     #:styles
     (hash 'title
           (text-style-update
            (typography-ref animate-typography-theme 'title)
            #:font-size 3/2))))
  (define worker
    (start-project-preview-worker fixture 'worker-typography-scene
                                  #:fingerprint 'typography-worker))
  (dynamic-wind
   void
   (lambda ()
     (define (render id typography)
       (preview-worker-render-frame!
        worker
        (preview-render-request #:id id #:document-generation 0
                                #:render-generation id #:sample (frame-sample 0 1)
                                #:quality full-preview-quality #:priority 0)
        (make-preview-render-spec #:fps 1 #:typography typography)))
     (define-values (default-bitmap _default-diagnostics)
       (render 1 animate-typography-theme))
     (define-values (enlarged-bitmap _enlarged-diagnostics)
       (render 2 enlarged-title-theme))
     (check-not-equal? (bitmap-bytes default-bitmap)
                       (bitmap-bytes enlarged-bitmap)))
   (lambda () (preview-worker-stop! worker))))
