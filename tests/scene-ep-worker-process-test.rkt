#lang racket/base

;;;
;;; SCENE-EP Isolated Project Worker
;;;

(require rackunit
         racket/class
         racket/draw
         racket/runtime-path
         "../preview.rkt"
         "../private/preview-worker-process.rkt")

(define-runtime-path fixture "fixtures/preview-worker-scene.rkt")

(module+ test
  (define worker
    (start-project-preview-worker fixture 'worker-scene
                                  #:fingerprint 'worker-test))
  (dynamic-wind
   void
   (lambda ()
     (check-true (preview-worker-open? worker))
     (define request
       (preview-render-request #:id 17
                               #:document-generation 0
                               #:render-generation 3
                               #:sample (frame-sample 0 2)
                               #:quality full-preview-quality
                               #:priority 0))
     (define-values (bitmap diagnostics)
       (preview-worker-render-frame!
        worker request
        (make-preview-render-spec #:fps 2 #:pixel-scale 1/2)))
     (check-true (is-a? bitmap bitmap%))
     (check-equal? (send bitmap get-width) 640)
     (check-true (hash-has-key? diagnostics 'render-milliseconds))
     ;; A timeout is a distinct terminal request outcome. The parent has
     ;; already replaced the process before reporting it, so the same worker
     ;; is immediately usable for a later current-frame request.
     (check-exn exn:fail:preview-worker-timed-out?
                (lambda ()
                  (preview-worker-render-frame!
                   worker request
                   (make-preview-render-spec #:fps 2 #:pixel-scale 1/2)
                   #:timeout-milliseconds 1)))
     (check-true (preview-worker-open? worker))
     ;; The timeout restart itself—not a later manual restart—must leave a
     ;; fresh process able to render the next current request. Use a distinct
     ;; request identity, just as the controller does, so an old queued reply
     ;; can never be mistaken for the post-recovery frame.
     (define recovery-request
       (preview-render-request #:id 18
                               #:document-generation 0
                               #:render-generation 3
                               #:sample (frame-sample 0 2)
                               #:quality full-preview-quality
                               #:priority 0))
     (define-values (recovered _diagnostics)
       (preview-worker-render-frame!
        worker recovery-request
        (make-preview-render-spec #:fps 2 #:pixel-scale 1/4)))
     (check-equal? (send recovered get-width) 320))
   (lambda () (preview-worker-stop! worker))))
