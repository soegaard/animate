#lang racket/base
;; Read genuine stored captures. Never start an animation renderer from Scribble.
(require json racket/file racket/path racket/runtime-path "frame-style.rkt")
(provide three-d-frames)
(define-runtime-path directory "../figures/3d-r3")
(define (three-d-frames key #:columns [columns #f])
  (define manifest (build-path directory "manifest.json"))
  (unless (file-exists? manifest)
    (raise-user-error
     'three-d-frames
     "3D manual frames are missing. From the checkout root run: racket scribblings/render-3d-illustrations.rkt --install"))
  (define data (call-with-input-file manifest read-json))
  (unless (equal? (hash-ref data 'schema #f) "animate-manual-3d-frames-v1")
    (raise-user-error 'three-d-frames "unrecognized 3D illustration manifest"))
  (define strip (hash-ref (hash-ref data 'strips) (string->symbol key)))
  (define frames (hash-ref strip 'frames))
  (manual-frame-strip
   (for/list ([frame (in-list frames)])
     (manual-frame (build-path directory (hash-ref frame 'file))
                   (hash-ref frame 'width) (hash-ref frame 'height)
                   (hash-ref frame 'caption)))
   #:columns columns #:label key
   #:note (if (= (length frames) 1)
              "A still picture, sampled at time zero."
              "Frames sampled directly from this example; times are in seconds.")))
