#lang racket/base

;;;
;;; Session-Bound Racket REPL
;;;

;; The REPL owns an evaluation namespace on a normal Racket thread. Every
;; editing binding delegates through the preview transaction/controller APIs;
;; there is no back door to mutate actor fields or GUI widgets.

(require racket/async-channel
         racket/list
         racket/port
         "preview-controller.rkt"
         "preview-model.rkt"
         "preview-transaction.rkt"
         "program-loader.rkt"
         "visual-inspector.rkt")

(provide preview-repl?
         open-preview-repl/internal!
         close-preview-repl!
         preview-repl-open?
         preview-repl-evaluate!
         preview-repl-evaluate-string!
         preview-repl-refresh-source!
         preview-repls-refresh-source!)

(struct repl-command (kind value reply)
  #:transparent)

(struct repl-reply (ok? value)
  #:transparent)

(struct preview-repl (session commands thread alive? namespace loader callbacks)
  #:mutable
  #:transparent)

(define session-repls (make-weak-hasheq))

(define (open-preview-repl/internal! session
                                     #:loader [loader #f]
                                     #:callbacks [callbacks (hash)])
  (unless (preview-session? session)
    (raise-argument-error 'open-preview-repl! "preview-session?" session))
  (unless (or (not loader) (scene-program-loader? loader))
    (raise-argument-error 'open-preview-repl! "(or/c #f scene-program-loader?)" loader))
  (unless (hash? callbacks)
    (raise-argument-error 'open-preview-repl! "hash?" callbacks))
  (attach-preview-transactions! session)
  (define commands (make-async-channel))
  (define alive? (box #t))
  (define initial-namespace (make-repl-namespace session loader callbacks))
  (define repl
    (preview-repl session commands #f alive? initial-namespace loader callbacks))
  (define worker
    (thread (lambda () (repl-loop repl))))
  (set-preview-repl-thread! repl worker)
  (hash-set! session-repls session
             (cons repl (hash-ref session-repls session '())))
  (preview-add-close-hook! session (lambda () (close-preview-repl! repl)))
  repl)

(define (close-preview-repl! repl)
  (unless (preview-repl? repl)
    (raise-argument-error 'close-preview-repl! "preview-repl?" repl))
  (when (unbox (preview-repl-alive? repl))
    (define reply (make-async-channel))
    (async-channel-put (preview-repl-commands repl) (repl-command 'close #f reply))
    (async-channel-get reply)
    (thread-wait (preview-repl-thread repl))
    (define session (preview-repl-session repl))
    (hash-set! session-repls session
               (remq repl (hash-ref session-repls session '()))))
  (void))

(define (preview-repl-open? repl)
  (unless (preview-repl? repl)
    (raise-argument-error 'preview-repl-open? "preview-repl?" repl))
  (unbox (preview-repl-alive? repl)))

(define (preview-repl-evaluate! repl datum)
  (unless (preview-repl? repl)
    (raise-argument-error 'preview-repl-evaluate! "preview-repl?" repl))
  (unless (preview-repl-open? repl)
    (raise-arguments-error 'preview-repl-evaluate! "open preview REPL" "repl" repl))
  (define reply (make-async-channel))
  (async-channel-put (preview-repl-commands repl) (repl-command 'evaluate datum reply))
  (define result (async-channel-get reply))
  (if (repl-reply-ok? result)
      (repl-reply-value result)
      (raise (repl-reply-value result))))

(define (preview-repl-evaluate-string! repl string)
  (unless (string? string)
    (raise-argument-error 'preview-repl-evaluate-string! "string?" string))
  (define input (open-input-string string))
  (define datum (read input))
  (when (eof-object? datum)
    (raise-arguments-error 'preview-repl-evaluate-string! "one Racket expression"
                           "string" string))
  (unless (eof-object? (read input))
    (raise-arguments-error 'preview-repl-evaluate-string! "one Racket expression"
                           "string" string))
  (preview-repl-evaluate! repl datum))

(define (preview-repl-refresh-source! repl loader)
  (unless (preview-repl? repl)
    (raise-argument-error 'preview-repl-refresh-source! "preview-repl?" repl))
  (unless (scene-program-loader? loader)
    (raise-argument-error 'preview-repl-refresh-source! "scene-program-loader?" loader))
  ;; A user may invoke `(reload!)` from this REPL itself. Refreshing that
  ;; namespace inline avoids waiting for a command that only this same thread
  ;; can dequeue.
  (if (eq? (current-thread) (preview-repl-thread repl))
      (refresh-repl-namespace! repl loader)
      (let ()
        (define reply (make-async-channel))
        (async-channel-put (preview-repl-commands repl) (repl-command 'refresh loader reply))
        (define result (async-channel-get reply))
        (if (repl-reply-ok? result)
            (repl-reply-value result)
            (raise (repl-reply-value result))))))

(define (preview-repls-refresh-source! session loader)
  (for ([repl (in-list (hash-ref session-repls session '()))])
    (when (preview-repl-open? repl)
      (with-handlers ([exn:fail? (lambda (_error) (void))])
        (preview-repl-refresh-source! repl loader))))
  (void))

(define (repl-loop repl)
  (let loop ()
    (define command (async-channel-get (preview-repl-commands repl)))
    (case (repl-command-kind command)
      [(close)
       (set-box! (preview-repl-alive? repl) #f)
       (async-channel-put (repl-command-reply command) (repl-reply #t (void)))]
      [(evaluate)
       (define result
         (with-handlers ([exn:fail? (lambda (error) (repl-reply #f error))])
           (repl-reply #t
                       (parameterize ([current-namespace (preview-repl-namespace repl)])
                         (eval (repl-command-value command))))))
       (async-channel-put (repl-command-reply command) result)
       (loop)]
      [(refresh)
       (define result
         (with-handlers ([exn:fail? (lambda (error) (repl-reply #f error))])
           (repl-reply #t (refresh-repl-namespace! repl (repl-command-value command)))))
       (async-channel-put (repl-command-reply command) result)
       (loop)]
      [else
       (async-channel-put
        (repl-command-reply command)
        (repl-reply #f (error 'preview-repl "unknown command: ~e" command)))
       (loop)])))

(define (refresh-repl-namespace! repl loader)
  (define namespace
    (make-repl-namespace (preview-repl-session repl)
                         loader
                         (preview-repl-callbacks repl)))
  (set-preview-repl-namespace! repl namespace)
  (set-preview-repl-loader! repl loader)
  (void))

(define (make-repl-namespace session loader callbacks)
  (define namespace (make-base-namespace))
  (when loader
    ;; Import exactly the exported user-module bindings into the fresh REPL
    ;; namespace. Core animate module instances remain attached by the source
    ;; loader, so scene? identity is not split across namespaces.
    (namespace-attach-module (scene-program-loader-namespace loader)
                             (scene-program-loader-source-path loader)
                             namespace)
    (parameterize ([current-namespace namespace])
      (namespace-require (scene-program-loader-source-path loader))))
  (define (callback name fallback)
    (hash-ref callbacks name fallback))
  (define (install name value)
    (namespace-set-variable-value! name value #t namespace))
  (install 'current-preview session)
  (install 'current-preview-scene (lambda () (preview-edit-scene session)))
  (install 'current-preview-time (lambda () (preview-current-time session)))
  (install 'current-preview-frame (lambda () (preview-current-frame session)))
  (install 'current-selection (lambda () (preview-selection session)))
  (install 'seek! (lambda (time) (preview-seek! session time)))
  (install 'seek-frame! (lambda (frame) (preview-seek-frame! session frame)))
  (install 'step! (lambda ([delta 1]) (preview-step! session delta)))
  (install 'play-range! (lambda (start end) (preview-play-range! session start end)))
  (install 'jump! (lambda (section) (preview-jump-to-section! session section)))
  (install 'play! (lambda (request [duration 1])
                    (preview-play-request! session request #:duration duration)))
  (install 'wait! (lambda (duration) (preview-wait! session duration)))
  (install 'add! (lambda visual (apply preview-add! session visual)))
  (install 'remove! (lambda target (apply preview-remove! session target)))
  (install 'set-value! (lambda (id value) (preview-set-value! session id value)))
  (install 'checkpoint! (lambda (name) (preview-checkpoint! session name)))
  (install 'restore! (lambda (name) (preview-restore-checkpoint! session name)))
  (install 'undo! (lambda () (preview-undo! session)))
  (install 'redo! (lambda () (preview-redo! session)))
  (install 'reset! (callback 'reset! (lambda () (preview-reset-to-initial-source! session))))
  (install 'reload! (callback 'reload! (unavailable-command 'reload!)))
  (install 'rerun-block! (callback 'rerun-block! (unavailable-command 'rerun-block!)))
  (install 'select! (lambda (path) (preview-select! session path)))
  (install 'inspect
           (lambda ([path #f])
             (define scene (preview-source-scene (preview-source session)))
             (define time (preview-current-time session))
             (if path
                 (scene-inspect-path scene path time)
                 (scene-inspection-tree scene time))))
  (install 'copy-path! (lambda () (preview-selection session)))
  namespace)

(define (unavailable-command name)
  (lambda arguments
    (raise-arguments-error name "a source-program preview session" "arguments" arguments)))
