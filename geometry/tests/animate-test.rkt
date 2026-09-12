#lang racket/base

;; Native integration tests. These require the containing animate repository
;; and its installed dependencies, but no TeX formula construction or FFmpeg.
(require rackunit racket/list racket/file
         (prefix-in a: "../../main.rkt") (prefix-in color: "../../colors.rkt")
         (prefix-in output: "../../render.rkt")
         "../main.rkt" "../render.rkt" "../review-plan.rkt" "fixtures.rkt"
         (prefix-in eq: "../examples/equilateral-triangle.rkt")
         (prefix-in pb: "../examples/perpendicular-bisector.rkt")
         (prefix-in pp: "../examples/perpendicular-through-point.rkt")
         (prefix-in gal: "../examples/gallery.rkt"))
(define (maybe-child group id)
  (findf (lambda (v) (eq? (a:visual-id v) id)) (a:group-visual-children group)))
(define (child group id)
  (or (maybe-child group id)
      (error 'test "no child ~a in ~a" id (a:visual-id group))))
(construction compass-native-demo
  (given [A (point -2 0)] [B (point 0 0)] [O (point 2 1)])
  (initially (hide-label A B O))
  (step [AB (segment A B)])
  (step [c (circle O #:radius (length AB))]))
(module+ test
  (test-case "family variants become native unresolved palette tokens"
    (define style (resolve-geometry-style default-geometry-theme 'Circle 'deemphasized))
    (check-equal? (geometry-style-color style 'stroke) (color:palette-color 'aqua-c)))
  (test-case "procedural exact native colors pass through without RGB copying"
    (define t (geometry-theme-set default-geometry-theme 'point
                                  (list (list 'color (color:rgb-color 20 40 60)))))
    (check-equal? (geometry-style-color (resolve-geometry-style t 'Point 'normal) 'fill)
                  (color:rgb-color 20 40 60)))
  (test-case "conversion returns an ordinary native scene with a linear clock"
    (define timeline (construction->timeline triangle))
    (define scene (geometry-timeline->scene timeline #:id 'geometry-test))
    (check-true (a:scene? scene))
    (check-= (a:scene-duration scene) (geometry-timeline-duration timeline) 1e-8)
    (check-= (a:scene-value-at scene 'geometry-test/clock 2) 2 1e-8))
  (test-case "native arbitrary-time sampling is independent of frame order"
    (define scene (geometry-timeline->scene (construction->timeline perpendicular) #:id 'geometry-test))
    (define first (a:scene-visual-at scene 'geometry-test 4.25))
    (for ([time (in-list '(8 1 0 6.5 2))]) (a:scene-visual-at scene 'geometry-test time))
    (check-equal? first (a:scene-visual-at scene 'geometry-test 4.25)))
  (test-case "native stroke widths remain cosmetic semantic values"
    (define timeline (construction->timeline triangle))
    (define visual (geometry-timeline->visual timeline (geometry-timeline-duration timeline)))
    (define shape (child (child visual 'AB) 'AB/stroke-0))
    (check-equal? (a:visual-stroke-width shape) 2))
  (test-case "scene conversion rejects a mismatched output aspect"
    (define timeline (construction->timeline triangle))
    (check-exn exn:fail:geometry?
               (lambda () (geometry-timeline->scene timeline #:width 500 #:height 500))))
  (test-case "all distributed examples instantiate through their public API"
    (for ([make (in-list (list eq:make-demo-scene pb:make-demo-scene pp:make-demo-scene gal:make-demo-scene))])
      (check-true (a:scene? (make #:width 320 #:height 180)))))
  (test-case "full-frame rendering reuses identical static geometry frames"
    (define directory (make-temporary-file "geometry-static-frame-test-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define timeline
          (construction->timeline triangle
                                  #:opening-hold 0.5
                                  #:read-delay 0.5
                                  #:action-duration 0.1
                                  #:hold 0.5))
        (define report
          (render-geometry-frames/report! timeline directory #:width 320 #:height 180 #:fps 10))
        (check-equal? (length (output:render-diagnostics-paths report))
                      (output:render-diagnostics-frame-count report))
        (check-true
         (for/or ([milliseconds (in-list (output:render-diagnostics-frame-milliseconds report))])
           (zero? milliseconds))))
      (lambda () (delete-directory/files directory))))
  (test-case "native compass reveal adds a transient carrier and glow attention"
    (define timeline
      (construction->timeline compass-native-demo #:read-delay 0 #:action-duration 1 #:hold 0 #:opening-hold 0))
    (define plan (make-geometry-review-plan timeline))
    (define circle-row (cadr plan))
    (define source-attention
      (findf (lambda (sample) (eq? (geometry-review-sample-phase sample) 'source-attention))
             (geometry-review-step-samples circle-row)))
    (check-not-false source-attention)
    (define attention-frame
      (geometry-timeline->visual timeline (geometry-review-sample-time source-attention)))
    (define circle-attention (child attention-frame 'c))
    (check-not-false (maybe-child circle-attention 'c/compass-guide))
    (check-not-false (maybe-child circle-attention 'c/compass-attention))
    (define circle-event
      (findf (lambda (event)
               (ormap (lambda (action) (memq 'c (geometry-action-targets action)))
                      (geometry-event-actions event)))
             (geometry-timeline-events timeline)))
    (check-not-false circle-event)
    (define settled (geometry-timeline->visual timeline (geometry-event-end circle-event)))
    (define circle-settled (child settled 'c))
    (check-false (maybe-child circle-settled 'c/compass-guide))
    (check-false (maybe-child circle-settled 'c/compass-attention)))
  (test-case "native PNG output and narration metadata can be produced headlessly"
    (define directory (make-temporary-file "geometry-test-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define timeline (construction->timeline triangle #:action-duration 0.1 #:hold 0.1 #:opening-hold 0.1))
        (define paths (render-geometry-stills! timeline directory #:width 320 #:height 180 #:fps 10))
        (check-true (pair? paths))
        (check-equal? (subbytes (file->bytes (car paths)) 0 8) #"\211PNG\r\n\032\n")
        (check-true (file-exists? (build-path directory "narration.srt")))
        (check-true (file-exists? (build-path directory "stills.tsv"))))
      (lambda () (delete-directory/files directory)))))
