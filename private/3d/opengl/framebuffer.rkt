#lang racket/base

;;;
;;; Backend-Owned Offscreen Framebuffers
;;;

(require "api.rkt"
         "context-host.rkt"
         "gl-object.rkt")

(provide (struct-out gl-framebuffer-target)
         (struct-out gl-framebuffer-cache)
         make-gl-framebuffer-cache
         gl-framebuffer-cache-ensure!
         gl-framebuffer-cache-clear!
         gl-framebuffer-target-bind-draw!
         gl-framebuffer-target-resolve!
         gl-framebuffer-target-read-rgba!
         gl-framebuffer-cache-statistics)

(struct gl-framebuffer-target
  (width height samples framebuffer color depth resolve-framebuffer resolve-color
         byte-size context-identity last-used)
  #:transparent)

(struct gl-framebuffer-cache (entries allocations max-bytes bytes tick) #:mutable #:transparent)

; make-gl-framebuffer-cache : [#:max-bytes exact-positive-integer?] -> gl-framebuffer-cache?
;; Keeps a bounded LRU of backend-owned targets rather than retaining every
;; preview size and MSAA tier seen during a long authoring session.
(define (make-gl-framebuffer-cache #:max-bytes [max-bytes (* 64 1024 1024)])
  (unless (exact-positive-integer? max-bytes)
    (raise-argument-error 'make-gl-framebuffer-cache "exact-positive-integer?" max-bytes))
  (gl-framebuffer-cache (make-hash) 0 max-bytes 0 0))

(define (one vector) (u32vector-ref vector 0))

(define (delete-buffer-object delete id)
  (delete 1 (u32vector id)))

(define (make-framebuffer-resource host id label)
  (gl-framebuffer (gl-context-host-identity host) id 0 #f label
                  (lambda (value) (delete-buffer-object glDeleteFramebuffers value))))

(define (make-texture-resource host id bytes label)
  (gl-texture (gl-context-host-identity host) id bytes #f label
              (lambda (value) (delete-buffer-object glDeleteTextures value))))

(define (make-renderbuffer-resource host id bytes label)
  (gl-renderbuffer (gl-context-host-identity host) id bytes #f label
                   (lambda (value) (delete-buffer-object glDeleteRenderbuffers value))))

(define (target-key width height samples identity)
  (vector width height samples identity))

(define (requested-samples->actual requested maximum)
  (cond [(<= requested 1) 1]
        [(<= maximum 1) 1]
        [else (max 1 (min requested maximum))]))

; gl-framebuffer-cache-ensure! : cache host width height samples max-samples -> target
;; Called outside the host's context.  FBO allocation itself is serialized and
;; current through gl-context-host-call.
(define (gl-framebuffer-cache-ensure! cache host width height requested-samples maximum-samples)
  (unless (gl-framebuffer-cache? cache)
    (raise-argument-error 'gl-framebuffer-cache-ensure! "gl-framebuffer-cache?" cache))
  (unless (gl-context-host? host)
    (raise-argument-error 'gl-framebuffer-cache-ensure! "gl-context-host?" host))
  (for ([value (in-list (list width height requested-samples))])
    (unless (exact-positive-integer? value)
      (raise-argument-error 'gl-framebuffer-cache-ensure! "exact-positive-integer?" value)))
  (unless (exact-nonnegative-integer? maximum-samples)
    (raise-argument-error 'gl-framebuffer-cache-ensure! "exact-nonnegative-integer?" maximum-samples))
  (define samples (requested-samples->actual requested-samples maximum-samples))
  (define key (target-key width height samples (gl-context-host-identity host)))
  (define existing (hash-ref (gl-framebuffer-cache-entries cache) key #f))
  (or (and existing
           (let ()
             (set-gl-framebuffer-cache-tick! cache (add1 (gl-framebuffer-cache-tick cache)))
             (define touched
               (struct-copy gl-framebuffer-target existing
                            [last-used (gl-framebuffer-cache-tick cache)]))
             (hash-set! (gl-framebuffer-cache-entries cache) key touched)
             touched))
      (let ([target (gl-context-host-call
                     host
                     (lambda () (make-framebuffer-target/current! host width height samples)))])
        (set-gl-framebuffer-cache-tick! cache (add1 (gl-framebuffer-cache-tick cache)))
        (define touched
          (struct-copy gl-framebuffer-target target
                       [last-used (gl-framebuffer-cache-tick cache)]))
        (hash-set! (gl-framebuffer-cache-entries cache) key touched)
        (set-gl-framebuffer-cache-allocations! cache
                                               (add1 (gl-framebuffer-cache-allocations cache)))
        (set-gl-framebuffer-cache-bytes!
         cache (+ (gl-framebuffer-cache-bytes cache)
                  (gl-framebuffer-target-byte-size touched)))
        (gl-framebuffer-cache-evict! cache host key)
        touched)))

(define (check-complete who)
  (unless (= (glCheckFramebufferStatus GL_FRAMEBUFFER) GL_FRAMEBUFFER_COMPLETE)
    (raise-arguments-error who "a complete framebuffer"
                           "status" (glCheckFramebufferStatus GL_FRAMEBUFFER))))

(define (make-framebuffer-target/current! host width height samples)
  (define byte-size (* width height 4))
  (define framebuffer #f)
  (define color #f)
  (define depth #f)
  (define resolve-framebuffer #f)
  (define resolve-color #f)
  (with-handlers
      ([exn? (lambda (exception)
               (for ([resource (in-list (filter values
                                                  (list resolve-color resolve-framebuffer
                                                        depth color framebuffer)))])
                 (gl-resource-delete-current! resource host))
               (raise exception))])
    (cond
      [(= samples 1)
       (set! framebuffer (make-framebuffer-resource host (one (glGenFramebuffers 1)) "framebuffer"))
       (set! color (make-texture-resource host (one (glGenTextures 1)) byte-size "framebuffer-colour"))
       (set! depth (make-renderbuffer-resource host (one (glGenRenderbuffers 1)) byte-size
                                                "framebuffer-depth"))
       (glBindFramebuffer GL_FRAMEBUFFER (gl-resource-id framebuffer))
       (glBindTexture GL_TEXTURE_2D (gl-resource-id color))
       (glTexImage2D GL_TEXTURE_2D 0 GL_RGBA8 width height 0 GL_RGBA GL_UNSIGNED_BYTE #f)
       (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_NEAREST)
       (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_NEAREST)
       (glFramebufferTexture2D GL_FRAMEBUFFER GL_COLOR_ATTACHMENT0 GL_TEXTURE_2D
                               (gl-resource-id color) 0)
       (glBindRenderbuffer GL_RENDERBUFFER (gl-resource-id depth))
       (glRenderbufferStorage GL_RENDERBUFFER GL_DEPTH24_STENCIL8 width height)
       (glFramebufferRenderbuffer GL_FRAMEBUFFER GL_DEPTH_STENCIL_ATTACHMENT GL_RENDERBUFFER
                                  (gl-resource-id depth))
       (check-complete 'make-framebuffer-target/current!)]
      [else
       ;; Multisampled drawing uses renderbuffers, then resolves into a normal
       ;; RGBA8 texture/FBO which has a portable glReadPixels path.
       (set! framebuffer (make-framebuffer-resource host (one (glGenFramebuffers 1)) "multisample-framebuffer"))
       (set! color (make-renderbuffer-resource host (one (glGenRenderbuffers 1)) byte-size
                                                "multisample-colour"))
       (set! depth (make-renderbuffer-resource host (one (glGenRenderbuffers 1)) byte-size
                                                "multisample-depth"))
       (glBindFramebuffer GL_FRAMEBUFFER (gl-resource-id framebuffer))
       (glBindRenderbuffer GL_RENDERBUFFER (gl-resource-id color))
       (glRenderbufferStorageMultisample GL_RENDERBUFFER samples GL_RGBA8 width height)
       (glFramebufferRenderbuffer GL_FRAMEBUFFER GL_COLOR_ATTACHMENT0 GL_RENDERBUFFER
                                  (gl-resource-id color))
       (glBindRenderbuffer GL_RENDERBUFFER (gl-resource-id depth))
       (glRenderbufferStorageMultisample GL_RENDERBUFFER samples GL_DEPTH24_STENCIL8 width height)
       (glFramebufferRenderbuffer GL_FRAMEBUFFER GL_DEPTH_STENCIL_ATTACHMENT GL_RENDERBUFFER
                                  (gl-resource-id depth))
       (check-complete 'make-framebuffer-target/current!)
       (set! resolve-framebuffer
             (make-framebuffer-resource host (one (glGenFramebuffers 1)) "resolve-framebuffer"))
       (set! resolve-color (make-texture-resource host (one (glGenTextures 1)) byte-size
                                               "resolve-colour"))
       (glBindFramebuffer GL_FRAMEBUFFER (gl-resource-id resolve-framebuffer))
       (glBindTexture GL_TEXTURE_2D (gl-resource-id resolve-color))
       (glTexImage2D GL_TEXTURE_2D 0 GL_RGBA8 width height 0 GL_RGBA GL_UNSIGNED_BYTE #f)
       (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_NEAREST)
       (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_NEAREST)
       (glFramebufferTexture2D GL_FRAMEBUFFER GL_COLOR_ATTACHMENT0 GL_TEXTURE_2D
                               (gl-resource-id resolve-color) 0)
       (check-complete 'make-framebuffer-target/current!)])
    (glBindFramebuffer GL_FRAMEBUFFER 0)
    ;; A multisampled target has two MSAA attachments plus one resolve colour.
    ;; Framebuffer handles are negligible compared with attachments.
    (gl-framebuffer-target width height samples framebuffer color depth resolve-framebuffer resolve-color
                           (+ (* byte-size samples 2) (if (> samples 1) byte-size 0))
                           (gl-context-host-identity host)
                           0)))

(define (check-target-current! target host who)
  (unless (gl-framebuffer-target? target)
    (raise-argument-error who "gl-framebuffer-target?" target))
  (unless (equal? (gl-framebuffer-target-context-identity target)
                  (gl-context-host-identity host))
    (raise-arguments-error who "a framebuffer from the current context generation"
                           "target-identity" (gl-framebuffer-target-context-identity target)
                           "context-generation" (gl-context-host-generation host))))

;; The next three functions must be invoked while `host` is current, normally
;; from a renderer3d-render call wrapped by gl-context-host-call.
(define (gl-framebuffer-target-bind-draw! target host)
  (check-target-current! target host 'gl-framebuffer-target-bind-draw!)
  (glBindFramebuffer GL_FRAMEBUFFER
                     (gl-resource-id (gl-framebuffer-target-framebuffer target)))
  (glViewport 0 0 (gl-framebuffer-target-width target) (gl-framebuffer-target-height target)))

(define (gl-framebuffer-target-resolve! target host)
  (check-target-current! target host 'gl-framebuffer-target-resolve!)
  (when (> (gl-framebuffer-target-samples target) 1)
    (glBindFramebuffer GL_READ_FRAMEBUFFER
                       (gl-resource-id (gl-framebuffer-target-framebuffer target)))
    (glBindFramebuffer GL_DRAW_FRAMEBUFFER
                       (gl-resource-id (gl-framebuffer-target-resolve-framebuffer target)))
    (glBlitFramebuffer 0 0 (gl-framebuffer-target-width target) (gl-framebuffer-target-height target)
                       0 0 (gl-framebuffer-target-width target) (gl-framebuffer-target-height target)
                       GL_COLOR_BUFFER_BIT GL_NEAREST)))

(define (gl-framebuffer-target-read-rgba! target host)
  (check-target-current! target host 'gl-framebuffer-target-read-rgba!)
  (gl-framebuffer-target-resolve! target host)
  (glBindFramebuffer GL_FRAMEBUFFER
                     (gl-resource-id
                      (or (gl-framebuffer-target-resolve-framebuffer target)
                          (gl-framebuffer-target-framebuffer target))))
  (define rgba (make-bytes (* 4 (gl-framebuffer-target-width target)
                             (gl-framebuffer-target-height target))))
  (glReadPixels 0 0 (gl-framebuffer-target-width target) (gl-framebuffer-target-height target)
                GL_RGBA GL_UNSIGNED_BYTE rgba)
  rgba)

(define (destroy-target/current! target host)
  (for ([resource (in-list (filter values
                                    (list (gl-framebuffer-target-resolve-color target)
                                          (gl-framebuffer-target-resolve-framebuffer target)
                                          (gl-framebuffer-target-depth target)
                                          (gl-framebuffer-target-color target)
                                          (gl-framebuffer-target-framebuffer target))))])
    (gl-resource-delete-current! resource host)))

(define (gl-framebuffer-cache-clear! cache host)
  (unless (gl-framebuffer-cache? cache)
    (raise-argument-error 'gl-framebuffer-cache-clear! "gl-framebuffer-cache?" cache))
  (unless (gl-context-host? host)
    (raise-argument-error 'gl-framebuffer-cache-clear! "gl-context-host?" host))
  (gl-context-host-call
   host
   (lambda ()
     (for ([target (in-hash-values (gl-framebuffer-cache-entries cache))])
       (when (equal? (gl-framebuffer-target-context-identity target)
                     (gl-context-host-identity host))
         (destroy-target/current! target host)))
     (hash-clear! (gl-framebuffer-cache-entries cache))
     (set-gl-framebuffer-cache-bytes! cache 0)))
  (void))

(define (gl-framebuffer-cache-statistics cache)
  (unless (gl-framebuffer-cache? cache)
    (raise-argument-error 'gl-framebuffer-cache-statistics "gl-framebuffer-cache?" cache))
  (hasheq 'entries (hash-count (gl-framebuffer-cache-entries cache))
          'allocations (gl-framebuffer-cache-allocations cache)
          'bytes (gl-framebuffer-cache-bytes cache)
          'max-bytes (gl-framebuffer-cache-max-bytes cache)))

;; Eviction runs only after a just-created target has been installed. The
;; current key is protected, so a too-small byte budget retains one usable
;; target instead of creating and immediately deleting it.
(define (gl-framebuffer-cache-evict! cache host protected-key)
  (let loop ()
    (when (and (> (gl-framebuffer-cache-bytes cache)
                  (gl-framebuffer-cache-max-bytes cache))
               (> (hash-count (gl-framebuffer-cache-entries cache)) 1))
      (define candidate
        (for/fold ([best #f]) ([(key target) (in-hash (gl-framebuffer-cache-entries cache))])
          (cond [(equal? key protected-key) best]
                [(not best) (cons key target)]
                [(< (gl-framebuffer-target-last-used target)
                    (gl-framebuffer-target-last-used (cdr best)))
                 (cons key target)]
                [else best])))
      (when candidate
        (gl-context-host-call host
          (lambda () (destroy-target/current! (cdr candidate) host)))
        (hash-remove! (gl-framebuffer-cache-entries cache) (car candidate))
        (set-gl-framebuffer-cache-bytes!
         cache (- (gl-framebuffer-cache-bytes cache)
                  (gl-framebuffer-target-byte-size (cdr candidate))))
        (loop)))))
