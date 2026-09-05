#lang racket/base

;;;
;;; SCENE-EP Headless Production Timeline, Audio, and Diagnostics
;;;

(require rackunit
         racket/file
         "../main.rkt"
         "../authoring.rkt"
         "../preview.rkt")

(module+ test
  ;; The clock maps wall time to semantic time without a render loop increment.
  (define clock (preview-clock #:start-time 2 #:start-milliseconds 1000
                               #:speed 3/2 #:running? #t))
  (check-equal? (preview-clock-time clock 3000) 5.0)
  (define paused (preview-clock-pause clock 3000))
  (check-equal? (preview-clock-time paused 9000) 5.0)

  (define scene (scene-wait (make-scene) 8))
  (define timeline
    (make-authored-timeline
     scene
     #:sections (list (section 'intro 0 3) (section 'proof 3 8))
     #:cues (list (cue 'definition 2))
     #:audio-cues
     (list (audio-cue "narration.wav" #:start 1 #:source-start 1/2
                      #:duration 4 #:gain 3/4 #:fade-in 1/2 #:fade-out 1/2))
     #:subtitles (list (subtitle 1 2 "Definition"))))
  (define model
    (make-preview-timeline 8 #:timeline timeline
                           #:blocks (list (list 'setup 0 1) (list 'proof 1 8))
                           #:zoom 2))
  (check-equal? (preview-timeline-duration model) 8)
  (check-equal? (timeline-entry-id (preview-timeline-entry-at model 'cues 2))
                'definition)
  (check-equal? (timeline-entry-id (preview-timeline-entry-at model 'sections 3))
                'proof)
  (check-equal? (preview-timeline-visible-range
                 (preview-timeline-seek model 6))
                (timeline-range 4 8))
  (check-equal? (preview-timeline-range
                 (preview-timeline-select-range model 2 4))
                (timeline-range 2 4))
  ;; Zooming is pure viewport state: it keeps the cursor and selected interval
  ;; instead of rebuilding or retiming semantic lanes.
  (define selected-model (preview-timeline-select-range model 2 4))
  (define zoomed-model (preview-timeline-set-zoom selected-model 4))
  (check-equal? (preview-timeline-zoom zoomed-model) 4)
  (check-equal? (preview-timeline-cursor zoomed-model)
                (preview-timeline-cursor selected-model))
  (check-equal? (preview-timeline-range zoomed-model)
                (timeline-range 2 4))
  ;; A/B markers are immutable editorial state. Saving them never changes the
  ;; selected transport range or the viewport, and clearing one leaves the
  ;; other marker intact.
  (define compared-model
    (preview-timeline-save-comparison
     (preview-timeline-save-comparison selected-model 'a)
     'b))
  (check-equal? (preview-timeline-comparison-range compared-model 'a)
                (timeline-range 2 4))
  (check-equal? (preview-timeline-comparison-range compared-model 'b)
                (timeline-range 2 4))
  (define without-a (preview-timeline-clear-comparison compared-model 'a))
  (check-false (preview-timeline-comparison-range without-a 'a))
  (check-equal? (preview-timeline-comparison-range without-a 'b)
                (timeline-range 2 4))
  (check-exn exn:fail?
             (lambda ()
               (preview-timeline-save-comparison
                (make-preview-timeline 8)
                'a)))

  ;; Audio planning is pure: a nonexistent declared source still yields an
  ;; inspectable plan and matching final/preview placement semantics.
  (define audio-plan (make-preview-audio-plan timeline #:proxy-path "proxy.wav"
                                               #:waveform-path "waveform.dat"))
  (check-equal? (preview-audio-plan-duration audio-plan) 8)
  (check-equal? (preview-audio-cue-gain
                 (car (preview-audio-plan-cue-plan audio-plan))) 3/4)
  (check-true (string? (preview-audio-plan-fingerprint audio-plan)))
  (check-true (regexp-match? #rx"adelay=1000" (preview-audio-filter-graph audio-plan)))

  ;; A mixed proxy must never be reused after a semantic cue edit. The pure
  ;; plan catches timing/style changes, while the effectful cache key below
  ;; additionally catches a source file replaced at the same pathname.
  (define changed-cue-timeline
    (make-authored-timeline
     scene
     #:audio-cues
     (list (audio-cue "narration.wav" #:start 1 #:source-start 1/2
                      #:duration 4 #:gain 1/2 #:fade-in 1/2 #:fade-out 1/2))))
  (check-not-equal?
   (preview-audio-plan-fingerprint audio-plan)
   (preview-audio-plan-fingerprint
    (make-preview-audio-plan changed-cue-timeline
                             #:proxy-path "other-proxy.wav")))
  (define fingerprint-source
    (make-temporary-file "scene-ep-audio-fingerprint-~a.wav"))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file fingerprint-source
       (lambda (out) (write-bytes #"first recording" out))
       #:exists 'truncate/replace)
     (define fingerprint-timeline
       (make-authored-timeline
        scene
        #:audio-cues (list (audio-cue fingerprint-source #:duration 1))))
     (define fingerprint-plan
       (make-preview-audio-plan fingerprint-timeline #:proxy-path "proxy.wav"))
     (define key-before (preview-audio-proxy-cache-key fingerprint-plan))
     (call-with-output-file fingerprint-source
       (lambda (out) (write-bytes #"replaced recording" out))
       #:exists 'truncate/replace)
     (check-not-equal? key-before
                       (preview-audio-proxy-cache-key fingerprint-plan)))
   (lambda ()
     (when (file-exists? fingerprint-source) (delete-file fingerprint-source))))

  (define peaks
    (waveform-from-samples '(0 -1 1 1/2 -1/2 0) #:bucket-sizes '(2 4)))
  (check-equal? (waveform-level-samples-per-bucket
                 (waveform-level-for-width peaks 2)) 4)
  (check-equal? (vector-ref (waveform-level-minima (car (waveform-levels peaks))) 0) -1)

  ;; A cached waveform is a first-class timeline lane, not a decoration
  ;; inferred by the GUI from the audio cue rectangles.  It has the complete
  ;; timeline extent and retains the immutable peak object as its payload.
  (define waveform-model
    (make-preview-timeline 8 #:timeline timeline #:waveform peaks))
  (define waveform-entry
    (preview-timeline-entry-at waveform-model 'waveform 4))
  (check-equal? (timeline-entry-id waveform-entry) 'mixed-audio)
  (check-eq? (timeline-entry-payload waveform-entry) peaks)

  ;; Preview proxies are PCM WAV, not a renderer-specific waveform format.
  ;; Decode a tiny concrete WAV, then mix it through the real FFmpeg adapter.
  ;; The second preparation proves that proxy reuse requires its sidecar key;
  ;; the old existence-only cache behavior would have accepted any WAV here.
  (define wav (make-temporary-file "scene-ep-waveform-~a.wav"))
  (define peak-cache (make-temporary-file "scene-ep-waveform-~a.rktd"))
  (define proxy (make-temporary-file "scene-ep-audio-proxy-~a.wav"))
  (define proxy-waveform (make-temporary-file "scene-ep-audio-proxy-~a.rktd"))
  (define (write-u16 out value)
    (write-byte (bitwise-and value #xff) out)
    (write-byte (bitwise-and (arithmetic-shift value -8) #xff) out))
  (define (write-u32 out value)
    (write-u16 out (bitwise-and value #xffff))
    (write-u16 out (arithmetic-shift value -16)))
  (dynamic-wind
   void
   (lambda ()
     ;; RIFF header + PCM fmt chunk + one second of 48 kHz signed 16-bit mono
     ;; samples. The short nonzero prefix gives the waveform a visible peak;
     ;; using a normal sample rate also exercises FFmpeg's PCM proxy path.
     (call-with-output-file wav
       (lambda (out)
         (write-bytes #"RIFF" out) (write-u32 out 96036)
         (write-bytes #"WAVEfmt " out) (write-u32 out 16)
         (write-u16 out 1) (write-u16 out 1) (write-u32 out 48000)
         (write-u32 out 96000) (write-u16 out 2) (write-u16 out 16)
         (write-bytes #"data" out) (write-u32 out 96000)
         (for ([sample (in-list '(0 32767 32768 0))]) (write-u16 out sample))
         (for ([unused (in-range 47996)]) (write-u16 out 0)))
       #:exists 'truncate/replace)
     (define decoded (waveform-from-wav-file wav #:bucket-sizes '(2)))
     (check-equal? (waveform-sample-rate decoded) 48000)
     (check-equal? (waveform-channels decoded) 1)
     (check-= (vector-ref (waveform-level-maxima (car (waveform-levels decoded))) 0)
              (/ 32767.0 32768.0) 0.0001)
     (write-waveform-file decoded peak-cache)
     (check-equal? (read-waveform-file peak-cache) decoded)
     (define proxy-timeline
       (make-authored-timeline
        (scene-wait (make-scene) 1)
        #:audio-cues (list (audio-cue wav #:duration 1))))
     (define proxy-plan
       (make-preview-audio-plan proxy-timeline
                                #:proxy-path proxy
                                #:waveform-path proxy-waveform))
     (define first-proxy-report (prepare-preview-audio-proxy! proxy-plan))
     (check-false (audio-proxy-report-reused? first-proxy-report))
     (check-true (file-exists? proxy))
     (check-true (file-exists? proxy-waveform))
     (check-equal? (waveform-sample-rate (read-waveform-file proxy-waveform))
                   48000)
     (check-true (audio-proxy-report-reused?
                  (prepare-preview-audio-proxy! proxy-plan))))
   (lambda ()
     (for ([path (in-list
                  (list wav peak-cache proxy proxy-waveform
                        (string-append (path->string proxy)
                                       ".animate-audio-cache.rktd")))])
       (when (file-exists? path) (delete-file path)))))

  ;; The fake backend follows the caller-controlled monotonic clock exactly.
  (define milliseconds (box 0))
  (define backend
    (fake-audio-backend #:clock (lambda () (/ (unbox milliseconds) 1000.0))))
  (void (audio-backend-open backend audio-plan))
  (audio-backend-play backend 2 1)
  (set-box! milliseconds 2500)
  (check-= (audio-backend-position backend) 9/2 0.0001)
  (audio-backend-seek backend 1)
  (check-= (audio-backend-position backend) 1 0.0001)
  (audio-backend-close backend)
  (check-true (fake-audio-backend-closed? backend))

  ;; Mute is session-output policy rather than a second transport clock.  The
  ;; monitor pauses audio at the controller's semantic time, leaves the visual
  ;; `playing?` argument untouched, and restarts only the backend on unmute.
  (define monitor-milliseconds (box 0))
  (define monitor-backend
    (fake-audio-backend
     #:clock (lambda () (/ (unbox monitor-milliseconds) 1000.0))))
  (void (audio-backend-open monitor-backend audio-plan))
  (define monitor (preview-audio-monitor monitor-backend #f #f #f))
  (preview-audio-monitor-sync! monitor 2 #t 1)
  (check-true (preview-audio-monitor-playing? monitor))
  (check-true (fake-audio-backend-playing? monitor-backend))
  (set-box! monitor-milliseconds 1000)
  (preview-audio-monitor-set-muted! monitor #t 3 #t 1)
  (check-true (preview-audio-monitor-muted? monitor))
  (check-false (preview-audio-monitor-playing? monitor))
  (check-true (fake-audio-backend-muted? monitor-backend))
  (check-false (fake-audio-backend-playing? monitor-backend))
  (check-= (audio-backend-position monitor-backend) 3 0.0001)
  (preview-audio-monitor-set-muted! monitor #f 3 #t 1)
  (check-false (preview-audio-monitor-muted? monitor))
  (check-true (preview-audio-monitor-playing? monitor))
  (check-false (fake-audio-backend-muted? monitor-backend))
  (check-true (fake-audio-backend-playing? monitor-backend))
  (audio-backend-close monitor-backend)

  (define trace (make-preview-trace #:capacity 2))
  (preview-trace-record! trace 'sampling 4 #hasheq((frame . 12)))
  (preview-trace-record! trace 'rasterization 8)
  (preview-trace-record! trace 'cache-hit 1)
  (check-equal? (length (hash-ref (preview-trace->datum trace) 'events)) 2)
  (define output (make-temporary-file "scene-ep-trace-~a.rktd"))
  (dynamic-wind void
                (lambda ()
                  (preview-write-trace! trace output)
                  (check-true (file-exists? output)))
                (lambda () (when (file-exists? output) (delete-file output)))))
