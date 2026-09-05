#lang racket/base

;;;
;;; SCENE-EO Project Execution Tests
;;;

(require rackunit
         racket/file
         racket/path
         racket/runtime-path
         "../main.rkt"
         "../authoring.rkt"
         "../project.rkt"
         "../render.rkt"
         (only-in "../private/project-execution.rkt"
                  current-project-artifact-opener)
         "../private/doctor.rkt")

(define-runtime-path cache-fixture "fixtures/preview-worker-scene.rkt")

(module+ test
  (define root
    (make-temporary-file "animate-project-execution-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define scene
       (scene-wait
        (scene-add
         (make-scene #:camera (make-camera #:width 80 #:height 50 #:world-width 8))
         (circle #:id 'dot #:radius 1 #:fill "tomato"))
        1))
     (define project
       (animate-project
        #:id 'still
        #:source (scene-source scene)
        #:render (render-spec #:fps 2 #:width 80 #:height 50)
        #:output (output-spec #:root (build-path root "media")
                              #:name "still"
                              #:format 'png-sequence)
        #:encoder (encoder-spec #:codec 'none)
        #:cache (cache-spec #:root (build-path root "cache"))))
     (define report
       (render-project-frame! project 1 #:directory root))
     (check-true (project-execution-report? report))
     (check-true (directory-exists?
                  (hash-ref (project-execution-report-artifact-paths report) 'primary)))
     (check-equal?
      (hash-ref (project-execution-report-artifact-paths report) 'frame-sequence)
      (hash-ref (project-execution-report-artifact-paths report) 'primary))
     (check-true
      (file-exists?
       (build-path
        (hash-ref (project-execution-report-artifact-paths report) 'primary)
        "frame-000000.png")))
     (check-equal? (project-execution-report-rendered-frames report) 1)
     (check-true (file-exists?
                  (car (hash-ref (project-execution-report-artifact-paths report) 'frames))))
     (check-equal?
      (project-target-value (project-plan-target (project-execution-report-plan report)))
      1)
     (check-true (file-exists?
                  (hash-ref (project-execution-report-artifact-paths report) 'manifest)))
     (check-true (pair? (project-execution-report-warnings report)))

     ;; `#:open-after?` is a best-effort presentation side effect, separate
     ;; from writing. Parameterize the private opener so this test neither
     ;; launches Finder nor depends on a GUI-capable test environment.
     (define opened-artifacts '())
     (define open-after-project
       (animate-project
        #:id 'open-after
        #:source (scene-source scene)
        #:render (render-spec #:fps 2 #:width 80 #:height 50)
        #:output (output-spec #:root (build-path root "media")
                              #:name "open-after"
                              #:format 'png-sequence
                              #:open-after? #t)
        #:encoder (encoder-spec #:codec 'none)
        #:cache (cache-spec #:root (build-path root "open-after-cache"))))
     (define open-after-report
       (parameterize
           ([current-project-artifact-opener
             (lambda (artifact)
               (set! opened-artifacts (cons artifact opened-artifacts))
               #t)])
         (render-project! open-after-project #:directory root)))
     (check-equal?
      opened-artifacts
      (list (hash-ref (project-execution-report-artifact-paths open-after-report)
                      'primary)))
     (define failed-open-report
       (parameterize ([current-project-artifact-opener (lambda (_artifact) #f)])
         (render-project!
          (animate-project
           #:id 'open-after-failure
           #:source (scene-source scene)
           #:render (render-spec #:fps 2 #:width 80 #:height 50)
           #:output (output-spec #:root (build-path root "media")
                                 #:name "open-after-failure"
                                 #:format 'png-sequence
                                 #:open-after? #t)
           #:encoder (encoder-spec #:codec 'none)
           #:cache (cache-spec #:root (build-path root "open-after-failure-cache")))
          #:directory root)))
     (check-true
      (ormap (lambda (warning) (regexp-match? #rx"could not open" warning))
             (project-execution-report-warnings failed-open-report)))

     ;; An all-target authored project can intentionally materialize each
     ;; named section. Every child is prepared as a normal section target, so
     ;; it gets a collision-free output path and its own one-frame sequence.
     (define section-timeline
       (make-authored-timeline
        scene
        #:sections (list (section 'first 0 1/2)
                         (section 'second 1/2 1))))
     (define sections-project
       (animate-project
        #:id 'sections
        #:source (timeline-source section-timeline)
        #:render (render-spec #:fps 2 #:width 80 #:height 50)
        #:output (output-spec #:root (build-path root "media")
                              #:name "sections"
                              #:format 'png-sequence
                              #:write-sections? #t
                              #:overwrite-policy 'replace)
        #:encoder (encoder-spec #:codec 'none)
        ;; The tiny budget forces section-target cleanup while exports are
        ;; still in progress. The parent all-target cache must remain alive so
        ;; the report it returns does not contain dead frame paths.
        #:cache (cache-spec #:root (build-path root "sections-cache")
                            #:max-bytes 1)))
     (define sections-report
       (render-project! sections-project #:directory root))
     (define section-outputs
       (hash-ref (project-execution-report-artifact-paths sections-report)
                 'sections))
     (check-true
      (directory-exists?
       (path-only
        (car (hash-ref (project-execution-report-artifact-paths sections-report)
                       'frames)))))
     (check-equal? (map (lambda (entry) (hash-ref entry 'name)) section-outputs)
                   '(first second))
     (for ([entry (in-list section-outputs)])
       (define section-primary
         (hash-ref (hash-ref entry 'artifact-paths) 'primary))
       (check-true (directory-exists? section-primary))
       (check-true
        (file-exists? (build-path section-primary "frame-000000.png"))))
     (check-exn
      exn:fail?
      (lambda ()
        (render-project!
         (animate-project
          #:id 'sections-require-timeline
          #:source (scene-source scene)
          #:render (render-spec #:fps 2 #:width 80 #:height 50)
          #:output (output-spec #:root (build-path root "media")
                                #:name "sections-require-timeline"
                                #:format 'png-sequence
                                #:write-sections? #t)
          #:encoder (encoder-spec #:codec 'none)
          #:cache (cache-spec #:root (build-path root "sections-require-timeline-cache")))
         #:directory root)))

     ;; Frame reuse belongs to the raster domain, not the project/output or
     ;; encoder domain. A repeated module-backed render at identical dimensions
     ;; reuses its PNG frames; changing only width must regenerate them even
     ;; though the source, target, cache directory, and output name are the
     ;; same. (The PNG target deliberately has no video encoder.)
     (define cache-root (build-path root "persistent-cache"))
     (define (cache-project width)
       (animate-project
        #:id 'cache-identity
        #:source (module-binding-source cache-fixture 'worker-scene)
        #:render (render-spec #:fps 2 #:width width #:height 50)
        #:output (output-spec #:root (build-path root "media")
                              #:name "cache-identity"
                              #:format 'png-sequence
                              #:overwrite-policy 'replace)
        #:encoder (encoder-spec #:codec 'none)
        #:cache (cache-spec #:root cache-root #:policy 'read-write)))
     (define first-cache-report
       (render-project! (cache-project 80) #:directory root))
     (check-true (positive? (project-execution-report-rendered-frames first-cache-report)))
     (define reused-cache-report
       (render-project! (cache-project 80) #:directory root))
     (check-true (positive? (project-execution-report-reused-frames reused-cache-report)))
     (define resized-cache-report
       (render-project! (cache-project 120) #:directory root))
     (check-true (positive? (project-execution-report-rendered-frames resized-cache-report)))
     (check-equal? (project-execution-report-reused-frames resized-cache-report) 0)

     ;; Narration is an audio-domain input. Replacing it at the same path must
     ;; preserve valid visual PNGs; audio assembly/proxy work happens later.
     (define audio-asset-path (build-path root "narration.wav"))
     (call-with-output-file audio-asset-path
       (lambda (out) (write-bytes #"first narration" out))
       #:exists 'truncate/replace)
     (define (audio-asset-project)
       (animate-project
        #:id 'audio-asset-identity
        #:source (module-binding-source cache-fixture 'worker-scene)
        #:render (render-spec #:fps 2 #:width 80 #:height 50)
        #:output (output-spec #:root (build-path root "media")
                              #:name "audio-asset-identity"
                              #:format 'png-sequence
                              #:overwrite-policy 'replace)
        #:encoder (encoder-spec #:codec 'none)
        #:assets (list (project-asset audio-asset-path #:role 'audio))
        #:cache (cache-spec #:root (build-path root "audio-asset-cache")
                            #:policy 'read-write)))
     (define first-audio-asset-report
       (render-project! (audio-asset-project) #:directory root))
     (check-true (positive? (project-execution-report-rendered-frames
                             first-audio-asset-report)))
     (call-with-output-file audio-asset-path
       (lambda (out) (write-bytes #"replaced narration" out))
       #:exists 'truncate/replace)
     (define changed-audio-asset-report
       (render-project! (audio-asset-project) #:directory root))
     (check-true (positive? (project-execution-report-reused-frames
                             changed-audio-asset-report)))

     ;; An encoded visual segment has a deliberately different cache identity
     ;; from its PNG frames. Repeating a project with identical H.264 options
     ;; reuses the segment; changing only CRF reuses the frame sequence but
     ;; encodes a fresh segment. Audio is not involved in this fixture, so the
     ;; test isolates video-encoder identity from raster identity.
     (define segment-cache-root (build-path root "segment-cache"))
     (define (segment-project crf)
       (animate-project
        #:id 'segment-identity
        #:source (module-binding-source cache-fixture 'worker-scene)
        #:render (render-spec #:fps 2 #:width 80 #:height 50)
        #:output (output-spec #:root (build-path root "media")
                              #:name "segment-identity"
                              #:format 'mp4
                              #:write-frame-sequence? #t
                              #:overwrite-policy 'replace)
        #:encoder (encoder-spec #:options (hasheq 'crf crf))
        #:cache (cache-spec #:root segment-cache-root #:policy 'read-write)))
     ;; Project preparation is the one effectful phase that records a selected
     ;; encoder's identity.  It does not conflate this with `doctor`, which
     ;; deliberately only discovers capabilities without launching a tool.
     (define prepared-segment-project
       (prepare-project!
        (plan-project (segment-project "28") #:directory root)))
     (define ffmpeg-identity
       (project-tool-identities-ffmpeg
        (prepared-project-tool-identities prepared-segment-project)))
     (check-true (tool-identity? ffmpeg-identity))
     (check-eq? (tool-identity-name ffmpeg-identity) 'ffmpeg)
     (check-true (string? (tool-identity-executable ffmpeg-identity)))
     (check-true (string? (tool-identity-version ffmpeg-identity)))
     (check-true (regexp-match? #rx"^ffmpeg version "
                                (tool-identity-version ffmpeg-identity)))
     (define first-segment-report
       (render-project! (segment-project "28") #:directory root))
     (check-equal? (project-execution-report-encoded-segments first-segment-report) 1)
     (check-equal? (project-execution-report-reused-segments first-segment-report) 0)
     (define exported-mp4-frames
       (hash-ref (project-execution-report-artifact-paths first-segment-report)
                 'frame-sequence))
     (check-true (directory-exists? exported-mp4-frames))
     (check-true
      (file-exists? (build-path exported-mp4-frames "frame-000000.png")))
     (define reused-segment-report
       (render-project! (segment-project "28") #:directory root))
     (check-equal? (project-execution-report-encoded-segments reused-segment-report) 0)
     (check-equal? (project-execution-report-reused-segments reused-segment-report) 1)
     (check-true (positive? (project-execution-report-reused-frames reused-segment-report)))
     (define changed-encoder-report
       (render-project! (segment-project "18") #:directory root))
     (check-equal? (project-execution-report-encoded-segments changed-encoder-report) 1)
     (check-equal? (project-execution-report-reused-segments changed-encoder-report) 0)
     (check-true (positive? (project-execution-report-reused-frames changed-encoder-report)))

     ;; Capacity applies across completed target directories. The second active
     ;; target remains inspectable, while an older independent target is
     ;; evicted and recorded in the immutable execution report.
     (define budget-cache-root (build-path root "budget-cache"))
     (define (budget-project id)
       (animate-project
        #:id id
        #:source (module-binding-source cache-fixture 'worker-scene)
        #:render (render-spec #:fps 2 #:width 80 #:height 50)
        #:output (output-spec #:root (build-path root "media")
                              #:name (symbol->string id)
                              #:format 'png-sequence)
        #:encoder (encoder-spec #:codec 'none)
        #:cache (cache-spec #:root budget-cache-root
                            #:max-bytes 1
                            #:domains '(frames))))
     (define first-budget-report
       (render-project! (budget-project 'budget-first) #:directory root))
     (define first-budget-root
       (path-only
        (car (hash-ref (project-execution-report-artifact-paths
                        first-budget-report)
                       'frames))))
     (check-true (directory-exists? first-budget-root))
     (define second-budget-report
       (render-project! (budget-project 'budget-second) #:directory root))
     (check-false (directory-exists? first-budget-root))
     (define budget-event
       (for/first ([event (in-list (project-execution-report-cache-events
                                    second-budget-report))]
                   #:when (eq? (hash-ref event 'domain) 'cache))
         event))
     (check-eq? (hash-ref budget-event 'event) 'evicted)
     (check-equal? (length (hash-ref budget-event 'evicted)) 1))
   (lambda ()
     (delete-directory/files root))))
