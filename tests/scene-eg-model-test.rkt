#lang racket/base

;; SCENE-EG-1: GUI-independent preview sample and cache-key model.

(require rackunit
         "../main.rkt"
         "../preview.rkt")

(module+ test
  (define spec
    ;; An empty renderer list is enough for model tests and proves that this
    ;; test module does not need the GUI or a bitmap renderer.
    (make-preview-render-spec #:fps 4 #:renderers '()))
  (define scene
    (scene-wait (make-scene) 5/2))
  (define document
    (make-preview-document scene #:generation 7 #:label 'model-test))

  ;; Output-frame identity is exact and separate from the final endpoint.
  (check-equal? (preview-document-frame-count document spec) 10)
  (check-true (preview-frame-sample-valid? document (frame-sample 0 4)))
  (check-true (preview-frame-sample-valid? document (frame-sample 5 4)))
  (check-true (preview-frame-sample-valid? document (frame-sample 9 4)))
  (check-false (preview-frame-sample-valid? document (frame-sample 10 4)))
  (check-equal? (preview-sample-time document (frame-sample 0 4)) 0)
  (check-equal? (preview-sample-time document (frame-sample 5 4)) 5/4)
  (check-equal? (preview-sample-time document (frame-sample 9 4)) 9/4)
  (check-equal? (preview-final-sample document) (time-sample 5/2))
  (check-equal? (preview-sample-time document (preview-final-sample document)) 5/2)

  ;; Seeking is intentionally clamping.  Static scenes retain a useful exact
  ;; endpoint even though they have no encoded output-frame identity.
  (check-equal? (preview-normalize-frame-sample document -10 spec)
                (frame-sample 0 4))
  (check-equal? (preview-normalize-frame-sample document 99 spec)
                (frame-sample 9 4))
  (check-equal? (preview-normalize-time-sample document -1)
                (time-sample 0))
  (check-equal? (preview-normalize-time-sample document 3)
                (time-sample 5/2))
  (check-exn exn:fail:contract?
             (lambda ()
               (preview-sample-time document (frame-sample 10 4))))

  (define static-document (make-preview-document (make-scene)))
  (check-equal? (preview-document-frame-count static-document spec) 0)
  (check-equal? (preview-normalize-frame-sample static-document 0 spec)
                (time-sample 0))

  ;; A nonintegral duration times FPS still has ordinary encoded frames, with
  ;; the precise endpoint available as a time sample.
  (define fractional-document
    (make-preview-document (scene-wait (make-scene) 5/4)))
  (define fps-2 (make-preview-render-spec #:fps 2 #:renderers '()))
  (check-equal? (preview-document-frame-count fractional-document fps-2) 3)
  (check-equal? (preview-sample-time fractional-document (frame-sample 2 2)) 1)
  (check-equal? (preview-sample-time fractional-document
                                      (preview-final-sample fractional-document))
                5/4)

  ;; Existing authored sections retain their global, half-open frame grid.
  (define timeline
    (make-authored-timeline
     scene
     #:sections (list (section 'middle 1 2))
     #:cues (list (cue 'middle-cue 3/2))))
  (define timeline-document (make-preview-document timeline))
  (check-equal? (preview-document-section-names timeline-document) '(middle))
  (check-equal? (preview-document-section-frame-indices timeline-document 'middle
                                                        (make-preview-render-spec
                                                         #:fps 2 #:renderers '()))
                '(2 3))
  (check-equal? (map cue-name (preview-document-section-cues timeline-document 'middle))
                '(middle-cue))

  ;; Cache identity includes both document and rendering generations as well as
  ;; the exact sample and render specification.
  (define frame (frame-sample 2 4))
  (define key-a (make-preview-frame-key document 3 frame spec))
  (define key-b (make-preview-frame-key document 3 frame spec))
  (define key-new-render (make-preview-frame-key document 4 frame spec))
  (define key-new-document
    (make-preview-frame-key (make-preview-document scene #:generation 8) 3 frame spec))
  (define other-spec (make-preview-render-spec #:fps 5 #:renderers '()))
  (check-equal? key-a key-b)
  (check-not-equal? key-a key-new-render)
  (check-not-equal? key-a key-new-document)
  (check-not-equal? key-a (make-preview-frame-key document 3 (frame-sample 2 5) other-spec)))
