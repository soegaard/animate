#lang racket/base
(require rackunit rackunit/text-ui racket/list
         "../examples/private/differentiation-model.rkt"
         "../examples/private/differentiation-script.rkt")
(define (end id) (state-at-shot-end id))
(define tests
  (test-suite
   "Differentiation slides: mathematics and manuscript"
   (test-case "unique ordered beats"
     (check-equal? (length script) (length (remove-duplicates (map shot-id script)))))
   (test-case "full theorem precedes split screen"
     (check-true (> theorem-duration 0))
     (check-true (> transition-duration 0))
     (check-eq? (shot-panel (car script)) 'theorem)
     (check-equal? film-duration (+ theorem-duration transition-duration script-duration)))
   (test-case "the model is x squared"
     (for ([x (in-list '(-3 -2 -1 -1/2 0 1/2 1 2 3))])
       (check-equal? (sample-function x) (* x x))))
   (test-case "same semantic points and exact increments"
     (for* ([x (in-list '(-2 -1 0 1 2))] [h (in-list '(1 1/2 1/100))])
       (define m (mathematical-state x h))
       (check-equal? (hash-ref m 'P) (cons x (* x x)))
       (check-equal? (hash-ref m 'Q) (cons (+ x h) (* (+ x h) (+ x h))))
       (check-equal? (hash-ref m 'dx) h)
       (check-equal? (hash-ref m 'dy) (+ (* h h) (* 2 x h)))))
   (test-case "difference quotient agrees with the original algebra"
     (for* ([x (in-list '(-2 -1 0 1 2))] [h (in-list '(1 1/2 1/100))])
       (check-equal? (hash-ref (mathematical-state x h) 'm) (+ h (* 2 x)))))
   (test-case "first circular zoom is centered at x0=1"
     (check-equal? (hash-ref (end 'hold-foerste) 'x0) 1)
     (check-equal? (hash-ref (end 'hold-foerste) 'zoom) 40)
     (check-equal? (hash-ref (end 'hold-foerste) 'lens) 1))
   (test-case "second circular zoom is centered at x0=2"
     (check-equal? (hash-ref (end 'hold-andet) 'x0) 2)
     (check-equal? (hash-ref (end 'hold-andet) 'zoom) 40)
     (check-equal? (hash-ref (end 'hold-andet) 'lens) 1))
   (test-case "the graph is inspected before the tangent overlay"
     (check-equal? (hash-ref (end 'hold-foerste) 'tangent) 0)
     (check-equal? (hash-ref (end 'hold-andet) 'tangent) 0)
     (check-equal? (hash-ref (end 'tangent-i-lup) 'tangent) 1))
   (test-case "zoom out before choosing another point"
     (check-equal? (hash-ref (end 'fjern-lup-foerste) 'zoom) 1)
     (check-equal? (hash-ref (end 'fjern-lup-foerste) 'lens) 0)
     (check-equal? (hash-ref (end 'andet-punkt) 'lens) 0))
   (test-case "original tangent examples have slopes 2 and 4"
     (check-equal? (hash-ref (mathematical-state 1 1) 'tangent-slope) 2)
     (check-equal? (hash-ref (mathematical-state 2 1) 'tangent-slope) 4))
   (test-case "original three-step order is retained"
     (for ([a (in-list '(tretrinsreglen dy-definition dy-kvadrat dq-definition dq-del-broek dq-forkort graense-regn))]
           [b (in-list '(dy-definition dy-kvadrat dq-definition dq-del-broek dq-forkort graense-regn bevis-tangent))])
       (check-true (< (hash-ref shot-offsets a) (hash-ref shot-offsets b)))))
   (test-case "x0 stays fixed through the calculation"
     (for ([id (in-list '(nabopunkt tilvaekster dy-definition dy-indsaet dy-kvadrat
                                  dy-forkort dq-definition dq-del-broek dq-forkort
                                  graense-start graense-approach graense-regn bevis-tangent))])
       (check-equal? (hash-ref (end id) 'x0) 1)))
   (test-case "finite animation never evaluates h=0"
     (for ([i (in-range 601)])
       (check-true (> (hash-ref (state-at (* script-duration (/ i 600))) 'h) 0)))
     (check-equal? (hash-ref (end 'graense-approach) 'h) 1/100)
     (check-equal? (hash-ref (mathematical-state 1 1/100) 'm) 201/100))
   (test-case "sampling is independent of the order of frames"
     (define times (for/list ([i (in-range 101)]) (* script-duration (/ i 100))))
     (check-equal? (map state-at times) (reverse (map state-at (reverse times)))))
   (test-case "exact tangent is a separate final object"
     (define last-state (state-at script-duration))
     (check-equal? (hash-ref last-state 'tangent) 1)
     (check-equal? (hash-ref last-state 'secant) 0)
     (check-equal? (hash-ref last-state 'neighbour) 0)
     (check-equal? (hash-ref last-state 'h) 1/100))
   (test-case "invalid times are rejected"
     (check-exn exn:fail:contract? (lambda () (state-at -1)))
     (check-exn exn:fail:contract? (lambda () (state-at (+ script-duration 1)))))))
(module+ test (define failures (run-tests tests)) (unless (zero? failures) (exit 1)))
