#lang racket/base

;; SCENE-EG-2: controller ownership, generation safety, and queue semantics.

(require racket/async-channel
         rackunit
         "../main.rkt"
         "../preview.rkt")

(define (await channel)
  (or (sync/timeout 2 channel)
      (error 'scene-eg-controller-test "timed out waiting for preview event")))

(define (await-frame-ready events)
  (let loop ()
    (define event (await events))
    (if (eq? (preview-event-kind event) 'frame-ready)
        event
        (loop))))

(module+ test
  (define scene (scene-wait (make-scene) 2))

  ;; The controller accepts nonmonotone exact-frame requests.  The event source
  ;; is deliberately a fake renderer, so no GUI or bitmap backend is required.
  (define events (make-async-channel))
  (define session
    (open-preview-controller
     scene #:fps 2 #:prefetch 0 #:cache-megabytes 1
     #:producer
     (lambda (document sample spec)
       (list (preview-document-generation document) sample))
     #:byte-size (lambda (value) 8)
     #:on-event (lambda (event) (async-channel-put events event))))
  (check-equal? (preview-current-frame session) 0)
  (check-equal? (preview-event-bitmap (await-frame-ready events))
                (list 0 (frame-sample 0 2)))
  (void (preview-seek-frame! session 3))
  (check-equal? (preview-event-bitmap (await-frame-ready events))
                (list 0 (frame-sample 3 2)))
  (void (preview-seek-frame! session 1))
  (check-equal? (preview-event-bitmap (await-frame-ready events))
                (list 0 (frame-sample 1 2)))
  (check-equal? (preview-current-frame session) 1)
  (void (preview-play-range! session 1/2 3/2))
  (void (preview-pause! session))
  (check-false (preview-playing? session))
  (preview-close! session)
  (check-false (preview-open? session))
  (check-exn exn:fail:contract?
             (lambda () (preview-current-time session)))

  ;; An in-flight result from an older document generation is discarded, and
  ;; source replacement overtakes queued work from the old source.
  (define requests (make-async-channel))
  (define releases (make-async-channel))
  (define stale-events (make-async-channel))
  (define gated-session
    (open-preview-controller
     scene #:fps 2 #:prefetch 0 #:cache-megabytes 1
     #:producer
     (lambda (document sample spec)
       (async-channel-put requests (list (preview-document-generation document) sample))
       (async-channel-get releases))
     #:byte-size (lambda (value) 8)
     #:on-event (lambda (event) (async-channel-put stale-events event))))
  (check-equal? (await requests) (list 0 (frame-sample 0 2)))
  (void (preview-seek-frame! gated-session 1))
  (void (preview-set-source! gated-session (scene-wait (make-scene) 2)))
  (async-channel-put releases 'obsolete)
  ;; The old worker finishes first, but the next submitted job belongs to the
  ;; source generation installed after it began.
  (define replacement-request (await requests))
  (check-equal? (car replacement-request) 1)
  (async-channel-put releases 'replacement)
  (define replacement-event (await-frame-ready stale-events))
  (check-equal? (preview-status-document-generation
                 (preview-event-status replacement-event))
                1)
  (check-equal? (preview-event-bitmap replacement-event) 'replacement)
  (check-equal? (preview-current-bitmap gated-session) 'replacement)
  (preview-close! gated-session)

  ;; The private cache policy is exercised through a tiny byte budget: a newer
  ;; frame remains current, but a previous frame must be rendered again after
  ;; it has been evicted.
  (define render-count 0)
  (define cache-events (make-async-channel))
  (define cache-session
    (open-preview-controller
     scene #:fps 2 #:prefetch 0 #:cache-megabytes 1/1000000
     #:producer
     (lambda (document sample spec)
       (set! render-count (add1 render-count))
       (list render-count sample))
     #:byte-size (lambda (value) 8)
     #:on-event (lambda (event) (async-channel-put cache-events event))))
  (void (await-frame-ready cache-events))
  (void (preview-seek-frame! cache-session 1))
  (void (await-frame-ready cache-events))
  (void (preview-seek-frame! cache-session 0))
  (void (await-frame-ready cache-events))
  (check-equal? render-count 3)
  (preview-close! cache-session))
