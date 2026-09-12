#lang racket/base

;; Native integration checks. These require the containing Animate checkout,
;; RackUnit and pict/draw; run-tests.rkt includes them in the normal full run.
(require rackunit racket/class racket/list racket/runtime-path
         (prefix-in a: "../../main.rkt") (prefix-in colors: "../../colors.rkt")
         "../main.rkt" "../private/drawing.rkt")
(define-runtime-path examples "../examples")
(define (build name mode)
  ((dynamic-require (build-path examples (string-append name ".rkt")) 'make-demo-timeline) #:theme-mode mode))
(define (child v id)
  (or (findf (lambda (c) (eq? (a:visual-id c) id)) (a:group-visual-children v))
      (error 'refinement-render "missing child ~a" id)))
(module+ test
  (for ([mode '(light dark)])
    (test-case (format "native square keeps support lines behind the gold base: ~a" mode)
      (define t (build "square-on-segment" mode))
      (define r (geometry-timeline-realization t))
      (define env (geometry-realization-values r))
      (define nodes (geometry-program-nodes (geometry-realization-program r)))
      (define support-ids
        (for/list ([n nodes]
                    #:when (let ([v (hash-ref env (geometry-node-id n))])
                             (and (line? v) (on (hash-ref env 'A) v) (on (hash-ref env 'B) v))))
          (geometry-node-id n)))
      (check-true (pair? support-ids))
      (define sampler (geometry-timeline->visual-sampler t #:width 640))
      (define relevant
        (filter (lambda (event)
                  (ormap (lambda (id) (presentation-shown? (hash-ref (geometry-event-after event) id))) support-ids))
                (geometry-timeline-events t)))
      (check-true (pair? relevant))
      (for ([event (list (first relevant) (list-ref relevant (quotient (length relevant) 2)) (last relevant))])
        (define time (/ (+ (geometry-event-start event) (geometry-event-end event)) 2))
        (define group (sampler time))
        (define ids (map a:visual-id (a:group-visual-children group)))
        (for ([id support-ids]) (check-true (< (index-of ids id) (index-of ids 'AB))))
        (check-equal? (a:visual-id (child (child group 'AB) 'AB/stroke-0)) 'AB/stroke-0)))
    (test-case (format "native measured division labels retain their near-point anchors: ~a" mode)
      (define t (build "divide-segment-five" mode))
      (define env (geometry-realization-values (geometry-timeline-realization t)))
      (define plan (geometry-timeline->annotation-plan t #:width 1280))
      (for ([id '(P1 P2 P3 P4 P5)])
        (check-= (distance (hash-ref (annotation-plan-labels plan) id)
                           (point+ (hash-ref env id) (point -0.54 -0.08))) 0 1e-8)))
    (test-case (format "native purple circumcircle and hexagon ending render: ~a" mode)
      (define t (build "regular-hexagon" mode))
      (define p (geometry-realization-program (geometry-timeline-realization t)))
      (define style (resolve-geometry-style (geometry-timeline-theme t) 'Circle 'normal
                                            (object-style-overrides p 'k)))
      (check-equal? (geometry-style-color style 'stroke)
                    (colors:palette-color (if (eq? mode 'light) 'purple-d 'purple-b)))
      (define scene (geometry-timeline->scene t #:width 640 #:height 360))
      (define image
        (a:scene-frame->bitmap scene (sub1 (a:scene-frame-count scene #:fps 1)) #:fps 1
          #:theme (if (eq? mode 'light) colors:animate-light-theme colors:animate-dark-theme)))
      (check-equal? (send image get-width) 640)
      (check-equal? (send image get-height) 360))))
