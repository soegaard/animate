#lang racket/base

;;;
;;; SCENE-CW Video-Authoring Workflow Tests
;;;

;; Named sections preserve the original scene's global sampling grid while
;; producing locally numbered output that can be encoded as an independent
;; clip. Cues and audio placement remain immutable metadata.

(require rackunit
         racket/file
         racket/path
         racket/runtime-path
         "../main.rkt"
         "../authoring.rkt"
         "../render.rkt")

(define-runtime-path authoring-sections-example
  "../examples/authoring-sections.rkt")

(module+ test
  ;; The timeline example's playhead encodes global time as horizontal position;
  ;; its line midpoint must not drift vertically as it reaches the conclusion.
  (define make-demo-scene
    (dynamic-require authoring-sections-example 'make-demo-scene))
  (define demo-scene (make-demo-scene))
  (check-equal?
   (vec2-y (visual-position (scene-visual-at demo-scene 'playhead 0)))
   1/4)
  (check-equal?
   (vec2-y (visual-position (scene-visual-at demo-scene 'playhead 7)))
   1/4)

  (define scene
    (scene-wait (make-scene) 6))

  (define timeline
    (make-authored-timeline
     scene
     #:sections
     (list (section 'intro 0 2)
           (section 'derivation 2 5)
           (section 'outro 5 6))
     #:cues
     (list (cue 'begin-derivation 2)
           (cue 'conclusion 5))
     #:audio-cues
     (list (audio-cue "narration.wav"
                      #:start 0
                      #:source-start 3/2
                      #:duration 5))))

  ;; Metadata retains the declared authoring order, whereas frame selection is
  ;; always derived from the full scene's global output grid.
  (check-equal? (timeline-section-names timeline)
                '(intro derivation outro))
  (check-equal? (timeline-section-frame-indices timeline 'intro #:fps 2)
                '(0 1 2 3))
  (check-equal? (timeline-section-frame-indices timeline 'derivation #:fps 2)
                '(4 5 6 7 8 9))
  (check-equal? (timeline-section-frame-count timeline 'outro #:fps 2)
                2)
  (check-equal?
   (map cue-name (timeline-section-cues timeline 'derivation))
   '(begin-derivation))
  (check-equal?
   (map cue-name (timeline-section-cues timeline 'outro))
   '(conclusion))

  (define exported-metadata
    (authored-timeline-metadata timeline))
  (check-true (immutable? exported-metadata))
  (check-equal? (hash-ref exported-metadata 'duration) 6)
  (check-equal?
   (hash-ref (car (hash-ref exported-metadata 'audio-cues)) 'source)
   "narration.wav")

  ;; Reject malformed or ambiguous authoring data before it reaches rendering.
  (check-exn exn:fail:contract?
             (lambda () (section 'bad 2 2)))
  (check-exn exn:fail:contract?
             (lambda () (cue 'bad +inf.0)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (make-authored-timeline
      scene
      #:sections (list (section 'same 0 1)
                       (section 'same 1 2)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (make-authored-timeline
      scene
      #:sections (list (section 'first 0 3)
                       (section 'second 2 4)))))
  (check-exn exn:fail:contract?
             (lambda () (timeline-section timeline 'missing)))
  (check-exn exn:fail:contract?
             (lambda ()
               (timeline-section-frame-indices timeline 'intro #:fps 0)))

  ;; Selected rendering takes frames 4 through 9 from the global scene but
  ;; writes a directly encodable local sequence 0 through 5. An explicit key
  ;; makes the following identical request a real cache hit.
  (define output-directory
    (make-temporary-file "animate-scene-cw-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define fresh
       (render-timeline-section/report!
        timeline 'derivation output-directory
        #:fps 2 #:workers 2 #:cache-key 'derivation-v1))
     (check-false (section-render-report-cache-hit? fresh))
     (check-equal? (section-render-report-source-frame-indices fresh)
                   '(4 5 6 7 8 9))
     (check-equal?
      (map (lambda (path)
             (path->string (file-name-from-path path)))
           (section-render-report-paths fresh))
      (list "frame-000000.png"
            "frame-000001.png"
            "frame-000002.png"
            "frame-000003.png"
            "frame-000004.png"
            "frame-000005.png"))
     (check-true (andmap file-exists?
                         (section-render-report-paths fresh)))
     (check-true (render-diagnostics?
                  (section-render-report-diagnostics fresh)))

     (define cached
       (render-timeline-section/report!
        timeline 'derivation output-directory
        #:fps 2 #:workers 2 #:cache-key 'derivation-v1))
     (check-true (section-render-report-cache-hit? cached))
     (check-false (section-render-report-diagnostics cached))
     (check-equal? (section-render-report-paths cached)
                   (section-render-report-paths fresh))

     (define invalidated
       (render-timeline-section/report!
        timeline 'derivation output-directory
        #:fps 2 #:workers 1 #:cache-key 'derivation-v2))
     (check-false (section-render-report-cache-hit? invalidated)))
   (lambda ()
     (delete-directory/files output-directory))))
