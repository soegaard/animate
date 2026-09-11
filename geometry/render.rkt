#lang racket/base

;; Effectful output only. Native animate rendering/FFmpeg remain responsible
;; for pixels and encoding; this module adds narration and selected step stills.
(require racket/list racket/file racket/format
         (prefix-in output: "../render.rkt")
         "main.rkt")
(provide render-geometry-frames! render-geometry-frames/report! render-geometry-stills!
         render-geometry-frame-indices! geometry-frame-count
         write-geometry-subtitles! geometry-caption-cues)

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

(define (render-geometry-frame-indices! timeline indices directory #:width [width 1280] #:height [height 720]
                                       #:fps [fps 30] #:supersample [supersample 1]
                                       #:color-theme [color-theme #f] #:captions? [captions? #t]
                                       #:labels [labels (hash)])
  (unless (and (geometry-timeline? timeline) (list? indices) (andmap exact-nonnegative-integer? indices)
               (exact-positive-integer? fps))
    (geometry-error 'render-geometry-frame-indices! "invalid timeline, indices, or fps"))
  (define scene (geometry-timeline->scene timeline #:width width #:height height
                                         #:captions? captions? #:labels labels))
  (output:render-frame-indices! scene indices directory #:fps fps
                               #:theme color-theme #:supersample supersample))

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
  (define scene (geometry-timeline->scene timeline #:width width #:height height
                                         #:captions? captions? #:labels labels))
  (define report
    (output:render-frames/report! scene directory #:fps fps #:workers workers
                                  #:supersample supersample #:theme color-theme))
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
  (define scene (geometry-timeline->scene timeline #:width width #:height height
                                         #:captions? captions? #:labels labels))
  (define (index-before time)
    (max 0 (sub1 (inexact->exact (floor (* fps time))))))
  (define indices
    (sort (remove-duplicates
           (append (list 0 (index-before (geometry-timeline-duration timeline)))
                   (map (lambda (c) (index-before (geometry-cue-end c))) (geometry-timeline-cues timeline)))) <))
  (define paths (output:render-frame-indices! scene indices directory #:fps fps
                                             #:theme color-theme #:supersample supersample))
  (call-with-output-file (build-path directory "stills.tsv")
    (lambda (out)
      (fprintf out "image\ttime-seconds\tnarration\n")
      (for ([path (in-list paths)] [i (in-list indices)])
        (fprintf out "~a\t~a\t~a\n" path (exact->inexact (/ i fps))
                 (or (geometry-timeline-narration-at timeline (/ i fps)) ""))))
    #:exists 'truncate/replace)
  (write-geometry-subtitles! timeline (build-path directory "narration.srt"))
  paths)
