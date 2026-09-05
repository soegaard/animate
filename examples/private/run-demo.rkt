#lang racket/base

(require racket/cmdline
         animate
         animate/render)

(provide run-demo)

(define (run-demo program make-demo-scene #:workers [workers 1] #:diagnostics? [diagnostics? #f]
                  #:supersample [supersample 1])
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
      (render-frames/report! scene output-directory #:fps 30 #:workers workers
                             #:supersample supersample))
    (set! paths (render-diagnostics-paths report))
    (printf "Rendered ~a frames with ~a workers; ~a cache hits, ~a misses\n"
            (render-diagnostics-frame-count report)
            (render-diagnostics-workers report)
            (render-diagnostics-cache-hits report)
            (render-diagnostics-cache-misses report)))
  (unless diagnostics?
    (set! paths (render-frames! scene output-directory #:fps 30 #:workers workers
                                #:supersample supersample))
    (printf "Rendered ~a frames to ~a\n" (length paths) output-directory))
  (when output-video
    (cond
      [(= supersample 1)
       (encode-mp4! output-directory output-video #:fps 30)]
      [else
       (define camera (scene-camera-at scene 0))
       (encode-mp4! output-directory output-video #:fps 30
                    #:width (camera-width camera)
                    #:height (camera-height camera))])
    (printf "Encoded ~a\n" output-video)))
