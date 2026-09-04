#lang racket/base

;; SCENE-EH-6: a source-program attachment installs only compiled immutable
;; scenes into the generic preview actor. Block navigation and reload stay
;; distinct from ordinary authored-timeline navigation.

(require rackunit
         racket/file
         "../main.rkt"
         "../authoring.rkt"
         "../preview.rkt")

(define (write-program! path second-duration)
  (call-with-output-file
   path #:exists 'truncate/replace
   (lambda (out)
     (display "#lang racket/base\n(require animate animate/authoring)\n" out)
     (display "(define-scene-program preview-program #:initial (make-scene)\n" out)
     (display "  (scene-block first (scene) (scene-wait scene 1))\n" out)
     (fprintf out "  (scene-block second (scene) (scene-wait scene ~a)))~n"
              second-duration)
     (display "(provide preview-program)\n" out))))

(module+ test
  (define temporary-directory (simplify-path (build-path (current-directory) ".." "tmp")))
  (make-directory* temporary-directory)
  (define source-path
    (make-temporary-file "scene-eh-preview-~a.rkt" #f temporary-directory))
  (dynamic-wind
    void
    (lambda ()
      (write-program! source-path 2)
      (define session
        (open-program-preview-controller
         source-path 'preview-program #:fps 2 #:prefetch 0
         #:producer (lambda (document sample _spec)
                      (list (preview-document-generation document) sample))
         #:byte-size (lambda (_value) 1)))
      (check-true (program-preview-session? session))
      (check-equal? (preview-program-generation session) 0)
      (check-equal? (map scene-block-spec-id (preview-program-blocks session))
                    '(first second))
      (void (preview-jump-to-block! session 'second))
      (check-equal? (preview-current-time session) 1)
      (check-equal? (preview-current-block session) 'second)
      ;; Inspector selections map conservatively to their current source
      ;; block.  An editor integration receives the recorded source location;
      ;; no GUI or editor process is needed for this headless assertion.
      (define second-location (preview-current-block-source-location session))
      (check-true (source-location? second-location))
      (check-equal? (source-location-source second-location) source-path)
      (void (preview-select! session '(diagram dot)))
      (check-equal? (preview-selection-source-location session) second-location)
      (define opened #f)
      (check-equal?
       (preview-open-selection-source!
        session #:open (lambda (location) (set! opened location) 'opened))
       'opened)
      (check-equal? opened second-location)

      ;; Restoring a block input is explicitly a manual scratch branch; it does
      ;; not pretend that the full source program has been recompiled.
      (void (preview-restore-block-input! session 'second))
      (check-equal? (preview-program-branch-mode session)
                    'manual-checkpoint-branch)
      (check-equal? (scene-duration (preview-source session)) 1)
      (void (preview-reset-to-source! session))
      (check-equal? (preview-program-branch-mode session) 'verified)
      (check-equal? (scene-duration (preview-source session)) 3)

      ;; A verified reload installs a fresh source program and increases both
      ;; program and preview document generation without closing the session.
      (write-program! source-path 3)
      (void (preview-reload! session))
      (check-equal? (preview-program-generation session) 1)
      (check-equal? (scene-duration (preview-source session)) 4)
      (check-true (preview-open? session))
      (preview-close! session))
    (lambda ()
      (when (file-exists? source-path) (delete-file source-path)))))
