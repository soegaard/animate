#lang racket/base

;;;
;;; Immutable Preview Authoring Transactions
;;;

;; Editing is deliberately a layer over the generic preview controller. Each
;; command first constructs a candidate immutable scene, then asks the actor to
;; install it, and only after that succeeds records a new undoable snapshot.

(require racket/list
         "camera.rkt"
         "preview-controller.rkt"
         "preview-model.rkt"
         "rate-function.rkt"
         "scene.rkt")

(provide (struct-out authoring-snapshot)
         attach-preview-transactions!
         preview-transaction-session?
         preview-current-display-time
         preview-edit-scene
         preview-add!
         preview-remove!
         preview-play-request!
         preview-wait!
         preview-set-value!
         preview-set-camera!
         preview-branch-at!
         preview-undo!
         preview-redo!
         preview-checkpoint!
         preview-restore-checkpoint!
         preview-checkpoint-names
         preview-clear-checkpoints!
         preview-reset-to-initial-source!
         preview-rebase-transactions!
         preview-selection
         preview-select!)

(struct authoring-snapshot
  (document edit-scene display-sample current-block selection scratch? label)
  #:transparent)

(struct transaction-context
  (initial-scene edit-scene current-block selection scratch? undo redo checkpoints lock)
  #:mutable
  #:transparent)

(define contexts (make-weak-hasheq))

(define (attach-preview-transactions! session #:initial-scene [initial-scene #f])
  (unless (preview-session? session)
    (raise-argument-error 'attach-preview-transactions! "preview-session?" session))
  (define source (or initial-scene (preview-source-scene (preview-source session))))
  (unless (scene? source)
    (raise-argument-error 'attach-preview-transactions! "scene? initial source" source))
  (or (hash-ref contexts session #f)
      (let ([context (transaction-context source source #f #f #f '() '() (hash)
                                          (make-semaphore 1))])
        (hash-set! contexts session context)
        (preview-add-close-hook! session (lambda () (hash-remove! contexts session)))
        session)))

(define (preview-transaction-session? value)
  (and (preview-session? value) (hash-has-key? contexts value)))

(define (preview-current-display-time session)
  (preview-current-time session))

(define (preview-edit-scene session)
  (transaction-context-edit-scene (context-for 'preview-edit-scene session)))

(define (preview-add! session . visuals)
  (perform-edit!
   'preview-add! session
   (lambda (scene) (apply scene-add scene visuals))
   #:label 'add))

(define (preview-remove! session . targets)
  (perform-edit!
   'preview-remove! session
   (lambda (scene) (apply scene-remove scene targets))
   #:label 'remove))

(define (preview-play-request! session request
                               #:duration [duration 1]
                               #:easing [easing linear])
  (define context (context-for 'preview-play-request! session))
  (with-context context
    (lambda ()
      (define before (transaction-context-edit-scene context))
      (define start (scene-duration before))
      (define candidate (scene-play before request #:duration duration #:easing easing))
      (commit-candidate! session context candidate 'play)
      ;; An appended animation is the one intentional editing operation that
      ;; moves the display. Seeking alone never changes the edit base.
      (preview-play-range! session start (scene-duration candidate)))))

(define (preview-wait! session duration)
  (define context (context-for 'preview-wait! session))
  (with-context context
    (lambda ()
      (define before (transaction-context-edit-scene context))
      (define start (scene-duration before))
      (define candidate (scene-wait before duration))
      (commit-candidate! session context candidate 'wait)
      (preview-play-range! session start (scene-duration candidate)))))

(define (preview-set-value! session id value)
  (perform-edit! 'preview-set-value! session
                 (lambda (scene) (scene-set-value scene id value))
                 #:label 'set-value))

(define (preview-set-camera! session camera)
  (perform-edit! 'preview-set-camera! session
                 (lambda (scene) (scene-set-camera scene camera))
                 #:label 'set-camera))

;; An explicit branch captures a sampled state and camera at display time as a
;; new zero-duration editing base. It intentionally discards earlier timeline
;; intent, which callers can identify through `scratch?` in snapshots.
(define (preview-branch-at! session [time (preview-current-time session)])
  (define context (context-for 'preview-branch-at! session))
  (with-context context
    (lambda ()
      (define source (preview-source-scene (preview-source session)))
      (define-values (state camera) (scene-sample-with-camera source time))
      (define candidate (make-scene state #:camera camera))
      (commit-candidate! session context candidate 'branch #:scratch? #t))))

(define (preview-undo! session)
  (define context (context-for 'preview-undo! session))
  (with-context context
    (lambda ()
      (define undo (transaction-context-undo context))
      (if (null? undo)
          #f
          (let ([target (car undo)] [current (snapshot-for session context 'undo)])
            (install-snapshot! session context target)
            (set-transaction-context-undo! context (cdr undo))
            (set-transaction-context-redo! context
                                           (cons current (transaction-context-redo context)))
            target)))))

(define (preview-redo! session)
  (define context (context-for 'preview-redo! session))
  (with-context context
    (lambda ()
      (define redo (transaction-context-redo context))
      (if (null? redo)
          #f
          (let ([target (car redo)] [current (snapshot-for session context 'redo)])
            (install-snapshot! session context target)
            (set-transaction-context-redo! context (cdr redo))
            (set-transaction-context-undo! context
                                           (cons current (transaction-context-undo context)))
            target)))))

(define (preview-checkpoint! session name)
  (unless (symbol? name)
    (raise-argument-error 'preview-checkpoint! "symbol?" name))
  (define context (context-for 'preview-checkpoint! session))
  (with-context context
    (lambda ()
      (define snapshot (snapshot-for session context name))
      (set-transaction-context-checkpoints!
       context
       (hash-set (transaction-context-checkpoints context) name snapshot))
      snapshot)))

(define (preview-restore-checkpoint! session name)
  (unless (symbol? name)
    (raise-argument-error 'preview-restore-checkpoint! "symbol?" name))
  (define context (context-for 'preview-restore-checkpoint! session))
  (with-context context
    (lambda ()
      (define target (hash-ref (transaction-context-checkpoints context) name #f))
      (unless target
        (raise-arguments-error 'preview-restore-checkpoint! "known checkpoint name" "name" name))
      (define current (snapshot-for session context 'restore))
      (install-snapshot! session context target)
      (set-transaction-context-undo! context (cons current (transaction-context-undo context)))
      (set-transaction-context-redo! context '())
      ;; Restoring branches the edit history. Keep only the checkpoint reached
      ;; by the branch, so stale names never look reachable.
      (set-transaction-context-checkpoints! context (hash name target))
      target)))

(define (preview-checkpoint-names session)
  (sort (hash-keys (transaction-context-checkpoints
                    (context-for 'preview-checkpoint-names session)))
        symbol<?))

(define (preview-clear-checkpoints! session)
  (define context (context-for 'preview-clear-checkpoints! session))
  (with-context context
    (lambda ()
      (set-transaction-context-checkpoints! context (hash))
      (void))))

(define (preview-reset-to-initial-source! session)
  (define context (context-for 'preview-reset-to-initial-source! session))
  (with-context context
    (lambda ()
      (reset-context! session context (transaction-context-initial-scene context)))))

;; Source reloads call this only after a fresh candidate is installed in the
;; controller. Any scratch history refers to the old module generation and is
;; safely discarded rather than replayed against incompatible code.
(define (preview-rebase-transactions! session scene)
  (unless (scene? scene)
    (raise-argument-error 'preview-rebase-transactions! "scene?" scene))
  (define context (context-for 'preview-rebase-transactions! session))
  (with-context context
    (lambda ()
      (set-transaction-context-initial-scene! context scene)
      (set-transaction-context-edit-scene! context scene)
      (set-transaction-context-current-block! context #f)
      (set-transaction-context-scratch?! context #f)
      (set-transaction-context-undo! context '())
      (set-transaction-context-redo! context '())
      (set-transaction-context-checkpoints! context (hash))
      scene)))

(define (preview-selection session)
  (transaction-context-selection (context-for 'preview-selection session)))

(define (preview-select! session selection)
  (unless (or (not selection) (and (list? selection) (pair? selection) (andmap symbol? selection)))
    (raise-argument-error 'preview-select! "(or/c #f nonempty-listof-symbol?)" selection))
  (define context (context-for 'preview-select! session))
  (with-context context
    (lambda ()
      (set-transaction-context-selection! context selection)
      selection)))

(define (perform-edit! who session operation #:label label)
  (define context (context-for who session))
  (with-context context
    (lambda ()
      (define candidate (operation (transaction-context-edit-scene context)))
      (commit-candidate! session context candidate label))))

(define (commit-candidate! session context candidate label #:scratch? [scratch? #t])
  (unless (scene? candidate)
    (raise-arguments-error 'preview-transaction "a scene returned by the edit operation"
                           "candidate" candidate))
  (define old (snapshot-for session context label))
  ;; Installation is synchronous: no context field changes until the actor has
  ;; accepted the candidate and assigned it a new document generation.
  (define status (preview-set-source! session candidate))
  (set-transaction-context-edit-scene! context candidate)
  (set-transaction-context-scratch?! context scratch?)
  (set-transaction-context-undo! context (cons old (transaction-context-undo context)))
  (set-transaction-context-redo! context '())
  status)

(define (install-snapshot! session context snapshot)
  (preview-set-source! session (authoring-snapshot-edit-scene snapshot))
  (define sample (authoring-snapshot-display-sample snapshot))
  (if (frame-sample? sample)
      (preview-seek-frame! session (frame-sample-frame-index sample))
      (preview-seek! session (time-sample-time sample)))
  (set-transaction-context-edit-scene! context (authoring-snapshot-edit-scene snapshot))
  (set-transaction-context-current-block! context (authoring-snapshot-current-block snapshot))
  (set-transaction-context-selection! context (authoring-snapshot-selection snapshot))
  (set-transaction-context-scratch?! context (authoring-snapshot-scratch? snapshot)))

(define (reset-context! session context scene)
  (preview-set-source! session scene)
  (set-transaction-context-edit-scene! context scene)
  (set-transaction-context-current-block! context #f)
  (set-transaction-context-scratch?! context #f)
  (set-transaction-context-undo! context '())
  (set-transaction-context-redo! context '())
  (set-transaction-context-checkpoints! context (hash))
  scene)

(define (snapshot-for session context label)
  (authoring-snapshot (preview-source session)
                      (transaction-context-edit-scene context)
                      (preview-current-sample session)
                      (transaction-context-current-block context)
                      (transaction-context-selection context)
                      (transaction-context-scratch? context)
                      label))

(define (context-for who session)
  (unless (preview-session? session)
    (raise-argument-error who "preview-session?" session))
  (or (hash-ref contexts session #f)
      (raise-arguments-error who "preview with authoring transactions attached"
                             "session" session)))

(define (with-context context thunk)
  (call-with-semaphore (transaction-context-lock context) thunk))
