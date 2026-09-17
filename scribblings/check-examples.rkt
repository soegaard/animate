#lang racket/base

;; Execute the same source files displayed in the manual. No MP4 encoding or GUI.
(require racket/cmdline racket/runtime-path
         (only-in rackunit test-suite test-case check-true check-equal? check-= check-not-exn)
         (only-in rackunit/text-ui run-tests)
         (only-in pict pict? pict-width pict-height)
         (only-in animate scene? scene-duration scene-sample scene-state->pict scene-camera-at)
         animate/slides animate/slides/pict animate/slides/scene animate/slides/render)
(define-runtime-path examples-directory "examples")
(define (load-example name binding)
  (dynamic-require (build-path examples-directory name) binding))
(define (check-picture picture)
  (check-true (pict? picture))
  (check-true (> (pict-width picture) 0))
  (check-true (> (pict-height picture) 0)))
(define (check-board name [expected #f] [extra-times '()])
  (define board (prepare-storyboard! (load-example name 'film)))
  (define scene (storyboard->scene board #:size '(320 180)))
  (define end (prepared-duration board))
  (check-true (scene? scene))
  (when expected (check-= end expected 1e-8))
  (check-= (scene-duration scene) end 1e-9)
  ;; End, middle, start, and then interior frames: no dependence on seek order.
  (for ([time (in-list (append (list end (/ end 2) 0 (/ end 3)) extra-times))])
    (check-picture (storyboard->pict board #:at time #:size '(320 180)))
    (check-picture (scene-state->pict (scene-sample scene time)
                                     #:camera (scene-camera-at scene time))))
  board)

(module+ main
  (define math? #f)
  (define geometry? #f)
  (command-line #:program "scribblings/check-examples.rkt"
    #:once-each
    [("--math") "Prepare the real mathematical checkpoint example" (set! math? #t)]
    [("--geometry") "Prepare the real construction example" (set! geometry? #t)]
    #:args () (void))
  (define base-tests
    (test-suite "illustrated manual examples"
      (test-case "Quick Start: one-second motion and half-second hold"
        (define sc (load-example "moving-circle.rkt" 'animation))
        (check-equal? (scene-duration sc) 3/2)
        (for ([time (in-list '(3/2 1 3/4 1/2 1/4 0))])
          (check-picture (scene-state->pict (scene-sample sc time)
                                           #:camera (scene-camera-at sc time)))))
      (test-case "source blocks: setup, movement, and hold"
        (define sc (load-example "source-blocks.rkt" 'animation))
        (check-equal? (scene-duration sc) 4)
        (for ([time (in-list '(0 2 4))])
          (check-picture (scene-state->pict (scene-sample sc time)
                                           #:camera (scene-camera-at sc time)))))
      (test-case "plain slide: a picture and a zero-duration Scene"
        (define card (load-example "first-slide.rkt" 'welcome))
        (check-true (slide? card))
        (check-equal? (scene-duration (slide->scene card)) 0)
        (check-picture (slide->pict card)))
      (test-case "four-second title build"
        (void (check-board "first-slide.rkt" 4 '(1))))
      (test-case "five-second bullet build"
        (define clip (prepare-slide! (load-example "builds.rkt" 'clip)))
        (check-= (prepared-duration clip) 5 1e-9)
        (check-picture (slide->pict clip #:at '(identity end)))
        (void (check-board "builds.rkt" 5 '(0.7 1.6 2.5 3.4))))
      (test-case "nineteen point six second lesson and exact cut"
        (define board (check-board "slide-lesson.rkt" 19.6 '(3 7 12 14 14.3 14.6)))
        (check-equal? (length (storyboard->picts board)) 3)
        (check-picture (slide->pict (storyboard-ref board 'rule) #:at '(example end))))
      (test-case "shared title at five transition times"
        (void (check-board "matched-title.rkt" 4 '(1.2 1.45 1.7 1.95 2.2))))
      (test-case "named parts and nested placement"
        (define board (check-board "matched-parts.rkt" 7.5 '(2 2.625 3.25 3.875 4.5)))
        (check-equal? (length (storyboard-match-report board)) 1))
      (test-case "native viewport and independent local clock"
        (void (check-board "native-viewport.rkt" 5.5 '(1 2.5 4))))
      (test-case "complete transition-gallery recipe"
        (void (check-board "transition-gallery.rkt" 4 '(1.2 1.45 1.7 1.95 2.2))))
      (test-case "project declaration loads without rendering"
        (check-not-exn (lambda () (load-example "project.rkt" 'lesson-project))))
      (test-case "custom theme works with the plain title card"
        (define theme (load-example "theme.rkt" 'course-theme))
        (check-true (slide-theme? theme))
        (check-picture (slide->pict (load-example "first-slide.rkt" 'welcome) #:theme theme)))))
  (define failures (run-tests base-tests))
  (when math?
    (set! failures (+ failures
      (run-tests (test-suite "manual math example"
        (test-case "replay the actual authored subtraction"
          (void (check-board "math-checkpoints.rkt" 9 '(2 3 4 5 6)))))))))
  (when geometry?
    (set! failures (+ failures
      (run-tests (test-suite "manual geometry example"
        (test-case "sample the actual equilateral construction"
          (void (check-board "geometry-slide.rkt" #f '(0 10.55)))))))))
  (exit (if (zero? failures) 0 1)))
