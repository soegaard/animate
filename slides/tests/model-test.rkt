#lang racket/base
(require rackunit racket/list "../main.rkt" "../private/data.rkt" "helpers.rkt")
(provide tests)
(define tests
  (test-suite
   "immutable authoring and naming"
   (test-case "literal slot names do not capture lexical variables"
     (define s (let ([title "not a slot name"]) (slide #:layout 'title [title "Hello"])))
     (check-true (slide? s)) (check-equal? (slide-ref s 'title) "Hello"))
   (test-case "macro and procedural construction agree"
     (check-equal? (slide #:id 'a #:layout 'title [title #:key 'heading "Hello"])
                   (make-slide #:id 'a #:layout 'title
                               #:slots (hash 'title (slot-content "Hello" #:key 'heading)))))
   (test-case "mutable inputs are copied, including bullet pairs"
     (define text (string-copy "Hello"))
     (define table (make-hash (list (cons 'title text))))
     (define s (make-slide #:layout 'title #:slots table))
     (define bs (make-bullets (list (cons 'one text))))
     (string-set! text 0 #\J) (hash-set! table 'title "Other")
     (check-equal? (slide-ref s 'title) "Hello")
     (check-equal? (cdar (content-value-payload bs)) "Hello")
     (check-true (immutable? (slide-slots s))))
   (test-case "required, unknown, duplicate slots and continuity keys"
     (check-exn (code? 'missing-slot) (lambda () (slide #:layout 'title)))
     (check-exn (code? 'unknown-slot) (lambda () (slide #:layout 'title [title "T"] [typo "B"])))
     (check-exn (code? 'duplicate-name) (lambda () (slide #:layout 'title [title "A"] [title "B"])))
     (check-exn (code? 'duplicate-name)
                (lambda () (slide #:layout 'title [title #:key 'same "A"] [subtitle #:key 'same "B"]))))
   (test-case "immutable themes extend existing snapshots"
     (define extended (slide-theme #:id 'custom #:extends lecture-dark #:spacing (hash 'safe-x 1)))
     (check-equal? (slide-theme-colors extended) (slide-theme-colors lecture-dark))
     (check-equal? (hash-ref (slide-theme-spacing extended) 'safe-x) 1)
     (check-equal? (hash-ref (slide-theme-spacing lecture-dark) 'safe-x) 0.65))
   (test-case "format and action contracts"
     (check-exn exn:fail? (lambda () (slide-format #:id 'bad #:width +nan.0 #:height 9)))
     (check-exn exn:fail? (lambda () (beat 'bad #:duration -1)))
     (check-exn (code? 'beat-duration) (lambda () (beat 'untimed)))
     (check-exn (code? 'replacement-target) (lambda () (replace-content '(body item) "x")))
     (check-exn exn:fail? (lambda () (reveal-slot 'title #:effect 'invented))))
   (test-case "storyboard structure and occurrences"
     (define c (hold-slide (slide #:layout 'title [title "A"]) #:duration 1))
     (check-exn (code? 'storyboard-structure) (lambda () (storyboard (storyboard-cut))))
     (check-exn (code? 'duplicate-name) (lambda () (storyboard (storyboard-shot 'x c) (storyboard-shot 'x c))))
     (check-exn (code? 'storyboard-structure)
                (lambda () (storyboard (storyboard-shot 'x c) (storyboard-cut) (storyboard-cut) (storyboard-shot 'y c))))
     (check-exn (code? 'unknown-shot) (lambda () (storyboard-ref (storyboard (storyboard-shot 'x c)) 'missing))))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'model-test "failed")))
