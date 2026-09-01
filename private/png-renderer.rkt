#lang racket/base

;;;
;;; PNG Renderer
;;;

;; Writes deterministic numbered PNG frames for a sampled scene.
;;
;; Filesystem changes are isolated in this module and use names ending in !.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/class
         racket/file
         racket/format
         racket/path
         "camera.rkt"
         "frame-renderer.rkt"
         "pict-adapter.rkt"
         "pict-renderer.rkt")

;; Exports
(provide render-frames!)


;;;
;;; Constants
;;;

; frame-name-pattern : regexp?
;;   Matches numbered PNG files owned by the frame renderer.
(define frame-name-pattern
  #px"^frame-[0-9]{6,}\\.png$")


;;;
;;; Frame Output
;;;

; render-frames! : scene? path-string?
;                  [#:fps exact-positive-integer?]
;                  [#:camera (or/c camera? false/c)]
;                  [#:renderers (listof pict-renderer?)]
;                  [#:clean? boolean?]
;                  -> (listof path?)
;;   Writes every sampled scene frame as a numbered PNG file.
(define (render-frames! scene output-directory
                        #:fps [fps 30]
                        #:camera [camera #f]
                        #:renderers [renderers default-pict-renderers]
                        #:clean? [clean? #t])
  (define frame-count
    (scene-frame-count scene #:fps fps))
  (unless (path-string? output-directory)
    (raise-argument-error
     'render-frames!
     "path-string?"
     output-directory))
  (unless (or (not camera)
              (camera? camera))
    (raise-argument-error
     'render-frames!
     "(or/c camera? false/c)"
     camera))
  (check-pict-renderer-list 'render-frames! renderers)
  (unless (boolean? clean?)
    (raise-argument-error 'render-frames! "boolean?" clean?))
  (make-directory* output-directory)
  (when clean?
    (delete-old-frames! output-directory))
  (for/list ([frame-index (in-range frame-count)])
    (define path
      (frame-index->path output-directory frame-index))
    (define bitmap
      (scene-frame->bitmap scene
                           frame-index
                           #:fps fps
                           #:camera camera
                           #:renderers renderers))
    (unless (send bitmap save-file path 'png)
      (raise-arguments-error
       'render-frames!
       "could not save a PNG frame"
       "path" path))
    path))

; frame-index->path : path-string? exact-nonnegative-integer? -> path?
;;   Converts frame-index to its zero-padded PNG output path.
(define (frame-index->path output-directory frame-index)
  (build-path
   output-directory
   (format "frame-~a.png"
           (~r frame-index
               #:min-width 6
               #:pad-string "0"))))

; delete-old-frames! : path-string? -> void?
;;   Deletes only numbered PNG files previously owned by the renderer.
(define (delete-old-frames! output-directory)
  (for ([entry (in-list (directory-list output-directory))])
    (when (regexp-match? frame-name-pattern (path->string entry))
      (delete-file (build-path output-directory entry)))))
