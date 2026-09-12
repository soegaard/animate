#lang racket/base

;; Native integration: no substitute renderer. Requires the containing Animate
;; checkout and its ordinary pict/draw/font dependencies.
(require rackunit racket/list racket/class racket/file
         (prefix-in a: "../../main.rkt") (prefix-in colors: "../../colors.rkt")
         "../main.rkt" "../review-plan.rkt"
         (prefix-in t: "../examples/transformations.rkt")
         (prefix-in l: "../examples/semantic-labels.rkt")
         (prefix-in g: "../examples/gallery.rkt"))
(define (child group id)
  (or (findf (lambda (v) (eq? (a:visual-id v) id)) (a:group-visual-children group))
      (error 'transform-label-render "missing visual ~a" id)))
(module+ test
  (for* ([mode '(light dark)] [factory (list t:make-demo-timeline l:make-demo-timeline g:make-demo-timeline)])
    (test-case (format "native label metrics and random access: ~a / ~a" factory mode)
      (define t (factory #:theme-mode mode))
      (define plan (geometry-timeline->annotation-plan t #:width 640))
      (check-equal? (annotation-plan-metrics plan) 'animate-text)
      (define sampler (geometry-timeline->visual-sampler t #:width 640))
      (define before (sampler (geometry-timeline-duration t)))
      (sampler 0)
      (for ([sample (geometry-review-samples (make-geometry-review-plan t))])
        (sampler (geometry-review-sample-frame sample)))
      (check-equal? before (sampler (geometry-timeline-duration t)))))
  (test-case "point, segment, length and angle labels have native text children"
    (define t (l:make-demo-timeline))
    (define v (geometry-timeline->visual t (geometry-timeline-duration t) #:width 640))
    (for ([id '(apex base-length side-a side-b alpha beta)])
      (define label (child (child v id) (string->symbol (format "~a/label" id))))
      (check-equal? (a:visual-id label) (string->symbol (format "~a/label" id))))
    (check-equal? (a:visual-id (child (child v 'alpha) 'alpha/marker)) 'alpha/marker))
  (for ([mode '(light dark)])
    (test-case (format "native PNG with settled semantic labels / ~a" mode)
      (define t (l:make-demo-timeline #:theme-mode mode))
      (define scene (geometry-timeline->scene t #:width 640 #:height 360))
      (define bitmap
        (a:scene-frame->bitmap scene (sub1 (a:scene-frame-count scene #:fps 10)) #:fps 10
          #:theme (if (eq? mode 'dark) colors:animate-dark-theme colors:animate-light-theme)))
      (check-equal? (send bitmap get-width) 640)
      (check-equal? (send bitmap get-height) 360)
      (define path (make-temporary-file "geometry-labels-~a.png"))
      (dynamic-wind void
        (lambda ()
          (check-true (send bitmap save-file path 'png))
          (check-equal? (subbytes (file->bytes path) 0 8) #"\211PNG\r\n\032\n"))
        (lambda () (delete-file path))))))
