#lang racket/base
;; Stored captures only; a Scribble build never starts an animation renderer.
(require json racket/file racket/path racket/runtime-path "frame-style.rkt")
(provide frame-strip)
(define-runtime-path figure-directory "../figures")
(define catalogue
  (hash-ref (call-with-input-file (build-path figure-directory "illustrations.json") read-json)
            'strips))
(define (frame-strip key #:columns [columns #f])
  (unless (and (string? key) (hash-has-key? catalogue (string->symbol key)))
    (raise-argument-error 'frame-strip "known illustration key" key))
  (define spec (hash-ref catalogue (string->symbol key)))
  (manual-frame-strip
   (for/list ([frame (in-list (hash-ref spec 'frames))])
     (manual-frame
      (simplify-path (build-path figure-directory (hash-ref frame 'file)))
      (hash-ref frame 'width) (hash-ref frame 'height) (hash-ref frame 'caption)))
   #:columns columns #:label key
   #:note
   (case (string->symbol (hash-ref spec 'kind "animation"))
     [(still) "A still picture; it has no playback duration."]
     [(comparison) "Alternative views of the same content, not consecutive frames."]
     [else "Sample times are measured from the start of this example."])))
