#lang racket/base
(require rackunit racket/file racket/list racket/path
         "../main.rkt" "../pict.rkt" "../render.rkt"
         "../private/data.rkt" "../private/sample.rkt" "../private/codec.rkt"
         "../../project.rkt" "../../colors.rkt" "helpers.rkt")
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
       (lambda () (delete-directory/files temp))))
   (test-case "all new transition options survive parent-to-worker handoff"
     (define temp (make-temporary-file "slides-transition-codec-~a" 'directory))
     (dynamic-wind void
       (lambda ()
         (for ([tr (in-list (list (slide-transition #:effect 'push #:direction 'down #:easing 'ease-in)
                                  (slide-transition #:effect 'wipe #:direction 'up #:easing 'ease-out)
                                  (slide-transition #:effect 'cover #:direction 'right #:easing 'smooth)
                                  (slide-transition #:effect 'uncover #:direction 'left #:easing 'ease-in-out)
                                  (slide-transition #:effect 'zoom #:scale 0.73)
                                  (slide-transition #:effect 'fade-through)
                                  (slide-transition #:effect 'fade-through #:color "#123456")
                                  (slide-transition #:effect 'fade-through #:color theme-accent)))])
           (define source (storyboard
              (storyboard-shot 'a (hold-slide (slide #:layout 'title [title "A"]) #:duration 1))
              tr
              (storyboard-shot 'b (hold-slide (slide #:layout 'title [title "B"]) #:duration 1))))
           (define original (prepare-storyboard! source))
           (define-values (payload artifacts dependencies) (prepared-storyboard->payload! original temp))
           (check-true (source-transfer-data? payload))
           (define restored (payload->prepared-storyboard payload source))
           (check-equal? (prepared-bridge-transition (car (prepared-storyboard-value-bridges restored))) tr)
           (for ([q (in-list '(0 1/4 1/2 3/4 1))])
             (define t (+ 1 (* q (slide-transition-duration tr))))
             (check-equal? (sample-signature (sample-storyboard original t))
                           (sample-signature (sample-storyboard restored t))))))
       (lambda () (delete-directory/files temp))))
   (test-case "old preparation schemas are rejected instead of losing options"
     (check-exn (code? 'invalid-payload)
       (lambda ()
         (payload->prepared-storyboard
          (hash 'schema 'animate-slides-preparation-v1)
          (storyboard (storyboard-shot 'a (hold-slide (slide #:layout 'title [title "A"]) #:duration 1)))))))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'codec-test "failed")))
