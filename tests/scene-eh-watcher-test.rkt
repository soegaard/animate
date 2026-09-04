#lang racket/base

;; SCENE-EH-6: the portable polling watcher hashes content, debounces a save,
;; and sends the reload through the preview/program controller attachment.

(require rackunit
         racket/file
         "../main.rkt"
         "../preview.rkt")

(define (write-program! path duration)
  (call-with-output-file
   path #:exists 'truncate/replace
   (lambda (out)
     (display "#lang racket/base\n(require animate animate/authoring)\n" out)
     (display "(define-scene-program watched #:initial (make-scene)\n" out)
     (fprintf out "  (scene-block one (scene) (scene-wait scene ~a)))~n" duration)
     (display "(provide watched)\n" out))))

(define (wait-for-generation session generation)
  (let loop ([remaining 30])
    (cond [(>= (preview-program-generation session) generation) #t]
          [(zero? remaining) #f]
          [else (sleep 1/10) (loop (sub1 remaining))])))

(module+ test
  (define temporary-directory (simplify-path (build-path (current-directory) ".." "tmp")))
  (make-directory* temporary-directory)
  (define source-path
    (make-temporary-file "scene-eh-watcher-~a.rkt" #f temporary-directory))
  (dynamic-wind
    void
    (lambda ()
      (write-program! source-path 1)
      (define session
        (open-program-preview-controller
         source-path 'watched #:auto-reload? #t #:fps 2 #:prefetch 0
         #:producer (lambda (_document _sample _spec) 'bitmap)
         #:byte-size (lambda (_bitmap) 1)))
      ;; Let the watcher take its initial content snapshot before simulating
      ;; an editor save burst.
      (sleep 1/2)
      ;; A burst ending in duration 3 produces one generation replacement with
      ;; the settled bytes, not one reload for each filesystem write.
      (write-program! source-path 2)
      (write-program! source-path 3)
      (check-true (wait-for-generation session 1))
      (check-equal? (scene-duration (preview-source session)) 3)
      (preview-close! session))
    (lambda ()
      (when (file-exists? source-path) (delete-file source-path)))))
