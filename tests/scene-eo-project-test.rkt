#lang racket/base

;;;
;;; SCENE-EO Immutable Project Tests
;;;

(require rackunit
         racket/path
         racket/runtime-path
         "../main.rkt"
         "../authoring.rkt"
         "../project.rkt"
         "../version.rkt")

(define-runtime-path repository-root "..")
(define-runtime-path source-program-example
  "../examples/source-block-hot-reload.rkt")

(module+ test
  (define scene
    (scene-wait (make-scene) 2))
  ;; Project specifications snapshot option maps. Mutating a caller-owned
  ;; hash after construction cannot silently change a prepared render or its
  ;; persistent cache identity.
  (define mutable-encoder-options
    (make-hasheq (list (cons 'crf "18"))))
  (define preserved-encoder
    (encoder-spec #:options mutable-encoder-options))
  (hash-set! mutable-encoder-options 'crf "28")
  (check-equal? (hash-ref (encoder-spec-options preserved-encoder) 'crf) "18")
  (define direct-project
    (animate-project
     #:id 'direct
     #:source (scene-source scene)
     #:render (render-spec #:fps 2 #:width 320 #:height 180)
     #:output (output-spec #:root "media" #:name "direct")
     #:cache (cache-spec #:root ".cache")))
  (define plan
    (plan-project direct-project #:directory repository-root))
  (check-true (project-plan? plan))
  (check-equal?
   (project-path-plan-primary (project-plan-path-plan plan))
   (simplify-path (build-path repository-root "media" "direct.mp4")))
  (check-equal?
   (project-path-plan-frames-root (project-plan-path-plan plan))
   (simplify-path
    (build-path repository-root ".cache" "direct-all" "frames")))
  (check-equal?
   (project-path-plan-frame-sequence (project-plan-path-plan plan))
   (simplify-path
    (build-path repository-root "media" "direct-frames")))
  (check-equal?
   (project-path-plan-cache-domain-root (project-plan-path-plan plan) 'segments)
   (simplify-path
    (build-path repository-root ".cache" "direct-all" "segments")))
  (check-equal?
   (project-path-plan-cache-domain-root (project-plan-path-plan plan) 'source-program)
   (simplify-path
    (build-path repository-root ".cache" "direct-all" "source-program")))
  (define prepared
    (prepare-project! plan))
  (check-true (prepared-project? prepared))
  (check-equal? (prepared-project-target-frame-indices prepared) '(0 1 2 3))
  (check-eq? (cacheability-mode (prepared-project-cache-identities prepared))
             'memory-only)
  (check-true (project-check-report-ok? (check-project! plan)))
  (check-equal?
   (hash-ref (prepared-project-diagnostics prepared) 'release-version)
   animate-version)
  (check-equal?
   (prepared-project-target-frame-indices
    (prepare-project!
     (plan-project direct-project
                   #:directory repository-root
                   #:target (project-target-range 1/2 3/2))))
   '(1 2))
  (check-equal?
   (prepared-project-target-frame-indices
    (prepare-project!
     (plan-project direct-project
                   #:directory repository-root
                   #:target (project-target-frame 2))))
   '(2))

  (define timeline
    (make-authored-timeline
     scene #:sections (list (section 'first 0 1) (section 'second 1 2))))
  (define timeline-project
    (animate-project
     #:id 'timeline
     #:source (timeline-source timeline)
     #:render (render-spec #:fps 2)
     #:output (output-spec #:root "media" #:name "timeline")))
  (check-equal?
   (prepared-project-target-frame-indices
    (prepare-project!
     (plan-project timeline-project
                   #:directory repository-root
                   #:target (project-target-section 'second))))
   '(2 3))
  (check-equal?
   (project-path-plan-primary
    (project-plan-path-plan
     (plan-project timeline-project
                   #:directory repository-root
                   #:target (project-target-section 'second))))
   (simplify-path (build-path repository-root "media" "timeline-second.mp4")))
  ;; Target labels participate in output identity and are encoded rather than
  ;; treated as path fragments. This makes named sections safe on every output
  ;; platform and avoids a collision with an all-project render.
  (check-equal?
   (path->string
    (file-name-from-path
     (project-path-plan-primary
      (project-plan-path-plan
       (plan-project timeline-project
                     #:directory repository-root
                     #:target (project-target-section '|a/b|))))))
   "timeline-a_2f_b.mp4")
  (check-equal?
   (path->string
    (file-name-from-path
     (project-path-plan-primary
      (project-plan-path-plan
       (plan-project direct-project
                     #:directory repository-root
                     #:target (project-target-range 1/2 3/2))))))
   "direct-range-1_2f_2-3_2f_2.mp4")

  (define program-project
    (animate-project
     #:id 'program
     #:source (module-binding-source source-program-example 'hot-reload-demo)
     #:render (render-spec #:fps 2)
     #:output (output-spec #:root "media" #:name "program")))
  (define prepared-program
    (prepare-project!
     (plan-project program-project #:directory repository-root
                   #:target (project-target-block 'move-dot))))
  (check-equal? (prepared-project-target-frame-indices prepared-program) '(2 3 4 5))
  (check-eq? (cacheability-mode
              (prepared-project-cache-identities prepared-program))
             'persistent)

  (check-exn
   exn:fail?
   (lambda ()
     (normalize-project
      (animate-project
       #:id 'bad-png
       #:source (scene-source scene)
       #:output (output-spec #:format 'png-sequence)
       #:encoder (encoder-spec #:codec 'h264)))))
  (check-not-exn
   (lambda ()
     (normalize-project
      (animate-project
       #:id 'good-png
       #:source (scene-source scene)
       #:output (output-spec #:format 'png-sequence)
       #:encoder (encoder-spec #:codec 'none)))))
  (check-exn
   exn:fail?
   (lambda () (cache-spec #:domains '(frames not-a-cache-domain))))
  (check-exn
   exn:fail?
   (lambda () (cache-spec #:domains '(frames frames))))

  ;; Audio monitoring is optional. A visual project may ask for it without
  ;; making ffplay a prerequisite of planning or of the visual preview.
  (define audio-preview-project
    (animate-project
     #:id 'audio-preview
     #:source (timeline-source timeline)
     #:preview (preview-spec #:audio? #t)
     #:output (output-spec #:root "media" #:name "audio-preview"
                            #:format 'png-sequence)
     #:encoder (encoder-spec #:codec 'none)))
  (define audio-preview-report
    (check-project!
     (plan-project audio-preview-project #:directory repository-root)))
  (check-not-false (project-check-report-ok? audio-preview-report))
  (check-false (member 'ffplay (project-check-report-requirements audio-preview-report)))

  ;; A project check validates the exact FFmpeg profile before there is any
  ;; frame work to discard. Presence of the executable alone is not sufficient.
  (define unavailable-encoder-project
    (animate-project
     #:id 'unavailable-encoder
     #:source (scene-source scene)
     #:output (output-spec #:root "media" #:name "unavailable-encoder")
     #:encoder (encoder-spec #:codec 'definitely-not-an-encoder)))
  (define unavailable-encoder-report
    (check-project!
     (plan-project unavailable-encoder-project #:directory repository-root)))
  (check-false (project-check-report-ok? unavailable-encoder-report))
  (check-true
   (ormap (lambda (failure) (regexp-match? #rx"video encoder" failure))
          (project-check-report-failures unavailable-encoder-report)))

  (define unavailable-pixel-format-project
    (animate-project
     #:id 'unavailable-pixel-format
     #:source (scene-source scene)
     #:output (output-spec #:root "media" #:name "unavailable-pixel-format")
     #:encoder (encoder-spec #:pixel-format 'definitely-not-a-pixel-format)))
  (define unavailable-pixel-format-report
    (check-project!
     (plan-project unavailable-pixel-format-project #:directory repository-root)))
  (check-false (project-check-report-ok? unavailable-pixel-format-report))
  (check-true
   (ormap (lambda (failure) (regexp-match? #rx"pixel format" failure))
          (project-check-report-failures unavailable-pixel-format-report)))

  ;; A check remains non-writing, but catches roots that execution could never
  ;; use.  These two projects deliberately name an ordinary source file where
  ;; an output/cache directory is expected.
  (define impossible-output-project
    (animate-project
     #:id 'impossible-output
     #:source (scene-source scene)
     #:output (output-spec #:root source-program-example
                            #:name "impossible-output"
                            #:format 'png-sequence)
     #:encoder (encoder-spec #:codec 'none)
     #:cache (cache-spec #:root ".cache")))
  (define impossible-output-report
    (check-project!
     (plan-project impossible-output-project #:directory repository-root)))
  (check-false (project-check-report-ok? impossible-output-report))
  (check-true
   (ormap (lambda (failure) (regexp-match? #rx"output root" failure))
          (project-check-report-failures impossible-output-report)))

  (define impossible-cache-project
    (animate-project
     #:id 'impossible-cache
     #:source (scene-source scene)
     #:output (output-spec #:root "media"
                            #:name "impossible-cache"
                            #:format 'png-sequence)
     #:encoder (encoder-spec #:codec 'none)
     #:cache (cache-spec #:root source-program-example)))
  (define impossible-cache-report
    (check-project!
     (plan-project impossible-cache-project #:directory repository-root)))
  (check-false (project-check-report-ok? impossible-cache-report))
  (check-true
   (ormap (lambda (failure) (regexp-match? #rx"cache root" failure))
          (project-check-report-failures impossible-cache-report))))
