#lang racket/base

;;;
;;; Video Encoder
;;;

;; Invokes FFmpeg to assemble numbered PNG frames into an MP4 file.
;;
;; Frame generation itself has no FFmpeg dependency and remains independently
;; testable through frame-renderer.rkt and png-renderer.rkt.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         racket/path
         racket/system)

;; Exports
(provide encode-mp4!)


;;;
;;; MP4 Output
;;;

; encode-mp4! : path-string? path-string?
;               [#:fps exact-positive-integer?]
;               [#:width (or/c false/c exact-positive-integer?)]
;               [#:height (or/c false/c exact-positive-integer?)]
;               -> path-string?
;;   Encodes numbered PNG frames as an H.264 MP4 file using FFmpeg. Supplying
;;   both width and height resizes the source with Lanczos filtering.
(define (encode-mp4! frames-directory output-file #:fps [fps 30]
                     #:width [width #f] #:height [height #f])
  (unless (path-string? frames-directory)
    (raise-argument-error
     'encode-mp4!
     "path-string?"
     frames-directory))
  (unless (path-string? output-file)
    (raise-argument-error 'encode-mp4! "path-string?" output-file))
  (unless (exact-positive-integer? fps)
    (raise-argument-error
     'encode-mp4!
     "exact-positive-integer?"
     fps))
  (unless (or (and (not width) (not height))
              (and (exact-positive-integer? width)
                   (exact-positive-integer? height)))
    (raise-arguments-error
     'encode-mp4!
     "both #:width and #:height must be positive exact integers, or both omitted"
     "width" width
     "height" height))
  (define ffmpeg
    (find-executable-path "ffmpeg"))
  (unless ffmpeg
    (raise-arguments-error
     'encode-mp4!
     "FFmpeg was not found on PATH"
     "executable" "ffmpeg"))
  (define input-pattern
    (path->string
     (build-path frames-directory "frame-%06d.png")))
  (define scale-arguments
    (if width
        (list "-vf" (format "scale=~a:~a:flags=lanczos" width height))
        '()))
  (define succeeded?
    (apply system* ffmpeg
           (append
            (list "-y"
                  "-framerate" (number->string fps)
                  "-i" input-pattern)
            scale-arguments
            (list "-c:v" "libx264"
                  "-pix_fmt" "yuv420p"
                  (path->string
                   (if (path? output-file)
                       output-file
                       (string->path output-file)))))))
  (unless succeeded?
    (raise-arguments-error
     'encode-mp4!
     "FFmpeg failed to encode the frame sequence"
     "frames-directory" frames-directory
     "output-file" output-file))
  output-file)
