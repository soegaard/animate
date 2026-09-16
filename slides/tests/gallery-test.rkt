#lang racket/base
(require rackunit racket/list racket/file racket/path json
         (only-in pict pict? pict-width pict-height)
         "../main.rkt" "../gallery.rkt" "../pict.rkt" "../render.rkt"
         "../private/data.rkt" "../private/content.rkt" "../private/sample.rkt"
         "../private/gallery/times.rkt" "../private/gallery/render.rkt"
         "../private/project-artifacts.rkt" "helpers.rkt")
(provide tests)
(define tests
  (test-suite
   "author-facing slide gallery"
   (test-case "catalogue is complete, unique, and requirement-labelled"
     (check-equal? (length slide-gallery-entries) 42)
     (define ids (map slide-gallery-entry-id slide-gallery-entries))
     (check-equal? (length (remove-duplicates ids)) (length ids))
     (check-equal? (length (select-slide-gallery-entries #:category 'layouts)) 12)
     (check-equal? (length (select-slide-gallery-entries #:category 'transitions)) 23)
     (check-equal? (length (select-slide-gallery-entries #:category 'integration)) 7)
     (check-equal? (slide-gallery-entry-requirements
                    (car (select-slide-gallery-entries #:entries '(math-and-geometry)))) '(math geometry)))
   (test-case "selection preserves authored order and rejects typos"
     (check-equal? (map slide-gallery-entry-id (select-slide-gallery-entries #:entries '(zoom push-left))) '(zoom push-left))
     (for ([thunk (in-list (list (lambda () (select-slide-gallery-entries #:entries '(unknown)))
                                (lambda () (select-slide-gallery-entries #:entries '(zoom zoom)))
                                (lambda () (select-slide-gallery-entries #:category 'unknown))
                                (lambda () (select-slide-gallery-entries #:entries '(zoom) #:category 'layouts))))])
       (check-exn exn:fail? thunk)))
   (test-case "every layout prepares in both themes and all four formats"
     (for* ([e (in-list (select-slide-gallery-entries #:category 'layouts))]
            [theme (in-list (list lecture-light lecture-dark))]
            [fmt (in-list (list widescreen standard portrait square-format))])
       (define b (prepare-storyboard! (make-slide-gallery #:entries (list (slide-gallery-entry-id e)) #:theme theme #:format fmt)))
       (define size (list (* 20 (slide-format-width fmt)) (* 20 (slide-format-height fmt))))
       (define p (storyboard->pict b #:at 'end #:size size))
       (check-true (pict? p))
       (check-equal? (list (pict-width p) (pict-height p)) size)))
   (test-case "native Scene gallery entry constructs and samples"
     ;; Core Animate rate functions such as `smooth` are constructors. This
     ;; catches passing the constructor itself to scene-play instead of the
     ;; unary rate function returned by `(smooth)`.
     (define b (prepare-storyboard! (make-slide-gallery #:entries '(native-scene))))
     (check-true (> (prepared-duration b) 1))
     (define midpoint (/ (prepared-duration b) 2))
     (check-true (frame-value? (sample-storyboard b midpoint)))
     (check-true (pict? (storyboard->pict b #:at midpoint #:size '(320 180)))))
   (test-case "gallery match really preserves one title rather than crossfading it"
     (define b (prepare-storyboard! (make-slide-gallery #:entries '(match))))
     (define bridge (car (prepared-storyboard-value-bridges b)))
     (define frame (sample-storyboard b (+ (prepared-bridge-start bridge) 1/2)))
     (define titles (filter (lambda (l) (eq? (frame-leaf-key l) 'topic)) (frame-value-leaves frame)))
     (check-equal? (length titles) 1)
     (check-equal? (frame-leaf-opacity (car titles)) 1))
   (test-case "transition gallery prepares and samples bridge interiors"
     (for ([e (in-list (select-slide-gallery-entries #:category 'transitions))])
       (define b (prepare-storyboard! (make-slide-gallery #:entries (list (slide-gallery-entry-id e)))))
       (define times (gallery-review-times b))
       (check-equal? (car times) 0)
       (check-equal? (last times) (prepared-duration b))
       (for ([t (in-list times)]) (check-true (frame-value? (sample-storyboard b t))))))
   (test-case "catalogue chapters compose without occurrence-ID collisions"
     (define b (make-slide-gallery #:category 'transitions))
     (check-true (storyboard? b))
     (define p (prepare-storyboard! b))
     (define ids (map prepared-shot-id (prepared-storyboard-value-shots p)))
     (check-equal? (length ids) (length (remove-duplicates ids))))
   (test-case "project artifact reports are semantic hashes"
     (define primary (build-path "tmp" "gallery.mp4"))
     (define frame-a (build-path "tmp" "frame-000000.png"))
     (define frame-b (build-path "tmp" "frame-000001.png"))
     (define artifacts
       (hasheq 'primary primary 'frame-sequence #f 'frames (list frame-a frame-b)))
     (check-equal? (project-primary-artifact-path artifacts) primary)
     (check-equal? (project-artifact-path-list artifacts)
                   (list primary frame-a frame-b))
     (check-exn exn:fail? (lambda () (project-primary-artifact-path (hasheq 'frames '())))))
   (test-case "browsable export writes images, source, manifest, and review ZIP"
     (define temp (make-temporary-file "slides-gallery-export-~a" 'directory))
     (dynamic-wind void
       (lambda ()
         (define output (build-path temp "review"))
         (check-equal?
          (render-slide-gallery! (select-slide-gallery-entries #:entries '(push-left)) output
                                 #:width 320 #:repeat 2) 0)
         (check-true (file-exists? (build-path output "index.html")))
         (check-true (file-exists? (build-path output "posters" "push-left.png")))
         (check-true (file-exists? (build-path temp "review.zip")))
         (define manifest (call-with-input-file (build-path output "manifest.json") read-json))
         (check-equal? (hash-ref manifest 'errors) 0)
         (check-equal? (length (hash-ref manifest 'entries)) 1)
         (define entry (car (hash-ref manifest 'entries)))
         (check-false (hash-ref entry 'video))
         (check-true (> (length (hash-ref entry 'samples)) 4))
         ;; Loading the generated source must reconstruct a storyboard without
         ;; preparing TeX or launching a movie render.
         (check-true (storyboard? (dynamic-require (build-path output "sources" "push-left.rkt") 'film))))
       (lambda () (delete-directory/files temp))))
   (test-case "native preferred intrinsic viewports are finite and effect-free"
     (define ctx (content-context-value lecture-light portrait (box-value 0 0 8 1000000) #f #f))
     (for ([kind (in-list '(math geometry))])
       ;; Intentionally opaque payload: intrinsic sizing must not execute it.
       (define c (content-value kind 'unprepared (hash 'aspect 16/9)))
       (define-values (w h) (intrinsic-content c 'body 8 ctx))
       (check-equal? w 8) (check-equal? h 9/2)))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'gallery-test "failed")))
