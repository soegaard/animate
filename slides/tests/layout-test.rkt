#lang racket/base
(require rackunit racket/list
         (only-in pict blank pict-width pict-height)
         "../main.rkt" "../pict.rkt" "../render.rkt"
         "../private/data.rkt" "../private/sample.rkt" "helpers.rkt")
(provide tests)
(define (specimen name)
  (make-slide #:id name #:layout name
    #:slots (for/hash ([s (in-list (layout-slots (layout-ref name)))])
              (values (slot-spec-name s)
                      (if (eq? (slot-spec-name s) 'figure)
                          (pict-content (blank 160 100))
                          (symbol->string (slot-spec-name s)))))))
(define tests
  (test-suite
   "layout, typography, and shared output geometry"
   (test-case "twelve built-ins, two themes, four formats"
     (check-equal? (length (layout-names)) 12)
     (for* ([name (in-list (layout-names))] [theme (in-list (list lecture-light lecture-dark))]
            [fmt (in-list (list widescreen standard portrait square-format))])
       (define p (prepare-slide! (specimen name) #:theme theme #:format fmt))
       (check-true (prepared-slide? p) (format "~a ~a" name (slide-format-id fmt)))
       (define pic (slide->pict p))
       (check-equal? (pict-width pic) (* 80 (slide-format-width fmt)))
       (check-equal? (pict-height pic) (* 80 (slide-format-height fmt)))))
   (test-case "portrait two-column text stacks compactly"
     (define p
       (prepare-slide!
        (slide #:layout 'title+two-column
          [title "Compare"]
          [left (bullets [a "First"] [b "Second"])]
          [right (bullets [c "Third"] [d "Fourth"])])
        #:format portrait))
     (define slots (frame-value-slots (sample-slide p)))
     (define left (hash-ref slots '(left)))
     (define right (hash-ref slots '(right)))
     (check-= (- (box-value-y right)
                 (+ (box-value-y left) (box-value-height left)))
              (theme-spacing lecture-light 'section-gap)
              1e-8)
     ;; The compact stack deliberately leaves unused space below short text.
     (check-true (< (+ (box-value-y right) (box-value-height right))
                    (+ (box-value-y (frame-value-safe-box (sample-slide p)))
                       (box-value-height (frame-value-safe-box (sample-slide p)))))))
   (test-case "equation-focus keeps annotation with the equation"
     (define p
       (prepare-slide!
        (slide #:layout 'equation-focus
          [equation "3x + 5 = 17"]
          [annotation "Which value makes this true?"])))
     (define frame (sample-slide p))
     (define slots (frame-value-slots frame))
     (define equation (hash-ref slots '(equation)))
     (define annotation (hash-ref slots '(annotation)))
     (check-= (- (box-value-y annotation)
                 (+ (box-value-y equation) (box-value-height equation)))
              (theme-spacing lecture-light 'section-gap)
              1e-8)
     (define safe (frame-value-safe-box frame))
     (define block-top (box-value-y equation))
     (define block-bottom (+ (box-value-y annotation) (box-value-height annotation)))
     (check-= (/ (+ block-top block-bottom) 2)
              (+ (box-value-y safe) (/ (box-value-height safe) 2))
              1e-8))
   (test-case "output pixels do not change wrapping or layout"
     (define p (prepare-slide! (slide #:layout 'title+body [title "A title"]
                                     [body "A paragraph with words that retain their measured layout."])))
     (define before (sample-signature (sample-slide p)))
     (slide->pict p #:size '(640 360)) (slide->pict p #:size '(1920 1080))
     (check-equal? before (sample-signature (sample-slide p)))
     (check-exn (code? 'output-aspect) (lambda () (slide->pict p #:size '(600 600))))
     (check-equal? (pict-width (slide->pict p #:size '(600 600) #:fit 'letterbox)) 600))
   (test-case "prepared context is frozen"
     (define p (prepare-slide! (slide #:layout 'title [title "A"]) #:theme lecture-dark))
     (check-exn (code? 'frozen-context) (lambda () (slide->pict p #:theme lecture-light)))
     (check-exn (code? 'frozen-context) (lambda () (slide->pict p #:format portrait))))
   (test-case "natural text overflow is diagnosed"
     (define s (slide #:layout 'title+body [title "T"] [body (make-string 800 #\W)]))
     (check-exn (code? 'content-overflow) (lambda () (prepare-slide! s))))
   (test-case "custom box layout with explicit portrait variant"
     (define l
       (layout #:id 'custom #:slots (list (slot-spec 'heading #:required? #t #:role 'title)
                                          (slot-spec 'left #:required? #t) (slot-spec 'right #:required? #t))
         #:arrange (vbox (region 'heading #:basis 'content)
                         (hbox #:grow 1 (region 'left #:grow 1) (region 'right #:grow 2)))
         #:portrait (vbox (region 'heading #:basis 'content)
                          (region 'left #:grow 1) (region 'right #:grow 1))))
     (define s (slide #:layout l [heading "Heading"] [left "L"] [right "R"]))
     (define w (sample-slide (prepare-slide! s)))
     (define h (frame-value-slots w))
     (check-= (box-value-width (hash-ref h '(right))) (* 2 (box-value-width (hash-ref h '(left)))) 1e-8)
     (define tall (frame-value-slots (sample-slide (prepare-slide! s #:format portrait))))
     (check-true (> (box-value-y (hash-ref tall '(right))) (box-value-y (hash-ref tall '(left))))))
   (test-case "cropping is explicit"
     (define p (prepare-slide! (slide #:layout 'figure-full [figure (pict-content (blank 300 50) #:fit 'cover)])))
     (check-not-false (frame-leaf-clip (car (frame-value-leaves (sample-slide p))))))
   (test-case "custom layout errors are deterministic"
     (check-exn (code? 'layout-regions)
       (lambda () (layout #:id 'bad #:slots (list (slot-spec 'a)) #:arrange (region 'b))))
     (define l (layout #:id 'too-large #:slots (list (slot-spec 'a)) #:arrange (vbox (region 'a #:basis 100))))
     (check-exn (code? 'unsatisfiable-layout) (lambda () (prepare-slide! (slide #:layout l [a "A"])))))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'layout-test "failed")))
