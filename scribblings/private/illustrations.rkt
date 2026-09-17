#lang racket/base
;; Illustrations are checked-in frame captures, not build-time render jobs.
(require json racket/file racket/list racket/path racket/runtime-path
         scribble/manual)
(provide frame-strip)
(define-runtime-path figure-directory "../figures")
(define catalogue
  (hash-ref (call-with-input-file (build-path figure-directory "illustrations.json") read-json)
            'strips))
(define (chunks xs n)
  (if (null? xs) '()
      (let ([count (min n (length xs))])
        (cons (take xs count) (chunks (drop xs count) n)))))
(define (frame-strip key)
  (unless (and (string? key) (hash-has-key? catalogue (string->symbol key)))
    (raise-argument-error 'frame-strip "known illustration key" key))
  (define spec (hash-ref catalogue (string->symbol key)))
  (define columns (hash-ref spec 'columns 2))
  (define frames (hash-ref spec 'frames))
  (define cells
    (for/list ([frame (in-list frames)])
      (define path (simplify-path (build-path figure-directory (hash-ref frame 'file))))
      (unless (file-exists? path)
        (raise-arguments-error 'frame-strip "existing captured frame" "path" path))
      ;; Three-column strips are used for compact diagrams; slide frames get
      ;; two columns so their text remains readable. The original is retained.
      (define width (if (= columns 3) 150 230))
      (define scale (min 1 (/ width (hash-ref frame 'width))))
      (list (image path #:scale scale (hash-ref frame 'caption))
            (smaller (hash-ref frame 'caption)))))
  (define rows
    (append-map
     (lambda (row)
       (define pad (make-list (- columns (length row)) ""))
       (list (append (map car row) pad)
             (append (map cadr row) pad)))
     (chunks cells columns)))
  (nested
   (centered (tabular #:sep (hspace 1) rows))
   (smaller
    (case (string->symbol (hash-ref spec 'kind "animation"))
      [(still) "A still picture; it has no playback duration."]
      [(comparison) "Alternative views of the same content, not consecutive frames."]
      [else "Sample times are measured from the start of this example."]))))
