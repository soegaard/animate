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
     (lambda (document sample _spec _cancellation-token)
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
     (lambda (document sample _spec _cancellation-token)
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
     (lambda (document sample _spec _cancellation-token)
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
  (preview-close! cache-session)

  ;; A producer that explicitly opts into two render lanes receives two
  ;; prefetched frame requests at once. Production uses this only with the
  ;; isolated software-worker pool; this small fake keeps the scheduling
  ;; contract deterministic and headless.
  (define parallel-starts (make-async-channel))
  (define parallel-releases (make-async-channel))
  (define parallel-session
    (open-preview-controller
     (scene-wait (make-scene) 3)
     #:fps 2 #:prefetch 3 #:render-workers 2
     #:producer
     (lambda (_document sample _spec _cancellation-token)
       (define frame (frame-sample-frame-index sample))
       (if (zero? frame)
           frame
           (begin
             (async-channel-put parallel-starts frame)
             (async-channel-get parallel-releases)
             frame)))
     #:byte-size (lambda (_value) 1)))
  ;; Frame zero completes first. Its prefetch fills both available lanes with
  ;; frames one and two instead of keeping one behind a serial worker.
  (check-equal? (sort (list (await parallel-starts) (await parallel-starts)) <)
                '(1 2))
  (check-equal? (preview-render-worker-count parallel-session) 2)
  ;; A lower menu/API choice preserves in-flight jobs and limits only new
  ;; work. It is therefore safe to make while the cache is being filled.
  (void (preview-set-render-worker-count! parallel-session 1))
  (check-equal? (preview-render-worker-count parallel-session) 1)
  ;; The displayed initial frame extends the horizon by one more job. Release
  ;; all four before closing so this controlled fake cannot hold a controller
  ;; thread.
  (for ([ignored (in-range 4)])
    (async-channel-put parallel-releases 'continue))
  (sleep 1/20)
  (preview-close! parallel-session)

  ;; An exact time seek is what the timeline click sends. Its target and first
  ;; video-grid look-ahead frame occupy both lanes immediately; the controller
  ;; does not wait for the target bitmap before beginning A+1.
  (define eager-starts (make-async-channel))
  (define eager-releases (make-async-channel))
  (define eager-session
    (open-preview-controller
     (scene-wait (make-scene) 3)
     #:fps 2 #:start 5/2 #:prefetch 3 #:render-workers 2
     #:producer
     (lambda (_document sample _spec _cancellation-token)
       (cond
         [(time-sample? sample)
          (if (= (time-sample-time sample) 5/2)
              sample
              (begin
                (async-channel-put eager-starts 'clicked-time)
                (async-channel-get eager-releases)
                sample))]
         [else
          (define frame (frame-sample-frame-index sample))
          (begin
            (async-channel-put eager-starts frame)
            (async-channel-get eager-releases)
            frame)]))
     #:byte-size (lambda (_value) 1)))
  ;; Starting at the final frame avoids an initial look-ahead queue.
  (void (preview-seek! eager-session 1/2))
  (define initial-eager-starts (list (await eager-starts) (await eager-starts)))
  (check-not-false (member 'clicked-time initial-eager-starts))
  (check-not-false (member 2 initial-eager-starts))
  ;; When the clicked frame becomes visible, the scheduler adds the next frame
  ;; after the queued A+1..A+3 run. It keeps the cache horizon moving instead
  ;; of waiting for playback to reach the next frame first.
  (for ([ignored (in-range 5)])
    (async-channel-put eager-releases 'continue))
  (check-equal? (sort (list (await eager-starts)
                            (await eager-starts)
                            (await eager-starts)) <)
                '(3 4 5))
  (sleep 1/20)
  (preview-close! eager-session))
