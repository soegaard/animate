#lang racket/base

;; SCENE-EI-1 and EI-2: authoring commands construct/install whole immutable
;; scenes. Failed candidates leave the currently installed scene unchanged.

(require rackunit
         "../main.rkt"
         "../preview.rkt")

(module+ test
  (define initial
    (scene-add (make-scene) (circle #:id 'dot #:center (vec2 0 0))))
  (define session
    (open-preview-controller
     initial #:fps 4 #:prefetch 0
     #:producer (lambda (document sample _spec _cancellation-token)
                  (list (preview-document-generation document) sample))
     #:byte-size (lambda (_value) 1)))
  (void (attach-preview-transactions! session))
  (check-equal? (preview-edit-scene session) initial)
  (check-equal? (preview-current-display-time session) 0)

  (define marker (circle #:id 'marker #:center (vec2 2 0)))
  (void (preview-add! session marker))
  (check-not-false (scene-ref (preview-edit-scene session) 'marker))
  (check-not-false (scene-ref (preview-source session) 'marker))
  (check-not-false (preview-undo! session))
  (check-false (with-handlers ([exn:fail? (lambda (_error) #f)])
                 (scene-ref (preview-edit-scene session) 'marker)))
  (check-not-false (preview-redo! session))
  (check-not-false (scene-ref (preview-edit-scene session) 'marker))

  (void (preview-checkpoint! session 'before-play))
  (void (preview-play-request! session (move-to 'dot (vec2 3 0)) #:duration 1))
  (void (preview-pause! session))
  (check-equal? (scene-duration (preview-edit-scene session)) 1)
  (check-equal? (preview-checkpoint-names session) '(before-play))
  (void (preview-restore-checkpoint! session 'before-play))
  (check-equal? (scene-duration (preview-edit-scene session)) 0)
  (check-equal? (preview-checkpoint-names session) '(before-play))

  ;; The candidate fails before controller installation, so `marker` remains
  ;; present and no partial transaction reaches undo history.
  (check-exn exn:fail?
             (lambda () (preview-remove! session 'does-not-exist)))
  (check-not-false (scene-ref (preview-edit-scene session) 'marker))

  (void (preview-branch-at! session 0))
  (check-equal? (scene-duration (preview-edit-scene session)) 0)
  (void (preview-reset-to-source! session))
  (check-equal? (preview-edit-scene session) initial)
  (preview-close! session))
