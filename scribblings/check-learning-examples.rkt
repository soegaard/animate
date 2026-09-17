#lang racket/base
;; Each test checks the program printed in the Guide, not a parallel mock example.
(require (prefix-in ru: rackunit) (only-in rackunit/text-ui run-tests)
         racket/class racket/list (only-in pict pict->bitmap)
         animate
         (prefix-in o: "examples/objects-and-groups.rkt")
         (prefix-in t: "examples/timing-and-visibility.rkt")
         (prefix-in g: "examples/first-function-graph.rkt")
         "private/learning-catalog.rkt"
         racket/runtime-path)
(define-runtime-path examples "examples")
(define camera (make-camera #:width 320 #:height 180 #:world-width 14))
(define (position sc id time) (visual-position (scene-visual-at sc id time)))
(define (frame sc time)
  (define bm (pict->bitmap (scene-state->pict (scene-sample sc time) #:camera camera)))
  (define bytes (make-bytes (* 4 (send bm get-width) (send bm get-height))))
  (send bm get-argb-pixels 0 0 (send bm get-width) (send bm get-height) bytes)
  bytes)
(define tests
  (ru:test-suite
   "Reader-oriented manual examples"
   (ru:test-case "only the selected top-level object moves"
     (ru:check-equal? (position o:one-moves 'dot 2) (vec2 -1 2))
     (ru:check-equal? (position o:one-moves 'tile 2) (vec2 1 0))
     (ru:check-equal? (position o:separate 'dot 0) (vec2 -1 0)))
   (ru:test-case "a group counts as one top-level object"
     (ru:check-equal? (scene-state-count (scene-sample o:grouped 0)) 1)
     (ru:check-true (scene-state-has? (scene-sample o:grouped 0) '(pair dot))))
   (ru:test-case "parent movement preserves child local coordinates"
     (ru:check-equal? (position o:group-moves 'pair 2) (vec2 -1 0))
     (ru:check-equal? (position o:group-moves '(pair dot) 2) (vec2 -1 0)))
   (ru:test-case "child movement leaves the parent and sibling unchanged"
     (ru:check-equal? (position o:child-moves '(pair dot) 2) (vec2 -1 2))
     (ru:check-equal? (position o:child-moves '(pair tile) 2) (vec2 1 0))
     (ru:check-equal? (position o:child-moves 'pair 2) (vec2 1 0)))
   (ru:test-case "the parent transform produces the documented world point"
     (define parent (scene-ref o:child-moves 'pair))
     ;; This example has only translations: world = parent + local child.
     (ru:check-equal? (vec2+ (visual-position parent)
                             (position o:child-moves '(pair dot) 2))
                      (vec2 0 2)))
   (ru:test-case "parallel and sequential alternatives both last two seconds"
     (ru:check-equal? (scene-duration t:together) 2)
     (ru:check-equal? (scene-duration t:in-order) 2)
     (ru:check-equal? (position t:together 'dot 1) (vec2 0 1))
     (ru:check-equal? (position t:together 'tile 1) (vec2 0 -1))
     (ru:check-equal? (position t:in-order 'dot 1) (vec2 3 1))
     (ru:check-equal? (position t:in-order 'tile 1) (vec2 -3 -1)))
   (ru:test-case "a delayed request keeps the starting position until its start"
     (ru:check-equal? (scene-duration t:overlapping) 5/2)
     (ru:check-equal? (position t:overlapping 'tile 1/4) (vec2 -3 -1))
     (ru:check-equal? (position t:overlapping 'dot 2) (vec2 3 1))
     (ru:check-equal? (position t:overlapping 'tile 5/2) (vec2 3 -1)))
   (ru:test-case "smooth changes interior motion but preserves duration and endpoints"
     (ru:check-equal? (scene-duration t:eased) 2)
     (ru:check-equal? (scene-sample t:eased 0) (scene-sample t:together 0))
     (ru:check-equal? (position t:eased 'dot 2) (vec2 3 1))
     (ru:check-not-equal? (position t:eased 'dot 1/2)
                         (position t:together 'dot 1/2)))
   (ru:test-case "fading to zero keeps the object; fading out removes it"
     (ru:check-true (scene-state-has? (scene-sample t:invisible 1) 'dot))
     (ru:check-equal? (visual-opacity (scene-ref t:invisible 'dot)) 0)
     (ru:check-false (scene-state-has? (scene-sample t:removed 1) 'dot))
     (ru:check-equal? (frame t:invisible 1) (frame t:removed 1)))
   (ru:test-case "restoration uses the correct lifecycle operation"
     (for ([sc (in-list (list t:visible-again t:reintroduced))])
       (ru:check-equal? (scene-duration sc) 2)
       (ru:check-equal? (scene-ref sc 'dot) t:dot)))
   (ru:test-case "duplicate introduction and missing target fail"
     (ru:check-exn exn:fail?
                   (lambda () (scene-play t:invisible (fade-in t:dot) #:duration 1)))
     (ru:check-exn exn:fail?
                   (lambda () (scene-play t:removed (fade-to 'dot 1) #:duration 1))))
   (ru:test-case "graph drawing ends in the original curve and holds it"
     (ru:check-equal? (scene-duration g:drawing) 2)
     (ru:check-equal? (scene-duration g:film) 3)
     (ru:check-equal? (scene-ref g:drawing 'curve) g:curve)
     (ru:check-equal? (frame g:film 2) (frame g:film 3)))
   (ru:test-case "the graph and axes remain a single movable diagram"
     (ru:check-equal? (scene-state-count (scene-sample g:moving-diagram 2)) 1)
     (ru:check-equal? (position g:moving-diagram 'diagram 2) (vec2 2 0))
     (ru:check-equal? (scene-visual-at g:moving-diagram '(diagram curve) 2) g:curve))
   (ru:test-case "every illustration recipe is valid and repeatable in reverse order"
     (for ([recipe (in-list learning-frame-recipes)])
       (define sc (dynamic-require (build-path examples (list-ref recipe 1))
                                   (list-ref recipe 2)))
       (define times (list-ref recipe 3))
       (ru:check-not-false (member (length times) '(3 5)))
       (for ([time (in-list times)])
         (ru:check-true (<= 0 time (scene-duration sc))))
       (define forward (map (lambda (time) (frame sc time)) times))
       (ru:check-equal? (map (lambda (time) (frame sc time)) (reverse times))
                       (reverse forward))))))
(module+ main (exit (if (zero? (run-tests tests)) 0 1)))
(module+ test
  (unless (zero? (run-tests tests)) (error 'manual-examples "example tests failed")))
