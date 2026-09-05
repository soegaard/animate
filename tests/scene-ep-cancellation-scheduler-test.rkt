#lang racket/base

;;;
;;; SCENE-EP Cooperative Cancellation Scheduler
;;;

(require racket/async-channel
         rackunit
         "../main.rkt"
         "../preview.rkt")

(define (await channel)
  (or (sync/timeout 2 channel)
      (error 'scene-ep-cancellation-scheduler-test "timed out")))

(module+ test
  (define started (make-async-channel))
  (define exact-events (make-async-channel))
  (define scene (scene-wait (make-scene) 2))
  (define session
    (open-preview-controller
     scene #:fps 2 #:prefetch 0
     #:producer
     (lambda (_document sample _spec token)
       (async-channel-put started (cons sample token))
       (if (zero? (frame-sample-frame-index sample))
           ;; This deliberately behaves like a cancellable expensive built-in:
           ;; it only exits when it reaches a documented coarse boundary.
           (let loop ()
             (check-cancellation token)
             (sleep 1/100)
             (loop))
           'latest-frame))
     #:byte-size (lambda (_value) 1)
     #:on-event (lambda (event) (async-channel-put exact-events event))))
  (define first (await started))
  (check-equal? (car first) (frame-sample 0 2))
  (void (preview-seek-frame! session 2))
  (check-true (cancellation-requested? (cdr first)))
  (check-equal? (cancellation-reason (cdr first)) 'superseded)
  (define second (await started))
  (check-equal? (car second) (frame-sample 2 2))
  (let loop ()
    (define event (await exact-events))
    (unless (eq? (preview-event-kind event) 'frame-ready) (loop)))
  (check-equal? (preview-current-bitmap session) 'latest-frame)
  (check-equal? (preview-displayed-sample session) (frame-sample 2 2))
  (define diagnostics (preview-session-diagnostics session))
  (check-equal? (hash-ref diagnostics 'desired-frame) 2)
  (check-equal? (hash-ref diagnostics 'displayed-frame) 2)
  (check-equal? (hash-ref diagnostics 'visual-lag-milliseconds) 0)
  (check-true
   (hash-has-key? (hash-ref diagnostics 'recent-render-diagnostics)
                  'render-milliseconds))
  (check-equal? (preview-canceled-request-count session) 1)
  (define trace-events (hash-ref (preview-session-trace session) 'events))
  (check-true (pair? trace-events))
  (check-not-false
   (member 'superseded-request
           (map (lambda (entry) (hash-ref entry 'kind)) trace-events)))
  (preview-close! session))

(module+ test
  ;; Exact playback advances only after a frame becomes available. A simple
  ;; fake renderer lets the actor prove that semantic time is not tied to a
  ;; wall-clock timeout in this mode.
  (define exact
    (open-preview-controller
     (scene-wait (make-scene) 1) #:fps 2 #:prefetch 0 #:playback-policy 'exact
     #:producer (lambda (_document sample _spec _token) sample)
     #:byte-size (lambda (_value) 1)))
  (check-eq? (preview-playback-policy exact) 'exact)
  (void (preview-play! exact))
  (let loop ([remaining 20])
    (when (and (preview-playing? exact) (positive? remaining))
      (sleep 1/100)
      (loop (sub1 remaining))))
  (check-false (preview-playing? exact))
  (check-equal? (preview-current-frame exact) 1)
  (void (preview-set-playback-policy! exact 'realtime))
  (check-eq? (preview-playback-policy exact) 'realtime)
  (preview-close! exact))

(module+ test
  ;; A marked loop stores semantic half-open endpoints, while the controller
  ;; alone rounds them to its frame grid. Exact mode makes the wrap order
  ;; deterministic without depending on wall-clock scheduling.
  (define loop-events (make-async-channel))
  (define looping
    (open-preview-controller
     (scene-wait (make-scene) 1) #:fps 2 #:prefetch 0 #:playback-policy 'exact
     #:producer (lambda (_document sample _spec _token) sample)
     #:byte-size (lambda (_value) 1)
     #:on-event (lambda (event) (async-channel-put loop-events event))))
  ;; Drain the paused initial frame before observing the loop itself.
  (let loop ()
    (define event (await loop-events))
    (unless (eq? (preview-event-kind event) 'frame-ready) (loop)))
  (check-equal? (preview-loop-range looping) #f)
  (check-equal? (preview-set-loop-range! looping 0 1)
                (preview-playback-range 0 1))
  (check-equal? (preview-loop-range looping) (preview-playback-range 0 1))
  (void (preview-set-playback-speed! looping 3/2))
  (check-equal? (preview-playback-speed looping) 3/2)
  (void (preview-play! looping))
  (define (next-loop-frame)
    (let loop ()
      (define event (await loop-events))
      (if (eq? (preview-event-kind event) 'frame-ready)
          (frame-sample-frame-index (preview-event-bitmap event))
          (loop))))
  (check-equal? (list (next-loop-frame) (next-loop-frame) (next-loop-frame))
                '(0 1 0))
  (check-true (preview-status-looping? (preview-session-status looping)))
  (void (preview-pause! looping))
  (check-false (preview-status-looping? (preview-session-status looping)))
  (void (preview-clear-loop-range! looping))
  (check-equal? (preview-loop-range looping) #f)
  (check-exn exn:fail:contract?
             (lambda () (preview-set-playback-speed! looping 0)))
  (preview-close! looping))

(module+ test
  ;; A burst of slider-style scrub requests uses a lower bitmap scale only
  ;; while the playhead is moving. After the configured idle interval the
  ;; controller requests the identical semantic frame at its full configured
  ;; scale, with a distinct cache key.
  (define requests (make-async-channel))
  (define adaptive
    (open-preview-controller
     (scene-wait (make-scene) 2)
     #:fps 2 #:prefetch 0 #:settle-milliseconds 40
     #:producer
     (lambda (_document sample spec _token)
       (async-channel-put
        requests
        (list (and (frame-sample? sample) (frame-sample-frame-index sample))
              (preview-render-spec-pixel-scale spec)))
       sample)
     #:byte-size (lambda (_value) 1)))
  ;; Initial paused inspection is full quality.
  (check-equal? (await requests) '(0 1))
  (void (preview-scrub-frame! adaptive 2))
  (check-equal? (await requests) '(2 1/2))
  (check-eq? (preview-quality-name (preview-current-quality adaptive)) 'draft)
  (sleep 1/10)
  (check-equal? (await requests) '(2 1))
  (check-eq? (preview-quality-name (preview-current-quality adaptive)) 'full)
  (preview-close! adaptive))
