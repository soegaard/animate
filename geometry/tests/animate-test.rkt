#lang racket/base

;; Native integration tests. These require the containing animate repository
;; and its installed dependencies, but no TeX formula construction or FFmpeg.
(require rackunit racket/list racket/file
         (prefix-in a: "../../main.rkt") (prefix-in color: "../../colors.rkt")
         "../main.rkt" "../render.rkt" "fixtures.rkt"
         (prefix-in eq: "../examples/equilateral-triangle.rkt")
         (prefix-in pb: "../examples/perpendicular-bisector.rkt")
         (prefix-in pp: "../examples/perpendicular-through-point.rkt"))
(define (child group id)
  (or (findf (lambda (v) (eq? (a:visual-id v) id)) (a:group-visual-children group))
      (error 'test "no child ~a in ~a" id (a:visual-id group))))
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
  (test-case "all three distributed examples instantiate through their public API"
    (for ([make (in-list (list eq:make-demo-scene pb:make-demo-scene pp:make-demo-scene))])
      (check-true (a:scene? (make #:width 320 #:height 180)))))
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
