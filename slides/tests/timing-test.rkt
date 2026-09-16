#lang racket/base
(require rackunit racket/list "../main.rkt" "../render.rkt"
         "../private/data.rkt" "../private/sample.rkt" "helpers.rkt")
(provide tests)
(define base (slide #:layout 'title+body [title "A"] [body (bullets [one "First"] [two "Second"])]))
(define tests
  (test-suite
   "deterministic beats, replacements, and transitions"
   (test-case "named bullets fade independently without reflow"
     (define p (prepare-slide! (build-slide base #:initial 'hidden
                                (beat 'intro #:duration 2 (reveal-slot '(body two) #:at 1 #:duration 1)))))
     (define a (sample-slide p 1.5))
     (check-= (frame-leaf-opacity (find-leaf a '(body two))) 0.5 1e-8)
     (check-equal? (frame-leaf-opacity (find-leaf a '(body one))) 0)
     (check-equal? (frame-value-slots (sample-slide p 0)) (frame-value-slots (sample-slide p 'end)))
     (check-equal? (sample-signature (sample-slide p 2)) (sample-signature (sample-slide p '(intro end)))))
   (test-case "repeated, backward, and shuffled seeking agree"
     (define p (prepare-slide! (build-slide base #:initial '(title)
                                (beat 'body #:duration 2 (reveal-slot 'body #:duration 1))
                                (beat 'pulse #:duration 1 (emphasize-slot '(body one) #:duration 1)))))
     (define times '(0 1/4 1/2 1 3/2 2 5/2 3))
     (define expected (for/hash ([t (in-list times)]) (values t (sample-signature (sample-slide p t)))))
     (for ([t (in-list '(3 0 5/2 1/4 2 1 3/2 1/2 0 3))])
       (check-equal? (sample-signature (sample-slide p t)) (hash-ref expected t))))
   (test-case "persistent hide and reduced motion retain duration"
     (define c (build-slide base (beat 'out #:duration 2 (conceal-slot 'body #:duration 1))))
     (define p (prepare-slide! c))
     (check-equal? (frame-leaf-opacity (find-leaf (sample-slide p 2) '(body one))) 0)
     (define reduced (prepare-slide! (build-slide base #:motion 'reduced
                                      (beat 'emphasis #:duration 2 (emphasize-slot 'body #:duration 2)))))
     (check-equal? (prepared-duration reduced) 2)
     (check-equal? (frame-leaf-scale (find-leaf (sample-slide reduced 1) '(body one))) 1))
   (test-case "replacement alternatives have a stable envelope"
     (define c (build-slide (slide #:layout 'title+body [title "Old"] [body "Body"])
                 (beat 'replace #:duration 2 (replace-content 'title "A new title" #:duration 1))))
     (define p (prepare-slide! c))
     (check-equal? (frame-value-slots (sample-slide p 0)) (frame-value-slots (sample-slide p 2)))
     (define title-leaves (filter (lambda (l) (equal? '(title) (frame-leaf-path l)))
                                  (frame-value-leaves (sample-slide p 1/2))))
     (check-equal? (length title-leaves) 2)
     (for ([l (in-list title-leaves)]) (check-= (frame-leaf-opacity l) 1/2 1e-8))
     (check-equal? (length (filter (lambda (l) (equal? '(title) (frame-leaf-path l)))
                                  (frame-value-leaves (sample-slide p 1)))) 1))
   (test-case "property conflicts, unknown selectors, and overruns"
     (check-exn (code? 'action-conflict)
       (lambda () (prepare-slide! (build-slide base (beat 'conflict #:duration 2
                    (reveal-slot 'body #:duration 1) (conceal-slot '(body one) #:duration 1))))))
     (check-exn (code? 'unknown-selector)
       (lambda () (prepare-slide! (build-slide base (beat 'bad #:duration 1 (reveal-slot 'missing))))))
     (check-exn (code? 'beat-overrun)
       (lambda () (prepare-slide! (build-slide base (beat 'too-short #:duration 1 (reveal-slot 'body #:duration 2)))))))
   (test-case "draft narration drives duration and reserves subtitles"
     (define clip (build-slide base (beat 'spoken #:narration (narration "A sentence" #:draft-duration 3)
                                         #:tail-hold 1/2 (reveal-slot 'body #:duration 1))))
     (define board (prepare-storyboard! (storyboard (storyboard-shot 's clip))))
     (check-= (prepared-duration board) 3.5 1e-8)
     (check-true (> (prepared-slide-value-subtitle-height (prepared-clip-value-slide (storyboard-ref board 's))) 0))
     (check-exn (code? 'beat-overrun)
       (lambda () (prepare-slide! (build-slide base (beat 'spoken #:duration 2
                          #:narration (narration "Too long" #:draft-duration 3)))))))
   (test-case "bridge duration is additional, with exact frozen endpoints"
     (define c (hold-slide (slide #:layout 'title [title #:key 'heading "Same"]) #:duration 2))
     (define b (prepare-storyboard! (storyboard (storyboard-shot 'a c)
                        (slide-transition #:effect 'match #:keys '(heading) #:duration 1)
                        (storyboard-shot 'b c))))
     (check-equal? (prepared-duration b) 5)
     (check-equal? (length (filter (lambda (l) (> (frame-leaf-opacity l) 0))
                                  (frame-value-leaves (sample-storyboard b 5/2)))) 1)
     (check-equal? (sample-signature (sample-storyboard b 2))
                   (sample-signature (prefix-frame (sample-slide (storyboard-ref b 'a) 'end) 'a)))
     (check-equal? (sample-signature (sample-storyboard b 3))
                   (sample-signature (prefix-frame (sample-slide (storyboard-ref b 'b) 'start) 'b))))
   (test-case "missing or hidden continuity keys are errors"
     (define s (slide #:layout 'title [title #:key 'heading "T"]))
     (define a (hold-slide s #:duration 1))
     (define b (build-slide s #:initial 'hidden (beat 'pause #:duration 1)))
     (check-exn (code? 'invisible-match)
       (lambda () (prepare-storyboard! (storyboard (storyboard-shot 'a a)
          (slide-transition #:effect 'match #:keys '(heading)) (storyboard-shot 'b b)))))
     (check-exn (code? 'missing-continuity-key)
       (lambda () (prepare-storyboard! (storyboard (storyboard-shot 'a a)
          (slide-transition #:effect 'match #:keys '(unknown)) (storyboard-shot 'b a))))))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'timing-test "failed")))
