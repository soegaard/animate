#lang racket/base

;;;
;;; Serialized, Hidden OpenGL Context Host
;;;

;; A host has exactly one GUI eventspace and exactly one GL context.  Calls
;; enter its eventspace and execute only within canvas%'s with-gl-context.
;; Consequently GL handles can never leak into authoring values or be used by
;; a different context by accident.

(require racket/async-channel
         racket/class
         racket/match
         racket/gui/base
         "context-config.rkt")

(provide (struct-out gl-context-host)
         make-gl-context-host
         gl-context-host-call
         gl-context-host-close!
         gl-context-host-open?
         gl-context-host-generation
         gl-context-host-context-ok?)

(struct host-success (values) #:transparent)
(struct host-failure (exception) #:transparent)

(struct gl-context-host
  (eventspace frame canvas context lock generation closed?)
  #:mutable
  #:transparent)

(define (call-in-eventspace eventspace thunk)
  (define result (make-async-channel))
  (parameterize ([current-eventspace eventspace])
    (queue-callback
     (lambda ()
       (with-handlers ([exn? (lambda (exception)
                               (async-channel-put result
                                                  (host-failure exception)))])
         (call-with-values thunk
           (lambda result-values
             (async-channel-put result (host-success result-values))))))
     #t))
  (match (async-channel-get result)
    [(host-success result-values) (apply values result-values)]
    [(host-failure exception) (raise exception)]))

; make-gl-context-host : -> gl-context-host?
;; The tiny frame is intentionally not a presentation surface.  It exists only
;; because Racket's portable OpenGL support creates contexts from canvases.
(define (make-gl-context-host)
  (define eventspace (make-eventspace))
  (define-values (frame canvas context)
    (call-in-eventspace
     eventspace
     (lambda ()
       (define frame
         (new frame%
              [label "Animate OpenGL host"]
              [width 8] [height 8]
              [min-width 8] [min-height 8]
              [stretchable-width #f] [stretchable-height #f]))
       (define canvas
         (new canvas%
              [parent frame]
              [style '(gl no-autoclear)]
              [gl-config (make-opengl-config)]))
       ;; Context initialization differs by platform.  This follows the same
       ;; conservative sequence used by Pict3D's invisible context helper.
       (case (system-type)
         [(macosx) (void)]
         [(windows) (send frame reflow-container)]
         [else (send frame show #t) (send frame show #f)])
       (define context (send (send canvas get-dc) get-gl-context))
       (unless (and context (send context ok?))
         (error 'make-gl-context-host
                "Racket could not create an OpenGL context from the hidden canvas"))
       (values frame canvas context))))
  (gl-context-host eventspace frame canvas context (make-semaphore 1) 0 #f))

(define (gl-context-host-open? host)
  (unless (gl-context-host? host)
    (raise-argument-error 'gl-context-host-open? "gl-context-host?" host))
  (not (gl-context-host-closed? host)))

(define (gl-context-host-context-ok? host)
  (unless (gl-context-host? host)
    (raise-argument-error 'gl-context-host-context-ok? "gl-context-host?" host))
  (and (gl-context-host-open? host)
       (call-in-eventspace
        (gl-context-host-eventspace host)
        (lambda () (send (gl-context-host-context host) ok?)))))

; gl-context-host-call : gl-context-host? (-> any/c) -> any/c
;; Runs thunk in the context-owning eventspace with the GL context current.
;; The semaphore means that a renderer cannot interleave state or resource
;; operations with another renderer call on the same host.
(define (gl-context-host-call host thunk)
  (unless (gl-context-host? host)
    (raise-argument-error 'gl-context-host-call "gl-context-host?" host))
  (unless (procedure? thunk)
    (raise-argument-error 'gl-context-host-call "procedure?" thunk))
  (call-with-semaphore
   (gl-context-host-lock host)
   (lambda ()
     (when (gl-context-host-closed? host)
       (raise-arguments-error 'gl-context-host-call "an open context host"
                              "host" host))
     (call-in-eventspace
      (gl-context-host-eventspace host)
      (lambda ()
        (send (gl-context-host-canvas host) with-gl-context thunk))))))

; gl-context-host-close! : gl-context-host? -> void?
;; Resource owners must delete their GL resources through gl-context-host-call
;; before closing.  Closing hides the frame and invalidates every generation.
(define (gl-context-host-close! host)
  (unless (gl-context-host? host)
    (raise-argument-error 'gl-context-host-close! "gl-context-host?" host))
  (call-with-semaphore
   (gl-context-host-lock host)
   (lambda ()
     (unless (gl-context-host-closed? host)
       (call-in-eventspace
        (gl-context-host-eventspace host)
        (lambda () (send (gl-context-host-frame host) show #f)))
       (set-gl-context-host-closed?! host #t)
       (set-gl-context-host-generation! host
                                        (add1 (gl-context-host-generation host))))))
  (void))
