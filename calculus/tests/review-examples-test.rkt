#lang racket/base

;;;
;;; Calculus Sparse-review Bundle Tests
;;;

;; Exercises a real but compact native review bundle.  This is deliberately a
;; separate gate from human inspection: it proves the artifacts are made and
;; linked, not that their mathematical communication has been approved.


;;;
;;; Imports
;;;

(require rackunit
         racket/file
         racket/path
         racket/system
         "../review-examples.rkt")


;;;
;;; Tests
;;;

(module+ test
  (define root (make-temporary-file "animate-calculus-review-test-~a" 'directory))
  (define output (build-path root "review"))
  (dynamic-wind
   void
   (lambda ()
     (define rows
       (run-calculus-review!
        #:fixtures '(reading-square)
        #:profiles '(light)
        #:width 320 #:height 180 #:workers 10
        #:output output))
     ;; The first complete Guide lesson has three authored steps.  Its stable
     ;; sparse plan includes start, midpoint, and endpoint samples without a
     ;; duplicate at shared event boundaries.
     (check-equal? (length rows) 13)
     (check-true (file-exists? (build-path output "index.html")))
     (check-true (file-exists? (build-path output "manifest.rktd")))
     (check-equal?
      (length
       (for/list ([path (in-directory (build-path output "light"))]
                  #:when (regexp-match? #px"reading-square-[0-9]{3}\\.png$"
                                       (path->string path)))
         path))
      13)
     ;; Thumbnails are navigation aids, so a 13-frame bundle needs two pages.
     (check-equal?
      (length
       (for/list ([path (in-directory (build-path output "light"))]
                  #:when (regexp-match? #px"contact-sheet-light-[0-9]{3}\\.png$"
                                       (path->string path)))
         path))
      2)
     ;; Existing evidence is never silently overwritten on a later run.
     (check-exn exn:fail?
                (lambda ()
                  (run-calculus-review!
                   #:fixtures '(reading-square) #:profiles '(light)
                   #:width 320 #:height 180 #:output output)))
     ;; Clip encoding is optional because some minimal Racket installations do
     ;; not ship an encoder. When the documented ffmpeg dependency is present,
     ;; exercise the real numbered-frame-to-MP4 path rather than merely its
     ;; command-line parsing.
     (when (find-executable-path "ffmpeg")
       (define clip-output (build-path root "clip-review"))
       (run-calculus-review!
        #:fixtures '(reading-square) #:profiles '(light)
        #:width 320 #:height 180 #:workers 10
        #:clips? #t #:clip-fps 4 #:output clip-output)
       (define clip-path
         (build-path clip-output "light" "clips" "reading-square-transition.mp4"))
       (check-true (file-exists? clip-path))
       (check-true (positive? (file-size clip-path)))))
   (lambda ()
     (when (directory-exists? root)
       (delete-directory/files root)))))
