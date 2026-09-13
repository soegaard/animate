#lang racket/base

;; Genuine native integration tests: use Animate's actual subtitle constructor,
;; authored timeline, scene sampler and serializer. No FFmpeg is required.
(require rackunit racket/file racket/list racket/string racket/runtime-path racket/system
         (prefix-in a: "../../main.rkt")
         (prefix-in author: "../../authoring.rkt")
         (prefix-in output: "../../render.rkt")
         "../main.rkt" "../render.rkt" "../private/subtitle-output.rkt")

(construction subtitle-native-demo
  (given [A (point -1 0)] [B (point 1 0)])
  (timing [opening-pause 0] [read-delay 1/2] [action-duration 1/2] [step-pause 1/2])
  (step "Join A to B." [AB (segment A B)])
  (step "The length is AB."))
(define (temporary-test f)
  (define root (make-temporary-file "geometry-subtitles-test-~a" 'directory))
  (dynamic-wind void (lambda () (f root)) (lambda () (delete-directory/files root))))
(define (snapshot-cues t cues duration)
  (struct-copy geometry-timeline t [cues cues] [duration duration]))
(define (has-caption? scene time)
  (define root (a:scene-visual-at scene '$geometry/subtitle-native-demo time))
  (for/or ([v (in-list (a:group-visual-children root))])
    (regexp-match? #rx"/caption$" (symbol->string (a:visual-id v)))))

(define-runtime-path cli-fixture "subtitle-cli-fixture.rkt")
(define executable (or (find-executable-path (find-system-path 'exec-file)) (find-system-path 'exec-file)))
(define (run-cli root . args)
  (parameterize ([current-directory root]
                 [current-output-port (open-output-string)]
                 [current-error-port (open-output-string)])
    (apply system*/exit-code executable cli-fixture args)))

(define (command-output executable . args)
  (define output (open-output-string))
  (define errors (open-output-string))
  (define ok?
    (parameterize ([current-output-port output] [current-error-port errors])
      (apply system* executable args)))
  (values ok? (get-output-string output) (get-output-string errors)))

(module+ test
  (test-case "bridge produces actual Animate subtitle values with exact geometry timing"
    (define t (construction->timeline subtitle-native-demo))
    (define entries (geometry-timeline->subtitles t))
    (check-true (andmap author:subtitle? entries))
    (check-equal? (map author:subtitle-cue-text entries) '("Join A to B." "The length is AB."))
    (check-equal? (map author:subtitle-start entries) '(0 3/2))
    (check-equal? (map author:subtitle-end entries) '(3/2 5/2)))
  (test-case "authored timelines retain visible captions by default, and export independently when disabled"
    (define t (construction->timeline subtitle-native-demo))
    (define shown (geometry-timeline->authored-timeline t #:width 320 #:height 180))
    (define hidden (geometry-timeline->authored-timeline t #:width 320 #:height 180 #:captions? #f))
    (check-true (author:authored-timeline? shown))
    (check-= (a:scene-duration (author:authored-timeline-scene shown)) (geometry-timeline-duration t) 1e-8)
    (check-true (has-caption? (author:authored-timeline-scene shown) 1/4))
    (check-false (has-caption? (author:authored-timeline-scene hidden) 1/4))
    (check-equal? (author:authored-timeline-subtitles shown) (author:authored-timeline-subtitles hidden)))
  (test-case "geometry writer delegates both formats byte-for-byte to Animate"
    (temporary-test
     (lambda (root)
       (define t (construction->timeline subtitle-native-demo))
       (define authored (geometry-timeline->authored-timeline t #:width 320 #:height 180))
       (for ([fmt '(srt webvtt)])
         (define expected (build-path root (format "native-~a.txt" fmt)))
         (define actual (build-path root "sub folder" (format "geometry-~a.txt" fmt)))
         (output:write-subtitles! authored expected #:format fmt)
         (check-equal? (write-geometry-subtitles! t actual #:format fmt) actual)
         (check-equal? (file->bytes actual) (file->bytes expected)))
       (check-equal? (file->string (build-path root "sub folder/geometry-srt.txt"))
                     "1\n00:00:00,000 --> 00:00:01,500\nJoin A to B.\n\n2\n00:00:01,500 --> 00:00:02,500\nThe length is AB.\n\n")
       (check-true (string-prefix? (file->string (build-path root "sub folder/geometry-webvtt.txt")) "WEBVTT\n\n")))))
  (test-case "Unicode and line breaks are serialized by the native writer, without invalid empty entries"
    (temporary-test
     (lambda (root)
       (define t (snapshot-cues (construction->timeline subtitle-native-demo)
                  (list (geometry-cue 0 1 "Æ Ø Å — A′, α, P₁\r\nSecond line")
                        (geometry-cue 1 2 "  ") (geometry-cue 2 2 "Instant")
                        (geometry-cue 2 3 "Last")) 3))
       (define entries (geometry-timeline->subtitles t))
       (check-equal? (length entries) 2)
       (check-equal? (map author:subtitle-start entries) '(0 2))
       (define path (build-path root "unicode.srt"))
       (write-geometry-subtitles! t path)
       (check-true (string-contains? (file->string path) "Æ Ø Å — A′, α, P₁\nSecond line"))
       (check-false (string-contains? (file->string path) "\r"))
       (check-equal? (bytes->string/utf-8 (file->bytes path)) (file->string path)))))
  (test-case "empty cue lists, nested output directories and atomic replacement work"
    (temporary-test
     (lambda (root)
       (define t (snapshot-cues (construction->timeline subtitle-native-demo) '() 1))
       (define file (build-path root "new/subtitles.srt"))
       (write-geometry-subtitles! t file)
       (check-equal? (file->bytes file) #"")
       (write-geometry-subtitles! (construction->timeline subtitle-native-demo) file)
       (define bytes (file->bytes file))
       (check-exn exn:fail? (lambda () (write-geometry-subtitles! t file #:format 'unsupported)))
       (check-equal? (file->bytes file) bytes)
       (check-equal? (map path->string (directory-list (build-path root "new"))) '("subtitles.srt")))))
  (test-case "sparse rendering still writes narration.srt, with independent explicit SRT and VTT"
    (temporary-test
     (lambda (root)
       (define t (construction->timeline subtitle-native-demo))
       (define frames (build-path root "frames"))
       (define srt (build-path root "captions/lesson.srt"))
       (define vtt (build-path root "captions/lesson.vtt"))
       (define paths (render-geometry-stills! t frames #:width 320 #:height 180 #:fps 2
                                             #:captions? #f #:srt srt #:vtt vtt))
       (check-true (pair? paths))
       (check-equal? (file->bytes srt) (file->bytes (build-path frames "narration.srt")))
       (check-true (string-prefix? (file->string vtt) "WEBVTT\n\n")))))
  (test-case "sidecar planning and writing stays available independently of MP4 muxing"
    (temporary-test
     (lambda (root)
       (define t (construction->timeline subtitle-native-demo))
       (define mp4 (build-path root "movies/demo.mp4"))
       (define paths (write-geometry-subtitle-outputs! t (geometry-subtitle-output-plan #:mp4 mp4)))
       (check-equal? paths (list (build-path root "movies/demo.srt")))
       (check-false (file-exists? mp4))
       (check-true (file-exists? (car paths)))))))

(module+ test
  (test-case "MP4 muxing adds a selectable mov_text subtitle track and keeps the SRT sidecar"
    (define ffmpeg (find-executable-path "ffmpeg"))
    (define ffprobe (find-executable-path "ffprobe"))
    (when (and ffmpeg ffprobe)
      (temporary-test
       (lambda (root)
         (define t (construction->timeline subtitle-native-demo))
         (define mp4 (build-path root "demo.mp4"))
         (define srt (build-path root "demo.srt"))
         (check-true
          (system* ffmpeg "-loglevel" "error" "-y"
                   "-f" "lavfi" "-i" "color=c=black:s=160x90:r=1:d=3"
                   "-c:v" "libx264" "-pix_fmt" "yuv420p" mp4))
         (write-geometry-subtitles! t srt)
         (define original-srt (file->bytes srt))
         (check-equal? (mux-geometry-subtitles-into-mp4! t mp4 srt) mp4)
         (check-equal? (file->bytes srt) original-srt)
         (define-values (ok? stdout stderr)
           (command-output ffprobe "-v" "error" "-select_streams" "s:0"
                           "-show_entries" "stream=codec_name"
                           "-of" "default=noprint_wrappers=1:nokey=1" mp4))
         (check-true ok? stderr)
         (check-equal? (string-trim stdout) "mov_text")
         (define-values (lang-ok? lang-out lang-err)
           (command-output ffprobe "-v" "error" "-select_streams" "s:0"
                           "-show_entries" "stream_tags=language"
                           "-of" "default=noprint_wrappers=1:nokey=1" mp4))
         (check-true lang-ok? lang-err)
         (check-equal? (string-trim lang-out) "eng")
         ;; The language is configurable without changing the SRT bytes.
         (check-equal? (mux-geometry-subtitles-into-mp4! t mp4 srt #:language "DAN") mp4)
         (define-values (dan-ok? dan-out dan-err)
           (command-output ffprobe "-v" "error" "-select_streams" "s:0"
                           "-show_entries" "stream_tags=language"
                           "-of" "default=noprint_wrappers=1:nokey=1" mp4))
         (check-true dan-ok? dan-err)
         (check-equal? (string-trim dan-out) "dan")
         (check-equal? (file->bytes srt) original-srt))))))

(module+ test
  (test-case "native example CLI exports SRT/VTT without images and leaves captions independent"
    (temporary-test
     (lambda (root)
       (check-equal? (run-cli root "--dark" "--subtitles-only"
                              "--srt" "captions/one.srt" "--vtt" "captions/one.vtt") 0)
       (check-equal? (run-cli root "--dark" "--no-captions" "--subtitles-only"
                              "--srt" "captions/two.srt") 0)
       (check-equal? (file->bytes (build-path root "captions/one.srt"))
                     (file->bytes (build-path root "captions/two.srt")))
       (check-true (file-exists? (build-path root "captions/one.vtt")))
       (check-false (directory-exists? (build-path root "geometry-output")))
       (check-not-equal? (run-cli root "--subtitles-only") 0))))
  (test-case "native one- and two-worker exports use the identical full timeline"
    (temporary-test
     (lambda (root)
       (for ([workers '("1" "2")])
         (define frames (string-append "frames-" workers))
         (define srt (string-append "subtitles/case-" workers ".srt"))
         (define vtt (string-append "subtitles/case-" workers ".vtt"))
         (check-equal? (run-cli root "--dark" "--frames" "--workers" workers
                                "--width" "160" "--height" "90" "--fps" "2"
                                "--srt" srt "--vtt" vtt frames) 0)
         (check-equal? (file->bytes (build-path root srt))
                       (file->bytes (build-path root frames "narration.srt"))))
       (check-equal? (file->bytes (build-path root "subtitles/case-1.srt"))
                     (file->bytes (build-path root "subtitles/case-2.srt")))
       (check-equal? (file->bytes (build-path root "subtitles/case-1.vtt"))
                     (file->bytes (build-path root "subtitles/case-2.vtt")))))))
(module+ test
  (test-case "native MP4 CLI embeds mov_text in both one-process and process-sharded rendering"
    (define ffprobe (find-executable-path "ffprobe"))
    (when ffprobe
      (temporary-test
       (lambda (root)
         (for ([workers '("1" "2")])
           (define frames (string-append "movie-frames-" workers))
           (define mp4 (string-append "movies/case-" workers ".mp4"))
           (check-equal? (run-cli root "--dark" "--workers" workers
                                  "--width" "160" "--height" "90" "--fps" "5"
                                  "--mp4" mp4 frames) 0)
           (define sidecar (path-replace-extension (build-path root mp4) #".srt"))
           (check-true (file-exists? sidecar))
           (define-values (ok? stdout stderr)
             (command-output ffprobe "-v" "error" "-select_streams" "s:0"
                             "-show_entries" "stream=codec_name"
                             "-of" "default=noprint_wrappers=1:nokey=1"
                             (build-path root mp4)))
           (check-true ok? stderr)
           (check-equal? (string-trim stdout) "mov_text")
           (define-values (lang-ok? lang-out lang-err)
             (command-output ffprobe "-v" "error" "-select_streams" "s:0"
                             "-show_entries" "stream_tags=language"
                             "-of" "default=noprint_wrappers=1:nokey=1"
                             (build-path root mp4)))
           (check-true lang-ok? lang-err)
           (check-equal? (string-trim lang-out) "eng")))))))
