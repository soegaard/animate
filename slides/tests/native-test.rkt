#lang racket/base
;; These ordinary imports are themselves the no-prefix regression test.
(require (only-in rackunit
                  test-suite test-case
                  check-true check-equal? check-not-equal? check-= check-exn)
         racket/list
         "../../main.rkt" "../../authoring.rkt" "../../project.rkt"
         "../../math/main.rkt" "../../typography.rkt" "../../colors.rkt"
         "../main.rkt" "../gallery.rkt" "../scene.rkt" "../pict.rkt" "../render.rkt" "../math.rkt" "../project.rkt"
         (only-in pict pict? pict-width pict-height)
         "../private/data.rkt" "../private/sample.rkt" "helpers.rkt")
(provide tests)
(define tests
  (test-suite
   "ordinary native Scene integration"
   (test-case "static Scene and Pict share type, dimensions, and pixels"
     (define p (prepare-slide! (slide #:layout 'title [title "Hello"] [subtitle "Both outputs"]) #:theme lecture-dark))
     (define s (slide->scene p #:size '(640 360)))
     (check-true (scene? s)) (check-equal? (scene-duration s) 0)
     (define native (scene-state->pict (scene-sample s 0) #:camera (scene-camera-at s 0)))
     (define picture (slide->pict p #:size '(640 360)))
     (check-true (pict? native))
     (check-equal? (list (pict-width native) (pict-height native)) '(640 360))
     ;; Same vector composition can round edge pixels differently. Keep a
     ;; small channel tolerance, not a claim of universal byte identity.
     (check-true (<= (max-pixel-difference (pixel-bytes native) (pixel-bytes picture)) 12)))
   (test-case "exact storyboard cuts agree between Pict and native Scene"
     (define opening
       (hold-slide
        (slide #:layout 'title
          [title "A function is a rule"]
          [subtitle "Opening card"])
        #:duration 3))
     (define next
       (build-slide
        (slide #:layout 'title+body [title "Next shot"] [body "Body"])
        #:initial '(title)
        (beat 'hold #:duration 2)))
     (define board
       (prepare-storyboard!
        (storyboard
         (storyboard-shot 'opening opening)
         (storyboard-cut)
         (storyboard-shot 'next next))))
     ;; Direct near-boundary Pict queries retain literal time semantics.
     (check-not-equal?
      (sample-signature (sample-storyboard board (- 3 1e-12)))
      (sample-signature (sample-storyboard board 3)))
     ;; The Scene's interpolated clock is canonicalized only at authored
     ;; boundaries, so the exact cut renders the same destination frame.
     (define scn (storyboard->scene board #:size '(640 360)))
     (define direct (storyboard->pict board #:at 3 #:size '(640 360)))
     (define native
       (scene-state->pict (scene-sample scn 3) #:camera (scene-camera-at scn 3)))
     (check-true
      (<= (max-pixel-difference (pixel-bytes direct) (pixel-bytes native)) 12)))
   (test-case "a slot has its own anchor and supports appended native animation"
     (define c (build-slide (slide #:layout 'title+body [title "T"] [body "B"])
                 (beat 'hold #:duration 1)))
     (define s (slide->scene c))
     (check-true (visual? (scene-slot-ref s 'title)))
     (check-true (> (vec2-y (visual-position (scene-slot-ref s 'title))) 0))
     (define extended (scene-play s (fade-to (scene-slot-id 'title) 0) #:duration 1 #:easing linear))
     (check-= (visual-opacity (scene-slot-ref extended 'title #:at 3/2)) 1/2 1e-8)
     (check-equal? (visual-opacity (scene-slot-ref extended 'title)) 0))
   (test-case "slot identity cannot collide with renderer-owned roots"
     (check-not-equal? (scene-slot-id '$slides-clock) '$slides-clock)
     (check-not-equal? (scene-slot-id '(a/b c)) (scene-slot-id '(a b/c)))
     (check-not-equal? (scene-slot-id '(a title)) (scene-slot-id '(b title))))
   (test-case "embedded native animation pauses, then advances"
     (define inner (scene-play (scene-add (make-scene)
                                (circle #:id 'disc #:radius 1 #:fill "blue"))
                              (move-to 'disc (vec2 2 0)) #:duration 2 #:easing linear))
     (define p (prepare-slide! (build-slide (slide #:layout 'figure-full [figure (scene-content inner)])
                                  (beat 'pause #:duration 1)
                                  (beat 'move #:duration 2 (play-content 'figure)))))
     (check-equal? (frame-leaf-time (find-leaf (sample-slide p 1/2) '(figure))) 0)
     (check-= (frame-leaf-time (find-leaf (sample-slide p 2) '(figure))) 1 1e-8)
     (check-equal? (frame-leaf-time (find-leaf (sample-slide p 3) '(figure))) 2)
     (define s (slide->scene p))
     (check-true (pict? (scene-state->pict (scene-sample s 2) #:camera (scene-camera-at s 2)))))
   (test-case "embedded native endpoints tolerate exact/inexact clock agreement"
     (define inner
       (scene-wait
        (scene-add (make-scene)
                   (circle #:id 'endpoint-disc #:radius 1 #:fill "blue"))
        67/10))
     ;; The parent beat uses an inexact spelling of the exact child duration.
     ;; Endpoint rendering must canonicalize that infinitesimal numeric mismatch
     ;; before calling the child's closed-interval Scene sampler.
     (define p
       (prepare-slide!
        (build-slide
         (slide #:layout 'figure-full [figure (scene-content inner)])
         (beat 'play
           #:narration (narration "Reach the endpoint." #:draft-duration 6.7)
           (play-content 'figure)))))
     (define leaf (find-leaf (sample-slide p 'end) '(figure)))
     (check-= (frame-leaf-time leaf) 67/10 1e-8)
     (check-true (scene? (slide->scene p))))
   (test-case "math descriptors do not typeset on construction"
     (define problem (math '(= (+ x 1) 2) #:id 'small #:context (math-context #:real '(x))))
     (define plan (present (derive problem [subtract (both-sides 'subtract 1)])))
     (define s (slide #:layout 'figure-full [figure (math-content plan)]))
     (check-true (slide? s))
     (check-exn (code? 'preparation-required) (lambda () (slide->pict s))))
   (test-case "narration becomes authored timeline metadata"
     (define c (build-slide (slide #:layout 'title [title "T"])
                 (beat 'say #:narration (narration "Draft sentence" #:draft-duration 2) #:tail-hold 1)))
     (define timeline (storyboard->timeline (storyboard (storyboard-shot 'opening c))))
     (check-true (authored-timeline? timeline))
     (check-equal? (scene-duration (authored-timeline-scene timeline)) 3)
     (check-equal? (length (authored-timeline-audio-cues timeline)) 0)
     (check-equal? (map subtitle-cue-text (authored-timeline-subtitles timeline)) '("Draft sentence"))
     (check-equal? (map authoring-section-name (authored-timeline-sections timeline)) '(opening)))))
(module+ test (require (only-in rackunit/text-ui run-tests)) (unless (zero? (run-tests tests)) (error 'native-test "failed")))
