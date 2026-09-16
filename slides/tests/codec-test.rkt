#lang racket/base
(require rackunit racket/file racket/list racket/path
         "../main.rkt" "../pict.rkt" "../render.rkt"
         "../private/data.rkt" "../private/sample.rkt" "../private/codec.rkt"
         "../../project.rkt" "helpers.rkt")
(provide tests)
(define tests
  (test-suite
   "parent preparation and worker-local replay"
   (test-case "portable drawing payload round-trips without layout"
     (define board (storyboard (storyboard-shot 'opening
       (build-slide (slide #:layout 'title [title "Prepared once"] [subtitle "Replayed as drawing commands"])
          #:initial 'hidden (beat 'intro #:duration 2 (reveal-slot 'title #:duration 1) (reveal-slot 'subtitle #:duration 1))))))
     (define prepared (prepare-storyboard! board))
     (define temp (make-temporary-file "slides-codec-~a" 'directory))
     (dynamic-wind void
       (lambda ()
         (define-values (payload artifacts dependencies) (prepared-storyboard->payload! prepared temp))
         (check-true (source-transfer-data? payload))
         (check-true (pair? artifacts))
         (define restored (payload->prepared-storyboard payload board))
         (check-equal? (prepared-duration restored) (prepared-duration prepared))
         (for ([t (in-list '(0 1/2 1 2))])
           (check-equal? (sample-signature (sample-storyboard prepared t))
                         (sample-signature (sample-storyboard restored t))))
         (define difference
           (max-pixel-difference
            (pixel-bytes (storyboard->pict prepared #:at 1 #:size '(640 360)))
            (pixel-bytes (storyboard->pict restored #:at 1 #:size '(640 360)))))
         (check-true (<= difference 12))
         (define artifact-path (hash-ref (car artifacts) 'path))
         (display-to-file "tampered" artifact-path #:exists 'truncate/replace)
         (check-exn (code? 'artifact-integrity) (lambda () (payload->prepared-storyboard payload board))))
       (lambda () (delete-directory/files temp))))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'codec-test "failed")))
