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
         racket/string
         racket/system
         "encoder-profile.rkt")

;; Exports
(provide encode-mp4!)


;;;
;;; MP4 Output
;;;

; encode-mp4! : path-string? path-string?
;               [#:fps exact-positive-integer?]
;               [#:width (or/c false/c exact-positive-integer?)]
;               [#:height (or/c false/c exact-positive-integer?)]
;               [#:codec symbol?] [#:pixel-format symbol?]
;               [#:options immutable-hash?] [#:fast-start? boolean?]
;               -> path-string?
;;   Encodes numbered PNG frames using an explicit FFmpeg video profile.
;;   Supplying both width and height resizes the source with Lanczos filtering.
(define (encode-mp4! frames-directory output-file #:fps [fps 30]
                     #:width [width #f] #:height [height #f]
                     #:codec [codec 'h264]
                     #:pixel-format [pixel-format 'yuv420p]
                     #:options [options #hasheq()]
                     #:fast-start? [fast-start? #t])
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
  (unless (symbol? codec)
    (raise-argument-error 'encode-mp4! "symbol?" codec))
  (unless (symbol? pixel-format)
    (raise-argument-error 'encode-mp4! "symbol?" pixel-format))
  (unless (hash? options)
    (raise-argument-error 'encode-mp4! "hash?" options))
  (unless (boolean? fast-start?)
    (raise-argument-error 'encode-mp4! "boolean?" fast-start?))
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
            (list "-c:v" (encoder-codec-name codec)
                  "-pix_fmt" (symbol->string pixel-format))
            (encoder-option-arguments options)
            (if fast-start? (list "-movflags" "+faststart") '())
            (list
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

(define (encoder-option-arguments options)
  (apply append
         (for/list ([entry
                     (in-list
                      (sort (hash->list options)
                            string<?
                            #:key (lambda (entry)
                                    (format "~a" (car entry)))))])
           (define key (car entry))
           (define value (cdr entry))
           (unless (symbol? key)
             (raise-argument-error 'encode-mp4! "symbol option key" key))
           (unless (or (string? value) (number? value) (symbol? value))
             (raise-argument-error
              'encode-mp4! "string?, number?, or symbol option value" value))
           (list (string-append "-" (symbol->string key))
                 (format "~a" value)))))
