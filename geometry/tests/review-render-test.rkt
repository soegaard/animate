#lang racket/base

;; Native end-to-end tests. Require the enclosing Animate checkout and the same
;; graphical dependencies as ordinary PNG rendering; no FFmpeg is invoked.
(require rackunit racket/class racket/draw racket/file racket/list json file/unzip
         (prefix-in a: "../../main.rkt") (prefix-in colors: "../../colors.rkt")
         "../main.rkt" "../review.rkt")

(construction review-fixture
  (given [A (point -2 0)] [B (point 2 0)])
  (timing [opening-pause 1/5] [read-delay 2/5] [action-duration 1] [step-pause 3/5])
  (step "Join A to B." [AB (segment A B)])
  (step "A is one endpoint." (highlight A))
  (step "The two endpoints are distinct." (highlight A B))
  (step "Observe the segment." (hide-label A))
  (step "A is its left endpoint." (show-label A))
  (step "The segment joins A and B." (highlight AB))
  (step #:pause 0 "This is the complete segment."))

(define (with-root f)
  (define root (make-temporary-file "geometry-native-review-~a" 'directory))
  (dynamic-wind void (lambda () (f root)) (lambda () (delete-directory/files root))))
(define (render timeline root name theme #:sheets? [sheets? #t] #:captions? [captions? #t]
                #:supersample [supersample 1])
  (render-geometry-review! timeline (build-path root name) #:name name
                           #:width 320 #:height 180 #:fps 10 #:supersample supersample
                           #:color-theme theme #:theme-name name
                           #:contact-sheet? sheets? #:captions? captions?
                           #:zip (build-path root (string-append name ".zip"))))
(define (image-size path)
  (define b (read-bitmap path))
  (check-true (send b ok?))
  (list (send b get-width) (send b get-height)))

(module+ test
  (test-case "native review renders triplets, paginated sheets and a complete ZIP"
    (with-root
     (lambda (root)
       (define t (construction->timeline review-fixture))
       (define result (render t root "light" colors:animate-light-theme))
       (define dir (geometry-review-result-directory result))
       (check-equal? (geometry-review-result-step-count result) 7)
       (check-equal? (geometry-review-result-image-count result) 21)
       (check-equal? (length (geometry-review-result-contact-sheets result)) 2)
       (for ([s (in-list (geometry-review-samples (make-geometry-review-plan t)))])
         (check-equal? (image-size (build-path dir (geometry-review-sample-filename s))) '(320 180)))
       (for ([sheet (in-list (geometry-review-result-contact-sheets result))])
         (check-equal? (car (image-size sheet)) 1200))
       (check-not-equal? (file->bytes (build-path dir "step-001-read.png"))
                         (file->bytes (build-path dir "step-001-during.png")))
       (check-not-equal? (file->bytes (build-path dir "step-001-during.png"))
                         (file->bytes (build-path dir "step-001-settled.png")))
       (define entries (zip-directory-entries (read-zip-directory (geometry-review-result-zip result))))
       (check-not-false (member #"light/step-007-settled.png" entries))
       (check-not-false (member #"light/contact-sheet-002.png" entries))
       (check-not-false (member #"light/steps.txt" entries)))))
  (test-case "light and dark reviews use their native render themes"
    (with-root
     (lambda (root)
       (define light (construction->timeline review-fixture #:theme default-light-geometry-theme))
       (define dark (construction->timeline review-fixture #:theme default-dark-geometry-theme))
       (define l (render light root "light" colors:animate-light-theme #:sheets? #f))
       (define d (render dark root "dark" colors:animate-dark-theme #:sheets? #f))
       (check-equal? (geometry-review-result-contact-sheets l) '())
       (check-not-equal?
        (file->bytes (build-path (geometry-review-result-directory l) "step-001-read.png"))
        (file->bytes (build-path (geometry-review-result-directory d) "step-001-read.png"))))))
  (test-case "review no-captions preserves written narration and supersampled dimensions"
    (with-root
     (lambda (root)
       (define t (construction->timeline review-fixture))
       (define result (render t root "light" colors:animate-light-theme #:sheets? #f
                              #:captions? #f #:supersample 2))
       (define dir (geometry-review-result-directory result))
       (check-equal? (image-size (build-path dir "step-001-read.png")) '(640 360))
       (define m (call-with-input-file (build-path dir "manifest.json") read-json))
       (check-false (hash-ref m 'captions))
       (check-equal? (hash-ref (car (hash-ref m 'steps)) 'narration) "Join A to B.")
       (check-true (regexp-match? #rx"Join A to B" (file->string (build-path dir "steps.txt"))))))))
