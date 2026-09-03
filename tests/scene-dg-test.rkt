#lang racket/base

;;;
;;; SCENE-DG Authored Audio, Subtitles, and Assembly Tests
;;;

(require rackunit
         racket/file
         racket/path
         racket/system
         "../main.rkt")

(module+ test
  (define scene (scene-wait (make-scene) 1))
  (define audio
    (audio-cue "narration.wav"
               #:start 1/4 #:source-start 1/10 #:duration 1/2
               #:gain 3/4 #:fade-in 1/10 #:fade-out 1/10))
  (check-equal? (audio-cue-gain audio) 3/4)
  (check-equal? (audio-cue-fade-in audio) 1/10)
  (check-equal? (audio-cue-fade-out audio) 1/10)
  (check-exn exn:fail:contract?
             (lambda () (audio-cue "audio.wav" #:fade-out 1/10)))

  (define timeline
    (make-authored-timeline
     scene
     #:audio-cues (list audio)
     #:subtitles (list (subtitle 0 1/2 "First line")
                       (subtitle 1/2 1 "Second\nline"))))
  (check-equal? (length (authored-timeline-subtitles timeline)) 2)
  (check-equal?
   (hash-ref (car (hash-ref (authored-timeline-metadata timeline) 'audio-cues))
             'gain)
   3/4)

  (define output-directory
    (make-temporary-file "animate-scene-dg-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define srt-file (build-path output-directory "captions.srt"))
     (define vtt-file (build-path output-directory "captions.vtt"))
     (write-subtitles! timeline srt-file)
     (write-subtitles! timeline vtt-file #:format 'webvtt)
     (check-equal?
      (file->string srt-file)
      "1\n00:00:00,000 --> 00:00:00,500\nFirst line\n\n2\n00:00:00,500 --> 00:00:01,000\nSecond\nline\n\n")
     (check-true (regexp-match? #px"^WEBVTT" (file->string vtt-file)))

     ;; DH's automatic key includes the serializable compiled scene, output
     ;; settings, and declared asset bytes. A static scene can reuse it across
     ;; selected renders without an author-written key.
     (define cache-timeline
       (make-authored-timeline scene #:sections (list (section 'all 0 1))))
     (define asset-file (build-path output-directory "asset.txt"))
     (call-with-output-file asset-file (lambda (out) (display "one" out)))
     (define key-one
       (automatic-section-cache-key
        cache-timeline (timeline-section cache-timeline 'all)
        #:fps 2 #:camera #f #:renderers default-pict-renderers
        #:asset-files (list asset-file)))
     (call-with-output-file asset-file (lambda (out) (display "two" out))
                            #:exists 'truncate/replace)
     (define key-two
       (automatic-section-cache-key
        cache-timeline (timeline-section cache-timeline 'all)
        #:fps 2 #:camera #f #:renderers default-pict-renderers
        #:asset-files (list asset-file)))
     (check-true (string? key-one))
     (check-not-equal? key-one key-two)
     ;; Standard named scene procedures such as `linear` are represented by
     ;; name and may participate in an automatic key. An opaque anonymous
     ;; resolver is deliberately a cache miss instead of a stale guess.
     (define anonymous-scene
       (scene-wait
        (scene-add
         (make-scene)
         (derived-visual
          (circle #:id 'anonymous-template)
          (lambda (_context template) template)))
        1))
     (define anonymous-timeline
       (make-authored-timeline
        anonymous-scene #:sections (list (section 'all 0 1))))
     (check-false
      (automatic-section-cache-key
       anonymous-timeline (timeline-section anonymous-timeline 'all)
       #:fps 2 #:camera #f #:renderers default-pict-renderers
       #:asset-files '()))
     (define cache-frames (build-path output-directory "cached-frames"))
     (define auto-first
       (render-timeline-section/report!
        cache-timeline 'all cache-frames #:fps 2 #:workers 1))
     (define auto-second
       (render-timeline-section/report!
        cache-timeline 'all cache-frames #:fps 2 #:workers 1))
     (check-false (section-render-report-cache-hit? auto-first))
     (check-true (section-render-report-cache-hit? auto-second))

     ;; FFmpeg is an optional external runtime dependency. When installed, a
     ;; genuine short sine-wave source verifies trimming, gain/fades/delay,
     ;; mixing, subtitle muxing, and MP4 output as one integration step.
     (define ffmpeg (find-executable-path "ffmpeg"))
     (when ffmpeg
       (define frames (build-path output-directory "frames"))
       (render-frames! scene frames #:fps 2)
       (define wav-file (build-path output-directory "narration.wav"))
       (check-true
        (system* ffmpeg "-y" "-f" "lavfi" "-i"
                 "sine=frequency=440:sample_rate=44100" "-t" "1"
                 (path->string wav-file)))
       (define real-timeline
         (make-authored-timeline
          scene
          #:sections (list (section 'first-half 0 1/2)
                           (section 'second-half 1/2 1))
          #:audio-cues
          (list (audio-cue wav-file #:duration 1 #:gain 1/2
                           #:fade-in 1/10 #:fade-out 1/10))
          #:subtitles (authored-timeline-subtitles timeline)))
       (define movie (build-path output-directory "assembled.mp4"))
       (assemble-authored-mp4! real-timeline frames movie #:fps 2
                               #:subtitle-file srt-file)
       (check-true (file-exists? movie))
       ;; Stream-copy concatenation is the partial-movie handoff used after
       ;; section frame caches have rendered only invalidated visual material.
       (define visual-partial (build-path output-directory "visual-partial.mp4"))
       (encode-mp4! frames visual-partial #:fps 2)
       (define concatenated (build-path output-directory "concatenated.mp4"))
       (concatenate-mp4! (list visual-partial visual-partial) concatenated)
       (check-true (file-exists? concatenated))

       ;; The high-level path keeps visual-only partials under its work
       ;; directory, reuses the section cache on a repeat invocation, and
       ;; applies the authored audio and generated captions only after joining.
       (define assembled-work (build-path output-directory "assembled-work"))
       (define assembled-by-sections
         (build-path output-directory "assembled-by-sections.mp4"))
       (render-authored-mp4! real-timeline assembled-work assembled-by-sections
                             #:fps 2 #:workers 1)
       (check-true (file-exists? assembled-by-sections))
       (check-true (file-exists? (build-path assembled-work "subtitles.srt")))
       (render-authored-mp4! real-timeline assembled-work assembled-by-sections
                             #:fps 2 #:workers 1)
       (check-true (file-exists? assembled-by-sections))))
   (lambda ()
     (delete-directory/files output-directory))))
