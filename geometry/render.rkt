#lang racket/base

;; Effectful output only. Native animate rendering/FFmpeg remain responsible
;; for pixels and encoding; this module adds narration and selected step stills.
(require racket/list racket/file racket/path racket/format
         (prefix-in output: "../render.rkt")
         "main.rkt" "private/frame-reuse.rkt" "private/subtitle-output.rkt")
(provide render-geometry-frames! render-geometry-frames/report! render-geometry-stills!
         render-geometry-frame-indices! geometry-frame-count encode-geometry-mp4!
         write-geometry-subtitles! geometry-caption-cues)

(struct frame-reuse-plan (requested-count unique-indices local->unique first-local-by-unique)
  #:transparent)

(define (subtitle-language-code? value)
  (or (not value)
      (and (string? value) (regexp-match? #px"^[A-Za-z]{3}$" value))))

(define (managed-frame-file-name? path)
  (regexp-match? #rx"^frame-[0-9]+\\.png$"
                 (path->string (file-name-from-path path))))

(define (delete-managed-frame-files! directory)
  (when (directory-exists? directory)
    (for ([entry (in-list (directory-list directory))])
      (define path (build-path directory entry))
      (when (and (file-exists? path) (managed-frame-file-name? entry))
        (delete-file path)))))

(define (output-frame-path directory local-index)
  (build-path directory
              (format "frame-~a.png"
                      (~r local-index #:min-width 6 #:pad-string "0"))))

(define (make-frame-reuse-plan timeline frame-indices fps captions?)
  (define unique-by-representative (make-hash))
  (define unique-indices-rev '())
  (define unique-count 0)
  (define requested-count (length frame-indices))
  (define local->unique (make-vector requested-count #f))
  (define first-local-by-unique '())
  (for ([mapping (in-list
                  (geometry-frame-reuse-representatives
                   timeline frame-indices fps captions?))]
        [local-index (in-naturals 0)])
    (define frame-index (car mapping))
    (define representative-frame-index (cadr mapping))
    (define existing
      (hash-ref unique-by-representative representative-frame-index #f))
    (cond [existing
           (vector-set! local->unique local-index existing)]
          [else
           (hash-set! unique-by-representative representative-frame-index unique-count)
           (vector-set! local->unique local-index unique-count)
           (set! unique-indices-rev (cons frame-index unique-indices-rev))
           (set! first-local-by-unique (cons local-index first-local-by-unique))
           (set! unique-count (add1 unique-count))]))
  (frame-reuse-plan requested-count (reverse unique-indices-rev) local->unique
                    (list->vector (reverse first-local-by-unique))))

(define (frame-reuse-plan-duplicate-count plan)
  (- (frame-reuse-plan-requested-count plan)
     (length (frame-reuse-plan-unique-indices plan))))

(define (copy-rendered-frames! rendered-paths destination local->unique)
  (define rendered-path-vector (list->vector rendered-paths))
  (for/list ([local-index (in-range (vector-length local->unique))])
    (define source-path
      (vector-ref rendered-path-vector (vector-ref local->unique local-index)))
    (define destination-path (output-frame-path destination local-index))
    (copy-file source-path destination-path #t)
    destination-path))

(define (expand-frame-milliseconds unique-frame-milliseconds local->unique first-local-by-unique)
  (define requested-count (vector-length local->unique))
  (define durations (make-vector requested-count 0))
  (for ([unique-index (in-range (vector-length first-local-by-unique))])
    (vector-set! durations
                 (vector-ref first-local-by-unique unique-index)
                 (list-ref unique-frame-milliseconds unique-index)))
  (vector->list durations))

(define (render-geometry-frame-indices/report! timeline indices directory #:width [width 1280] #:height [height 720]
                                               #:fps [fps 30] #:workers [workers 1]
                                               #:supersample [supersample 1]
                                               #:color-theme [color-theme #f] #:captions? [captions? #t]
                                               #:labels [labels (hash)])
  (unless (and (geometry-timeline? timeline) (list? indices) (andmap exact-nonnegative-integer? indices)
               (exact-positive-integer? fps) (exact-positive-integer? workers))
    (geometry-error 'render-geometry-frame-indices/report! "invalid timeline, indices, fps, or workers"))
  (define scene (geometry-timeline->scene timeline #:width width #:height height
                                         #:captions? captions? #:labels labels))
  (define plan (make-frame-reuse-plan timeline indices fps captions?))
  (define unique-indices (frame-reuse-plan-unique-indices plan))
  (cond
    [(= (length unique-indices) (length indices))
     (output:render-frame-indices/report! scene indices directory #:fps fps
                                          #:workers workers
                                          #:theme color-theme #:supersample supersample)]
    [else
     (define started-at (current-inexact-milliseconds))
     (make-directory* directory)
     (delete-managed-frame-files! directory)
     (define staging-directory (make-temporary-file "geometry-static-frames-~a" 'directory))
     (dynamic-wind
      void
      (lambda ()
        (define unique-report
          (output:render-frame-indices/report! scene unique-indices staging-directory #:fps fps
                                               #:workers workers
                                               #:theme color-theme #:supersample supersample))
        (define final-paths
          (copy-rendered-frames! (output:render-diagnostics-paths unique-report)
                                 directory
                                 (frame-reuse-plan-local->unique plan)))
        (output:render-diagnostics
         final-paths
         (length indices)
         (output:render-diagnostics-workers unique-report)
         (- (current-inexact-milliseconds) started-at)
         (expand-frame-milliseconds (output:render-diagnostics-frame-milliseconds unique-report)
                                    (frame-reuse-plan-local->unique plan)
                                    (frame-reuse-plan-first-local-by-unique plan))
         (output:render-diagnostics-cache-hits unique-report)
         (output:render-diagnostics-cache-misses unique-report)
         (output:render-diagnostics-cache-evictions unique-report)
         (output:render-diagnostics-release-version unique-report)
         (output:render-diagnostics-release-stage unique-report)))
      (lambda ()
        (when (directory-exists? staging-directory)
          (delete-directory/files staging-directory))))]))

(define (render-geometry-frame-indices! timeline indices directory #:width [width 1280] #:height [height 720]
                                       #:fps [fps 30] #:supersample [supersample 1]
                                       #:color-theme [color-theme #f] #:captions? [captions? #t]
                                       #:labels [labels (hash)])
  (output:render-diagnostics-paths
   (render-geometry-frame-indices/report! timeline indices directory
                                         #:width width #:height height
                                         #:fps fps #:workers 1
                                         #:supersample supersample
                                         #:color-theme color-theme #:captions? captions?
                                         #:labels labels)))

;; Encode the visual frame sequence, keep an SRT sidecar, and then use
;; Animate's authored-video muxer to add that SRT as an MP4 mov_text track.
;; The video stream is copied during muxing; subtitle embedding does not trigger
;; a second video encode. On a mux failure the already encoded visual MP4 stays
;; intact because mux-geometry-subtitles-into-mp4! publishes atomically.
(define (encode-geometry-mp4! timeline directory mp4
                              #:fps [fps 30] #:width [width 1280] #:height [height 720]
                              #:srt [srt #f] #:subtitle-language [subtitle-language "eng"])
  (unless (and (geometry-timeline? timeline) (path-string? directory) (path-string? mp4)
               (exact-positive-integer? fps) (exact-positive-integer? width)
               (exact-positive-integer? height) (or (not srt) (path-string? srt))
               (subtitle-language-code? subtitle-language))
    (geometry-error 'encode-geometry-mp4! "invalid timeline, paths, fps, width, height, SRT path, or subtitle language"))
  (define track-srt (geometry-mp4-subtitle-path mp4 srt))
  ;; Ensure the exact subtitle file that will be muxed was generated from this
  ;; timeline, even when this helper is called independently of frame rendering.
  (write-geometry-subtitles! timeline track-srt)
  (make-directory* (path-only (path->complete-path mp4)))
  (output:encode-mp4! directory mp4 #:fps fps #:width width #:height height)
  (mux-geometry-subtitles-into-mp4! timeline mp4 track-srt #:language subtitle-language)
  mp4)

(define (render-geometry-frames/report! timeline directory #:width [width 1280] #:height [height 720]
                                        #:fps [fps 30] #:workers [workers 1] #:supersample [supersample 1]
                                        #:color-theme [color-theme #f] #:captions? [captions? #t]
                                        #:labels [labels (hash)] #:mp4 [mp4 #f]
                                        #:srt [srt #f] #:vtt [vtt #f]
                                        #:subtitle-language [subtitle-language "eng"])
  (unless (subtitle-language-code? subtitle-language)
    (geometry-error 'render-geometry-frames/report!
                    "subtitle language must be #f or a three-letter ISO 639-2 code"))
  (define subtitle-plan
    (geometry-subtitle-output-plan #:directory directory #:mp4 mp4 #:srt srt #:vtt vtt))
  (define report
    (render-geometry-frame-indices/report!
     timeline
     (build-list (geometry-frame-count timeline fps) values)
     directory
     #:width width #:height height
     #:fps fps #:workers workers
     #:supersample supersample
     #:color-theme color-theme #:captions? captions? #:labels labels))
  (write-geometry-subtitle-outputs! timeline subtitle-plan)
  (when mp4
    (encode-geometry-mp4! timeline directory mp4 #:fps fps #:width width #:height height #:srt srt
                         #:subtitle-language subtitle-language))
  report)

(define (render-geometry-frames! timeline directory #:width [width 1280] #:height [height 720]
                                 #:fps [fps 30] #:workers [workers 1] #:supersample [supersample 1]
                                 #:color-theme [color-theme #f] #:captions? [captions? #t]
                                 #:labels [labels (hash)] #:mp4 [mp4 #f]
                                 #:srt [srt #f] #:vtt [vtt #f]
                                 #:subtitle-language [subtitle-language "eng"])
  (output:render-diagnostics-paths
   (render-geometry-frames/report! timeline directory #:width width #:height height
                                   #:fps fps #:workers workers #:supersample supersample
                                   #:color-theme color-theme #:captions? captions?
                                   #:labels labels #:mp4 mp4 #:srt srt #:vtt vtt
                                   #:subtitle-language subtitle-language)))
(define (render-geometry-stills! timeline directory #:width [width 1280] #:height [height 720]
                                #:fps [fps 30] #:color-theme [color-theme #f]
                                #:captions? [captions? #t] #:labels [labels (hash)]
                                #:supersample [supersample 1]
                                #:srt [srt #f] #:vtt [vtt #f])
  (define subtitle-plan
    (geometry-subtitle-output-plan #:directory directory #:srt srt #:vtt vtt))
  (unless (exact-positive-integer? fps) (geometry-error 'render-geometry-stills! "fps must be a positive integer"))
  (define (index-before time)
    (max 0 (sub1 (inexact->exact (floor (* fps time))))))
  (define indices
    (sort (remove-duplicates
           (append (list 0 (index-before (geometry-timeline-duration timeline)))
                   (map (lambda (c) (index-before (geometry-cue-end c))) (geometry-timeline-cues timeline)))) <))
  (define paths (render-geometry-frame-indices! timeline indices directory #:width width #:height height #:fps fps
                                                #:supersample supersample #:captions? captions?
                                                #:color-theme color-theme #:labels labels))
  (call-with-output-file (build-path directory "stills.tsv")
    (lambda (out)
      (fprintf out "image\ttime-seconds\tnarration\n")
      (for ([path (in-list paths)] [i (in-list indices)])
        (fprintf out "~a\t~a\t~a\n" path (exact->inexact (/ i fps))
                 (or (geometry-timeline-narration-at timeline (/ i fps)) ""))))
    #:exists 'truncate/replace)
  (write-geometry-subtitle-outputs! timeline subtitle-plan)
  paths)
