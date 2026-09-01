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
(require racket/path
         racket/system)

;; Exports
(provide encode-mp4!)


;;;
;;; MP4 Output
;;;

; encode-mp4! : path-string? path-string?
;               [#:fps exact-positive-integer?]
;               -> path-string?
;;   Encodes numbered PNG frames as an H.264 MP4 file using FFmpeg.
(define (encode-mp4! frames-directory output-file #:fps [fps 30])
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
  (define succeeded?
    (system* ffmpeg
             "-y"
             "-framerate" (number->string fps)
             "-i" input-pattern
             "-c:v" "libx264"
             "-pix_fmt" "yuv420p"
             (path->string
              (if (path? output-file)
                  output-file
                  (string->path output-file)))))
  (unless succeeded?
    (raise-arguments-error
     'encode-mp4!
     "FFmpeg failed to encode the frame sequence"
     "frames-directory" frames-directory
     "output-file" output-file))
  output-file)
