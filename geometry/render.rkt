#lang racket/base

;; Effectful output only. Native animate rendering/FFmpeg remain responsible
;; for pixels and encoding; this module adds narration and selected step stills.
(require racket/list racket/file racket/path racket/format
         (prefix-in output: "../render.rkt")
         "main.rkt")
(provide render-geometry-frames! render-geometry-frames/report! render-geometry-stills!
         render-geometry-frame-indices! geometry-frame-count
         write-geometry-subtitles! geometry-caption-cues)

(struct frame-reuse-plan (requested-count unique-indices local->unique first-local-by-unique)
  #:transparent)

;; Flatten expanded-helper narration into nonoverlapping caption spans.
(define (geometry-caption-cues timeline)
  (define boundaries
    (sort (remove-duplicates
           (append-map (lambda (c) (list (geometry-cue-start c) (geometry-cue-end c)))
                       (geometry-timeline-cues timeline))) <))
  (define reversed '())
  (for ([from (in-list boundaries)] [to (in-list (if (null? boundaries) '() (cdr boundaries)))])
    (define text (geometry-timeline-narration-at timeline (/ (+ from to) 2)))
    (when text
      (if (and (pair? reversed) (equal? text (geometry-cue-text (car reversed)))
               (= from (geometry-cue-end (car reversed))))
          (set! reversed (cons (geometry-cue (geometry-cue-start (car reversed)) to text) (cdr reversed)))
          (set! reversed (cons (geometry-cue from to text) reversed)))))
  (reverse reversed))
(define (timestamp seconds)
  (define millis (inexact->exact (round (* 1000 seconds))))
  (define (pad n count) (~r n #:min-width count #:pad-string "0"))
  (format "~a:~a:~a,~a" (pad (quotient millis 3600000) 2)
          (pad (modulo (quotient millis 60000) 60) 2)
          (pad (modulo (quotient millis 1000) 60) 2) (pad (modulo millis 1000) 3)))
(define (geometry-frame-count timeline fps)
  (unless (and (geometry-timeline? timeline) (exact-positive-integer? fps))
    (geometry-error 'geometry-frame-count "expected a geometry timeline and positive fps"))
  (max 1 (inexact->exact (ceiling (* fps (geometry-timeline-duration timeline))))))

(define (frame-index->time-seconds index fps)
  (exact->inexact (/ index fps)))

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

(define (frame-visual-key frame captions?)
  (list (geometry-frame-appearances frame)
        (and captions? (geometry-frame-narration frame))))

(define (make-frame-reuse-plan timeline frame-indices fps captions?)
  (define seen (make-hash))
  (define unique-indices-rev '())
  (define unique-count 0)
  (define requested-count (length frame-indices))
  (define local->unique (make-vector requested-count #f))
  (define first-local-by-unique '())
  (for ([frame-index (in-list frame-indices)] [local-index (in-naturals 0)])
    (define frame (sample-geometry-timeline timeline (frame-index->time-seconds frame-index fps)))
    (define key (frame-visual-key frame captions?))
    (define existing (hash-ref seen key #f))
    (cond [existing
           (vector-set! local->unique local-index existing)]
          [else
           (hash-set! seen key unique-count)
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

(define (write-geometry-subtitles! timeline path)
  (call-with-output-file path
    (lambda (out)
      (for ([cue (in-list (geometry-caption-cues timeline))] [index (in-naturals 1)])
        (fprintf out "~a\n~a --> ~a\n~a\n\n" index (timestamp (geometry-cue-start cue))
                 (timestamp (geometry-cue-end cue)) (geometry-cue-text cue))))
    #:exists 'truncate/replace)
  path)
(define (render-geometry-frames/report! timeline directory #:width [width 1280] #:height [height 720]
                                        #:fps [fps 30] #:workers [workers 1] #:supersample [supersample 1]
                                        #:color-theme [color-theme #f] #:captions? [captions? #t]
                                        #:labels [labels (hash)] #:mp4 [mp4 #f])
  (define report
    (render-geometry-frame-indices/report!
     timeline
     (build-list (geometry-frame-count timeline fps) values)
     directory
     #:width width #:height height
     #:fps fps #:workers workers
     #:supersample supersample
     #:color-theme color-theme #:captions? captions? #:labels labels))
  (write-geometry-subtitles! timeline (build-path directory "narration.srt"))
  (when mp4
    (output:encode-mp4! directory mp4 #:fps fps #:width width #:height height))
  report)

(define (render-geometry-frames! timeline directory #:width [width 1280] #:height [height 720]
                                 #:fps [fps 30] #:workers [workers 1] #:supersample [supersample 1]
                                 #:color-theme [color-theme #f] #:captions? [captions? #t]
                                 #:labels [labels (hash)] #:mp4 [mp4 #f])
  (output:render-diagnostics-paths
   (render-geometry-frames/report! timeline directory #:width width #:height height
                                   #:fps fps #:workers workers #:supersample supersample
                                   #:color-theme color-theme #:captions? captions?
                                   #:labels labels #:mp4 mp4)))
(define (render-geometry-stills! timeline directory #:width [width 1280] #:height [height 720]
                                #:fps [fps 30] #:color-theme [color-theme #f]
                                #:captions? [captions? #t] #:labels [labels (hash)]
                                #:supersample [supersample 1])
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
  (write-geometry-subtitles! timeline (build-path directory "narration.srt"))
  paths)
