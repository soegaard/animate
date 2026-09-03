#lang racket/base

;;;
;;; Authored MP4 Assembly
;;;

;; This module is the only layer that interprets authored audio placements as
;; FFmpeg input/filter arguments. Scene sampling remains independent of media
;; decoding; failure to open an audio/subtitle file is an assembly-time error.

(require racket/file
         racket/format
         racket/list
         racket/path
         racket/string
         racket/system
         "authoring-timeline.rkt"
         "scene.rkt"
         "shape-pict-renderers.rkt"
         "video-encoder.rkt")

(provide assemble-authored-mp4!
         mux-authored-video!
         concatenate-mp4!
         render-authored-mp4!)

;; assemble-authored-mp4! : authored-timeline? path-string? path-string?
;;                          [#:fps exact-positive-integer?]
;;                          [#:subtitle-file (or/c false/c path-string?)]
;;                          -> path-string?
;; Encodes numbered local PNG frames, mixes the timeline's audio cues, and
;; optionally muxes an SRT/WebVTT file as MP4 mov_text subtitles.
(define (assemble-authored-mp4! timeline frames-directory output-file
                                #:fps [fps 30]
                                #:subtitle-file [subtitle-file #f])
  (unless (authored-timeline? timeline)
    (raise-argument-error 'assemble-authored-mp4! "authored-timeline?" timeline))
  (unless (path-string? frames-directory)
    (raise-argument-error 'assemble-authored-mp4! "path-string?" frames-directory))
  (unless (path-string? output-file)
    (raise-argument-error 'assemble-authored-mp4! "path-string?" output-file))
  (unless (exact-positive-integer? fps)
    (raise-argument-error 'assemble-authored-mp4! "exact-positive-integer?" fps))
  (unless (or (not subtitle-file) (path-string? subtitle-file))
    (raise-argument-error
     'assemble-authored-mp4! "(or/c false/c path-string?)" subtitle-file))
  (define frame-pattern
    (build-path frames-directory "frame-%06d.png"))
  (unless (file-exists? (build-path frames-directory "frame-000000.png"))
    (raise-arguments-error
     'assemble-authored-mp4!
     "a locally numbered frame sequence beginning with frame-000000.png"
     "frames-directory" frames-directory))
  (when (and subtitle-file (not (file-exists? subtitle-file)))
    (raise-arguments-error
     'assemble-authored-mp4!
     "an existing subtitle file"
     "subtitle-file" subtitle-file))
  (define ffmpeg
    (find-executable-path "ffmpeg"))
  (unless ffmpeg
    (raise-arguments-error
     'assemble-authored-mp4!
     "FFmpeg was not found on PATH"
     "executable" "ffmpeg"))
  (define audio-cues
    (authored-timeline-audio-cues timeline))
  (for ([entry (in-list audio-cues)])
    (unless (file-exists? (audio-cue-source entry))
      (raise-arguments-error
       'assemble-authored-mp4!
       "an existing audio-cue source"
       "source" (audio-cue-source entry))))
  (define arguments
    (append
     (list "-y"
           "-framerate" (ffmpeg-number fps)
           "-i" (path-string->string* frame-pattern))
     (audio-input-arguments audio-cues)
     (if subtitle-file
         (list "-i" (path-string->string* subtitle-file))
         '())
     (output-arguments audio-cues subtitle-file)
     (list (path-string->string* output-file))))
  (unless (apply system* ffmpeg arguments)
    (raise-arguments-error
     'assemble-authored-mp4!
     "FFmpeg failed to assemble the authored movie"
     "frames-directory" frames-directory
     "output-file" output-file))
  output-file)

;; mux-authored-video! : authored-timeline? path-string? path-string? ...
;; Applies the same authored audio/subtitle assembly to an already encoded
;; visual MP4. This is the final step after concatenating cached partial movies.
(define (mux-authored-video! timeline input-video output-file
                             #:subtitle-file [subtitle-file #f])
  (unless (authored-timeline? timeline)
    (raise-argument-error 'mux-authored-video! "authored-timeline?" timeline))
  (unless (path-string? input-video)
    (raise-argument-error 'mux-authored-video! "path-string?" input-video))
  (unless (path-string? output-file)
    (raise-argument-error 'mux-authored-video! "path-string?" output-file))
  (unless (file-exists? input-video)
    (raise-arguments-error 'mux-authored-video! "an existing visual MP4"
                           "input-video" input-video))
  (unless (or (not subtitle-file) (path-string? subtitle-file))
    (raise-argument-error
     'mux-authored-video! "(or/c false/c path-string?)" subtitle-file))
  (when (and subtitle-file (not (file-exists? subtitle-file)))
    (raise-arguments-error 'mux-authored-video! "an existing subtitle file"
                           "subtitle-file" subtitle-file))
  (define ffmpeg (required-ffmpeg 'mux-authored-video!))
  (define audio-cues (authored-timeline-audio-cues timeline))
  (check-audio-cue-files 'mux-authored-video! audio-cues)
  (define arguments
    (append
     (list "-y" "-i" (path-string->string* input-video))
     (audio-input-arguments audio-cues)
     (if subtitle-file (list "-i" (path-string->string* subtitle-file)) '())
     (if (null? audio-cues)
         ;; Re-encoding is unnecessary when there is no audio filter graph.
         (append (list "-map" "0:v:0" "-c:v" "copy")
                 (if subtitle-file
                     (list "-map" "1:0" "-c:s" "mov_text")
                     '()))
         (append (list "-map" "0:v:0" "-c:v" "copy"
                       "-filter_complex" (audio-filter-graph audio-cues)
                       "-map" "[mixed]" "-c:a" "aac")
                 (if subtitle-file
                     (list "-map" (format "~a:0" (add1 (length audio-cues)))
                           "-c:s" "mov_text")
                     '())
                 (list "-shortest")))
     (list (path-string->string* output-file))))
  (unless (apply system* ffmpeg arguments)
    (raise-arguments-error
     'mux-authored-video! "FFmpeg failed to mux the authored movie"
     "input-video" input-video "output-file" output-file))
  output-file)

;; concatenate-mp4! : (non-empty-listof path-string?) path-string? -> path-string?
;; Concatenates compatible H.264 partial movies by FFmpeg stream copy. The
;; partials must use the same codecs and stream layout; encode-mp4! does so.
(define (concatenate-mp4! partial-movies output-file)
  (unless (and (list? partial-movies) (pair? partial-movies)
               (andmap path-string? partial-movies))
    (raise-argument-error
     'concatenate-mp4! "nonempty list of path-string?" partial-movies))
  (unless (path-string? output-file)
    (raise-argument-error 'concatenate-mp4! "path-string?" output-file))
  (for ([movie (in-list partial-movies)])
    (unless (file-exists? movie)
      (raise-arguments-error 'concatenate-mp4! "an existing partial MP4"
                             "partial-movie" movie)))
  (define ffmpeg (required-ffmpeg 'concatenate-mp4!))
  (define manifest
    (make-temporary-file "animate-concat-~a.txt" #f
                         (path-only (if (path? output-file)
                                        output-file
                                        (string->path output-file)))))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file
      manifest
      (lambda (output)
        (for ([movie (in-list partial-movies)])
          (fprintf output "file '~a'\n"
                   (concat-manifest-path (path-string->string* movie)))))
      #:exists 'truncate/replace)
     (unless (system* ffmpeg "-y" "-f" "concat" "-safe" "0"
                       "-i" (path->string manifest)
                       "-c" "copy" (path-string->string* output-file))
       (raise-arguments-error
        'concatenate-mp4! "FFmpeg failed to concatenate partial movies"
        "output-file" output-file)))
   (lambda ()
     (when (file-exists? manifest)
       (delete-file manifest))))
  output-file)

;; render-authored-mp4! : authored-timeline? path-string? path-string? ...
;; Renders a complete, contiguous section plan as individually cacheable PNG
;; sequences and visual-only MP4 partials. Only after the partials are joined
;; are authored audio and subtitles applied, so an unchanged audio track never
;; prevents visual section reuse.
(define (render-authored-mp4! timeline work-directory output-file
                              #:fps [fps 30]
                              #:camera [camera #f]
                              #:renderers [renderers default-pict-renderers]
                              #:workers [workers 1]
                              #:cache-key [cache-key 'auto]
                              #:asset-files [asset-files '()]
                              #:subtitle-file [subtitle-file 'auto]
                              #:subtitle-format [subtitle-format 'srt])
  (unless (authored-timeline? timeline)
    (raise-argument-error 'render-authored-mp4! "authored-timeline?" timeline))
  (unless (path-string? work-directory)
    (raise-argument-error 'render-authored-mp4! "path-string?" work-directory))
  (unless (path-string? output-file)
    (raise-argument-error 'render-authored-mp4! "path-string?" output-file))
  (unless (exact-positive-integer? fps)
    (raise-argument-error
     'render-authored-mp4! "exact-positive-integer?" fps))
  (unless (or (not subtitle-file)
              (eq? subtitle-file 'auto)
              (path-string? subtitle-file))
    (raise-argument-error
     'render-authored-mp4!
     "(or/c false/c 'auto path-string?)"
     subtitle-file))
  (unless (memq subtitle-format '(srt webvtt))
    (raise-argument-error 'render-authored-mp4! "'srt or 'webvtt" subtitle-format))
  (define entries
    (sort (authored-timeline-sections timeline) < #:key authoring-section-start))
  (check-complete-section-plan 'render-authored-mp4! timeline entries)
  (make-directory* work-directory)
  (define frames-root (build-path work-directory "frames"))
  (define partial-root (build-path work-directory "partials"))
  (make-directory* frames-root)
  (make-directory* partial-root)
  (define generated-subtitle-file
    (and (eq? subtitle-file 'auto)
         (pair? (authored-timeline-subtitles timeline))
         (build-path work-directory
                     (if (eq? subtitle-format 'srt)
                         "subtitles.srt"
                         "subtitles.vtt"))))
  (when generated-subtitle-file
    (write-subtitles! timeline generated-subtitle-file #:format subtitle-format))
  (define effective-subtitle-file
    (cond
      [generated-subtitle-file generated-subtitle-file]
      [(eq? subtitle-file 'auto) #f]
      [else subtitle-file]))
  (when (and effective-subtitle-file
             (not (file-exists? effective-subtitle-file)))
    (raise-arguments-error 'render-authored-mp4!
                           "an existing subtitle file"
                           "subtitle-file" effective-subtitle-file))
  (define partial-movies
    (for/list ([entry (in-list entries)] [index (in-naturals)])
      (define frames-directory
        (build-path frames-root (format "section-~a" (~r index #:min-width 4 #:pad-string "0"))))
      (define partial-movie
        (build-path partial-root (format "section-~a.mp4" (~r index #:min-width 4 #:pad-string "0"))))
      (define report
        (render-timeline-section/report!
         timeline entry frames-directory
         #:fps fps
         #:camera camera
         #:renderers renderers
         #:workers workers
         #:cache-key cache-key
         #:asset-files asset-files))
      (define effective-key
        (resolve-section-cache-key timeline entry cache-key fps camera renderers asset-files))
      (define partial-manifest
        (build-path partial-root
                    (format "section-~a.cache.rktd"
                            (~r index #:min-width 4 #:pad-string "0"))))
      (define expected-partial-cache
        (partial-cache-datum effective-key fps
                             (section-render-report-source-frame-indices report)))
      (unless (and effective-key
                   (file-exists? partial-movie)
                   (partial-cache-valid? partial-manifest expected-partial-cache))
        (encode-mp4! frames-directory partial-movie #:fps fps)
        (if effective-key
            (write-partial-cache! partial-manifest expected-partial-cache)
            (when (file-exists? partial-manifest)
              (delete-file partial-manifest))))
      partial-movie))
  (define visual-movie (build-path work-directory "visual.mp4"))
  (concatenate-mp4! partial-movies visual-movie)
  (mux-authored-video! timeline visual-movie output-file
                       #:subtitle-file effective-subtitle-file))

;; Complete coverage means concatenation preserves the original global output
;; grid exactly. A deliberately partial authoring plan can still use the lower
;; level section renderer and concatenate-mp4! directly.
(define (check-complete-section-plan who timeline entries)
  (unless (pair? entries)
    (raise-arguments-error who
                           "at least one named section covering the scene"
                           "sections" entries))
  (unless (= (authoring-section-start (car entries)) 0)
    (raise-arguments-error who
                           "the first section must start at zero"
                           "first-section" (authoring-section-name (car entries))))
  (unless (= (authoring-section-end (last entries))
             (scene-duration (authored-timeline-scene timeline)))
    (raise-arguments-error who
                           "the final section must end at scene duration"
                           "final-section" (authoring-section-name (last entries))
                           "scene-duration" (scene-duration (authored-timeline-scene timeline))))
  (for ([left (in-list entries)] [right (in-list (cdr entries))])
    (unless (= (authoring-section-end left)
               (authoring-section-start right))
      (raise-arguments-error who
                             "sections must be contiguous"
                             "left-section" (authoring-section-name left)
                             "right-section" (authoring-section-name right)))))

(define (resolve-section-cache-key timeline entry cache-key fps camera renderers asset-files)
  (if (eq? cache-key 'auto)
      (automatic-section-cache-key timeline entry
                                   #:fps fps
                                   #:camera camera
                                   #:renderers renderers
                                   #:asset-files asset-files)
      cache-key))

(define (partial-cache-datum key fps source-frame-indices)
  (list 'animate-partial-movie-cache-v1 key fps source-frame-indices))

(define (partial-cache-valid? cache-path expected)
  (and (file-exists? cache-path)
       (with-handlers ([exn:fail? (lambda (_exception) #f)])
         (equal? (call-with-input-file cache-path read) expected))))

(define (write-partial-cache! cache-path datum)
  (call-with-output-file
   cache-path
   (lambda (output)
     (write datum output)
     (newline output))
   #:exists 'truncate/replace)
  (void))

;; Every source trim is an FFmpeg input option so audio decoders need only read
;; the requested segment. Delaying happens in the filter graph after trimming.
(define (audio-input-arguments entries)
  (append*
   (for/list ([entry (in-list entries)])
     (append
      (list "-ss" (ffmpeg-number (audio-cue-source-start entry)))
      (if (audio-cue-duration entry)
          (list "-t" (ffmpeg-number (audio-cue-duration entry)))
          '())
      (list "-i" (path-string->string* (audio-cue-source entry)))))))

(define (output-arguments audio-cues subtitle-file)
  (define audio-count (length audio-cues))
  (define audio-options
    (if (zero? audio-count)
        '()
        (list "-filter_complex" (audio-filter-graph audio-cues)
              "-map" "[mixed]"
              "-c:a" "aac")))
  (define subtitle-options
    (if subtitle-file
        (list "-map" (format "~a:0" (add1 audio-count))
              "-c:s" "mov_text")
        '()))
  (append
   (list "-map" "0:v:0"
         "-c:v" "libx264"
         "-pix_fmt" "yuv420p"
         "-movflags" "+faststart")
   audio-options
   subtitle-options
   ;; Do not extend a completed visual movie with a frozen final image.
   (if (positive? audio-count) (list "-shortest") '())))

(define (audio-filter-graph entries)
  (define filters
    (for/list ([entry (in-list entries)] [index (in-naturals 1)])
      (format "[~a:a]~a[a~a]"
              index
              (audio-filter-chain entry)
              index)))
  (string-append
   (string-join filters ";")
   ";"
   (string-join
    (for/list ([index (in-range 1 (add1 (length entries)))])
      (format "[a~a]" index))
    "")
   (format "amix=inputs=~a:duration=longest[mixed]" (length entries))))

(define (audio-filter-chain entry)
  (define fade-in (audio-cue-fade-in entry))
  (define fade-out (audio-cue-fade-out entry))
  (define duration (audio-cue-duration entry))
  (string-join
   (append
    (list "asetpts=PTS-STARTPTS"
          (format "volume=~a" (ffmpeg-number (audio-cue-gain entry))))
    (if (positive? fade-in)
        (list (format "afade=t=in:st=0:d=~a" (ffmpeg-number fade-in)))
        '())
    (if (positive? fade-out)
        (list (format "afade=t=out:st=~a:d=~a"
                      (ffmpeg-number (- duration fade-out))
                      (ffmpeg-number fade-out)))
        '())
    (list (format "adelay=~a:all=1"
                  (inexact->exact (round (* 1000 (audio-cue-start entry)))))))
   ","))

(define (required-ffmpeg who)
  (define ffmpeg (find-executable-path "ffmpeg"))
  (unless ffmpeg
    (raise-arguments-error who "FFmpeg was not found on PATH"
                           "executable" "ffmpeg"))
  ffmpeg)

(define (check-audio-cue-files who audio-cues)
  (for ([entry (in-list audio-cues)])
    (unless (file-exists? (audio-cue-source entry))
      (raise-arguments-error who "an existing audio-cue source"
                             "source" (audio-cue-source entry)))))

(define (concat-manifest-path path)
  ;; FFmpeg concat files use single quotes; backslash and a literal quote are
  ;; the two characters requiring quoting in the manifest grammar.
  (regexp-replace* #px"'" (regexp-replace* #px"\\\\" path "\\\\\\\\") "'\\\\''"))

(define (path-string->string* value)
  (cond
    [(path? value) (path->string value)]
    [(string? value) value]
    [else (bytes->string/utf-8 value)]))

;; FFmpeg accepts decimal real literals, but Racket's exact rationals print as
;; 1/10. Convert every timeline number explicitly at the process boundary.
(define (ffmpeg-number value)
  (number->string (exact->inexact value)))
