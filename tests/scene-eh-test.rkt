#lang racket/base

;; SCENE-EH-1 through EH-3: source blocks compile to immutable scene
;; checkpoints; a retained prefix is explicitly marked when it is reused.

(require rackunit
         "../main.rkt"
         "../authoring.rkt")

(define-scene-program two-step-program
  #:initial (make-scene)
  (scene-block setup (scene)
    (scene-wait scene 1))
  (scene-block finish (scene)
    (scene-wait scene 2)))

(module+ test
  (define first (compile-scene-program two-step-program #:generation 4))
  (check-equal? (scene-duration (compiled-scene-program-scene first)) 3)
  (check-equal? (map scene-block-run-id
                     (compiled-scene-program-block-runs first))
                '(setup finish))
  (check-equal? (compiled-program-block-start first 'setup) 0)
  (check-equal? (compiled-program-block-end first 'setup) 1)
  (check-equal? (compiled-program-block-start first 'finish) 1)
  (check-equal? (compiled-program-block-end first 'finish) 3)
  (check-equal? (scene-duration (compiled-program-prefix-scene first 'setup)) 1)
  (check-false (scene-block-run-reused? (compiled-program-block first 'setup)))
  (check-true (real? (scene-block-run-build-milliseconds
                      (compiled-program-block first 'setup))))

  ;; The syntax macro records an actual source location, rather than leaving
  ;; a later GUI or watcher to reverse-engineer source locations from closures.
  (define setup-location
    (scene-block-spec-source-location
     (car (scene-program-blocks two-step-program))))
  (check-true (source-location? setup-location))
  (check-true (path-string? (source-location-source setup-location)))
  (check-true (positive? (source-location-line setup-location)))
  (check-true (exact-nonnegative-integer? (source-location-position setup-location)))

  ;; A changed suffix has to be supplied by a newly loaded program.  The
  ;; unchanged setup declaration allows precisely one checkpoint to be reused.
  (define changed-program
    (make-scene-program
     'two-step-program
     (lambda () (make-scene))
     (list
      (car (scene-program-blocks two-step-program))
      (make-scene-block
       'finish
       (lambda (scene) (scene-wait scene 3))
       #:source-location
       (scene-block-spec-source-location
        (cadr (scene-program-blocks two-step-program)))
       #:source-fingerprint "changed"))))
  (define incremental
    (compile-scene-program/incremental changed-program first 1 #:generation 5))
  (check-equal? (scene-duration (compiled-scene-program-scene incremental)) 4)
  (check-true (scene-block-run-reused?
               (compiled-program-block incremental 'setup)))
  (check-false (scene-block-run-reused?
                (compiled-program-block incremental 'finish)))

  ;; A malformed return and a duration regression both report the source block
  ;; that caused the failed atomic compile.
  (define bad-return
    (make-scene-program
     'bad-return (lambda () (make-scene))
     (list (make-scene-block 'bad (lambda (_scene) 'not-a-scene)
                             #:source-location setup-location))))
  (check-exn #rx"block bad"
             (lambda () (compile-scene-program bad-return)))
  (define regression
    (make-scene-program
     'regression (lambda () (scene-wait (make-scene) 2))
     (list (make-scene-block 'backwards (lambda (_scene) (make-scene))
                             #:source-location setup-location))))
  (check-exn #rx"block backwards"
             (lambda () (compile-scene-program regression))))
