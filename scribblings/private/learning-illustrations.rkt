#lang racket/base
;; Stored screenshots only. Requiring this helper never launches a renderer.
(require json racket/file racket/path racket/runtime-path "frame-style.rkt")
(provide learning-frames)
(define-runtime-path directory "../figures/learning-r4")
(define (learning-frames key #:columns [columns #f])
  (define manifest (build-path directory "manifest.json"))
  (unless (file-exists? manifest)
    (raise-user-error 'learning-frames
     "Missing manual figures. Run racket scribblings/render-learning-illustrations.rkt --install first."))
  (define data (call-with-input-file manifest read-json))
  (unless (equal? (hash-ref data 'schema #f) "animate-manual-learning-frames-v1")
    (raise-user-error 'learning-frames "unrecognized illustration manifest"))
  (define strip (hash-ref (hash-ref data 'strips) (string->symbol key)))
  (manual-frame-strip
   (for/list ([frame (in-list (hash-ref strip 'frames))])
     (define name (hash-ref frame 'file))
     (unless (regexp-match? #px"^[a-z0-9-]+\\.png$" name)
       (raise-user-error 'learning-frames "unsafe picture name"))
     (manual-frame (build-path directory name)
                   (hash-ref frame 'width) (hash-ref frame 'height)
                   (hash-ref frame 'caption)))
   #:columns columns #:label key #:note (hash-ref strip 'note)))
