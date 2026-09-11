#lang racket/base

;; Native integration tests. These intentionally use the containing checkout's
;; real Animate/pict/draw implementation, never a mock renderer.
(require rackunit racket/class racket/file racket/runtime-path racket/list
         (prefix-in a: "../../main.rkt") (prefix-in colors: "../../colors.rkt")
         "../main.rkt" "../render.rkt" "../examples/private/library-example-names.rkt")
(define-runtime-path examples "../examples")
(module+ test
  (for* ([name (in-list library-example-names)] [mode '(light dark)])
    (test-case (format "native scene, measured layout and bitmaps: ~a / ~a" name mode)
      (define path (build-path examples (string-append name ".rkt")))
      (define make (dynamic-require path 'make-demo-timeline))
      (define t (make #:theme-mode mode))
      (define theme (if (eq? mode 'light) colors:animate-light-theme colors:animate-dark-theme))
      (define scene (geometry-timeline->scene t #:width 320 #:height 180 #:id 'library-scene))
      (check-true (a:scene? scene))
      (check-= (a:scene-duration scene) (geometry-timeline-duration t) 1e-8)
      (define last-index (sub1 (a:scene-frame-count scene #:fps 1)))
      (define ending (a:scene-visual-at scene 'library-scene last-index))
      (a:scene-visual-at scene 'library-scene 0)
      (check-equal? ending (a:scene-visual-at scene 'library-scene last-index))
      (for ([index (in-list (list (quotient last-index 2) last-index))])
        (define bitmap (a:scene-frame->bitmap scene index #:fps 1 #:theme theme))
        (check-equal? (send bitmap get-width) 320)
        (check-equal? (send bitmap get-height) 180))))
  (test-case "standard-library example writes PNGs and nonempty subtitle cues"
    (define make (dynamic-require (build-path examples "square-on-segment.rkt") 'make-demo-timeline))
    (define t (make))
    (define directory (make-temporary-file "geometry-library-native-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define paths (render-geometry-stills! t directory #:width 320 #:height 180 #:fps 2))
        (check-true (> (length paths) 2))
        (for ([path (in-list paths)])
          (check-equal? (subbytes (file->bytes path) 0 8) #"\211PNG\r\n\032\n"))
        (check-true (positive? (file-size (build-path directory "narration.srt"))))
        (check-true (file-exists? (build-path directory "stills.tsv"))))
      (lambda () (delete-directory/files directory)))))
