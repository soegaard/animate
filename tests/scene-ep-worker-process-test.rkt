#lang racket/base

;;;
;;; SCENE-EP Isolated Project Worker
;;;

(require rackunit
         racket/async-channel
         racket/class
         racket/draw
         racket/runtime-path
         "../main.rkt"
         "../preview.rkt"
         "../private/preview-model.rkt"
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

(module+ test
  ;; Two controller lanes can safely borrow separate module workers.  The
  ;; workers render in independent Racket processes; this is intentionally not
  ;; implemented with two racket/draw threads in the parent process.
  (define pool
    (make-project-worker-producer fixture 'worker-scene
                                  #:fingerprint 'worker-pool-test
                                  #:workers 2))
  (dynamic-wind
   void
   (lambda ()
     (define completed (make-async-channel))
     (define document (make-preview-document (make-scene)))
     (define spec (make-preview-render-spec #:fps 2 #:pixel-scale 1/4))
     (for ([frame (in-list '(0 1))])
       (thread
        (lambda ()
          (define request
            (preview-render-request #:id (add1 frame)
                                    #:document-generation 0
                                    #:render-generation 0
                                    #:sample (frame-sample frame 2)
                                    #:quality full-preview-quality
                                    #:priority 0))
          (async-channel-put
           completed
           (project-worker-producer-produce
            pool document (frame-sample frame 2) spec
            (preview-render-request-cancellation-token request))))))
     (for ([ignored (in-range 2)])
       (define bitmap (sync/timeout 15 completed))
       (check-true (is-a? bitmap bitmap%))))
   (lambda () (project-worker-producer-close! pool))))
