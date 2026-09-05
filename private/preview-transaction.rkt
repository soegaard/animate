#lang racket/base

;;;
;;; Immutable Preview Authoring Transactions
;;;

;; Editing is deliberately a layer over the generic preview controller. Each
;; command first constructs a candidate immutable scene, then asks the actor to
;; install it, and only after that succeeds records a new undoable snapshot.

(require racket/list
         "camera.rkt"
         "formula-parts-visual.rkt"
         "formula-source.rkt"
         "formula-source-map.rkt"
         "preview-controller.rkt"
         "preview-model.rkt"
         "rate-function.rkt"
         "scene.rkt"
         "scene-state.rkt"
         "source-document.rkt"
         "visual-model.rkt")

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
         preview-select!
         preview-selection-reload-diagnostic)

(struct authoring-snapshot
  (document edit-scene display-sample current-block selection scratch? label)
  #:transparent)

(struct transaction-context
  (initial-scene edit-scene current-block selection selection-reload-diagnostic
                 scratch? undo redo checkpoints lock)
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
      (let ([context (transaction-context source source #f #f #f #f '() '() (hash)
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
;; safely discarded rather than replayed against incompatible code. Selection
;; identity is handled separately and conservatively: a reload may retain an
;; exact Visual path, then a unique named formula part, then an exact mapped
;; source span. It never guesses between repeated formula occurrences.
(define (preview-rebase-transactions! session scene)
  (unless (scene? scene)
    (raise-argument-error 'preview-rebase-transactions! "scene?" scene))
  (define context (context-for 'preview-rebase-transactions! session))
  (with-context context
    (lambda ()
      (define old-scene (transaction-context-edit-scene context))
      (define old-selection (transaction-context-selection context))
      (define-values (selection diagnostic)
        (preserve-selection-after-reload
         old-scene
         (preview-current-time session)
         old-selection
         scene))
      (set-transaction-context-initial-scene! context scene)
      (set-transaction-context-edit-scene! context scene)
      (set-transaction-context-current-block! context #f)
      (set-transaction-context-selection! context selection)
      (set-transaction-context-selection-reload-diagnostic! context diagnostic)
      (set-transaction-context-scratch?! context #f)
      (set-transaction-context-undo! context '())
      (set-transaction-context-redo! context '())
      (set-transaction-context-checkpoints! context (hash))
      scene)))

(define (preview-selection session)
  (transaction-context-selection (context-for 'preview-selection session)))

;; Returns #f for an ordinary live selection, or an immutable explanatory
;; string after a source reload. The diagnostic is deliberately separate from
;; the path: consumers can show it without treating a failed identity match as
;; a selectable Visual.
(define (preview-selection-reload-diagnostic session)
  (transaction-context-selection-reload-diagnostic
   (context-for 'preview-selection-reload-diagnostic session)))

(define (preview-select! session selection)
  (unless (or (not selection) (and (list? selection) (pair? selection) (andmap symbol? selection)))
    (raise-argument-error 'preview-select! "(or/c #f nonempty-listof-symbol?)" selection))
  (define context (context-for 'preview-select! session))
  (with-context context
    (lambda ()
      (set-transaction-context-selection! context selection)
      (set-transaction-context-selection-reload-diagnostic! context #f)
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
  (set-transaction-context-selection-reload-diagnostic! context #f)
  (set-transaction-context-scratch?! context (authoring-snapshot-scratch? snapshot)))

(define (reset-context! session context scene)
  (preview-set-source! session scene)
  (set-transaction-context-edit-scene! context scene)
  (set-transaction-context-current-block! context #f)
  (set-transaction-context-selection! context #f)
  (set-transaction-context-selection-reload-diagnostic! context #f)
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


;;;
;;; Selection Identity Across Source Reload
;;;

;; This code purposefully lives next to transaction rebasing rather than in the
;; GUI. A source reload performed by the REPL, file watcher, or a future editor
;; bridge gets the exact same conservative identity policy.

(define (preserve-selection-after-reload old-scene time old-selection new-scene)
  (cond
    [(not old-selection) (values #f #f)]
    [else
     (with-handlers
         ([exn:fail?
           (lambda (_error)
             (values #f
                     "selection cleared after reload: its previous semantic path could not be resolved"))])
       (define old-state (scene-state-at old-scene time))
       (define new-state (scene-state-at new-scene time))
       (cond
         [(scene-state-has? new-state old-selection)
          (values old-selection "selection retained after reload: exact Visual path")]
         [else
          (define named-candidates
            (named-formula-part-candidates old-state old-selection new-state))
          (cond
            [(= (length named-candidates) 1)
             (values (car named-candidates)
                     "selection retained after reload: unique named formula part")]
            [(pair? named-candidates)
             (values #f
                     "selection cleared after reload: named formula part is ambiguous")]
            [else
             (define source-candidates
               (source-span-candidates old-state old-selection new-state))
             (cond
               [(= (length source-candidates) 1)
                (values (car source-candidates)
                        "selection retained after reload: exact formula source span")]
               [(pair? source-candidates)
                (values #f
                        "selection cleared after reload: formula source span is ambiguous")]
               [else
                (values #f
                        "selection cleared after reload: no stable Visual, named-part, or source-span identity")])])]))]))

(define (scene-state-at scene time)
  (scene-sample scene (min time (scene-duration scene))))

(define (named-formula-part-candidates old-state old-selection new-state)
  (define part-name (selected-formula-part-name old-state old-selection))
  (if (not part-name)
      '()
      (for/list ([entry (in-list (formula-roots new-state))]
                 #:when (formula-assembly-visual-has-part?
                         (cdr entry) part-name))
        (append (car entry) (list part-name)))))

(define (selected-formula-part-name state selection)
  (for/or ([length (in-range (sub1 (length selection)) 0 -1)])
    (define prefix (take selection length))
    (define suffix (drop selection length))
    (and (pair? suffix)
         (with-handlers ([exn:fail? (lambda (_error) #f)])
           (define candidate (scene-state-ref state prefix))
           (and (formula-assembly-visual? candidate)
                (formula-assembly-visual-has-part? candidate (car suffix))
                (car suffix))))))

;; An exact source fallback needs both the complete canonical formula text and
;; its exact map span. Matching text alone would silently select the wrong
;; repeated occurrence, which is precisely what reload recovery must avoid.
(define (source-span-candidates old-state old-selection new-state)
  (define old-identity (selected-formula-source-identity old-state old-selection))
  (if (not old-identity)
      '()
      (let ([source (car old-identity)]
            [span (cdr old-identity)])
        (append*
         (for/list ([entry (in-list (formula-roots new-state))]
                    #:when
                    (with-handlers ([exn:fail? (lambda (_error) #f)])
                      (string=? source (formula-source (cdr entry)))))
           (for/list ([match (in-list (formula-source-map-matches
                                       (formula-source-map (cdr entry))))]
                      #:when (equal? span (formula-source-match-span match))
                      [relative (in-list (formula-source-match-relative-paths match))])
             (append (car entry) relative)))))))

(define (selected-formula-source-identity state selection)
  (for/or ([length (in-range (sub1 (length selection)) 0 -1)])
    (define prefix (take selection length))
    (define relative (drop selection length))
    (and (pair? relative)
         (with-handlers ([exn:fail? (lambda (_error) #f)])
           (define formula (scene-state-ref state prefix))
           (define mapping
             (and (formula-assembly-visual? formula)
                  (formula-source-map formula)))
           (and mapping
                (for/or ([match (in-list (formula-source-map-matches mapping))]
                         #:when (member relative
                                        (formula-source-match-relative-paths match)
                                        equal?))
                  (cons (formula-source formula)
                        (formula-source-match-span match))))))))

(define (formula-roots state)
  (append*
   (for/list ([visual (in-list (scene-state-visuals-in-drawing-order state))])
     (enumerate-formula-roots visual (list (visual-id visual))))))

(define (enumerate-formula-roots visual path)
  (append
   (if (formula-assembly-visual? visual)
       (list (cons path visual))
       '())
   (if (visual-container? visual)
       (append*
        (for/list ([child (in-list (visual-child-entries visual))])
          (enumerate-formula-roots
           (visual-child-visual child)
           (append path (list (visual-child-id child))))))
       '())))
