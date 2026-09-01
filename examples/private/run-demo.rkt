#lang racket/base

(require racket/cmdline
         "../../main.rkt")

(provide run-demo)

(define (run-demo program make-demo-scene #:workers [workers 1] #:diagnostics? [diagnostics? #f])
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program program
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define scene (make-demo-scene))
  (define paths #f)
  (when diagnostics?
    (define report
      (render-frames/report! scene output-directory #:fps 30 #:workers workers))
    (set! paths (render-diagnostics-paths report))
    (printf "Rendered ~a frames with ~a workers; ~a cache hits, ~a misses\n"
            (render-diagnostics-frame-count report)
            (render-diagnostics-workers report)
            (render-diagnostics-cache-hits report)
            (render-diagnostics-cache-misses report)))
  (unless diagnostics?
    (set! paths (render-frames! scene output-directory #:fps 30 #:workers workers))
    (printf "Rendered ~a frames to ~a\n" (length paths) output-directory))
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
