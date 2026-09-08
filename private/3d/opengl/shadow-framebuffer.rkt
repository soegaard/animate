#lang racket/base

;;; Depth-texture framebuffer owned by one OpenGL context generation

(require ffi/vector
         "api.rkt"
         "context-host.rkt"
         "gl-object.rkt")

(provide (struct-out gl-shadow-target)
         make-gl-shadow-target/current!
         gl-shadow-target-bind-draw/current!
         gl-shadow-target-delete/current!)

(struct gl-shadow-target (size framebuffer depth-texture byte-size context-identity)
  #:transparent)

(define (one ids) (u32vector-ref ids 0))

(define (delete-one delete id)
  (delete 1 (u32vector id)))

(define (make-framebuffer-resource host id)
  (gl-framebuffer (gl-context-host-identity host) id 0 #f "shadow-framebuffer"
                  (lambda (value) (delete-one glDeleteFramebuffers value))))

(define (make-depth-texture-resource host id byte-size)
  (gl-texture (gl-context-host-identity host) id byte-size #f "shadow-depth-texture"
              (lambda (value) (delete-one glDeleteTextures value))))

;; This runs only inside the serial context-host callback. The GLSL PCF loop
;; samples the depth texture through a `sampler2DShadow`; comparison mode makes
;; each explicit kernel tap a well-defined hardware depth comparison on the
;; macOS OpenGL driver as well as on ordinary desktop GL implementations.
(define (make-gl-shadow-target/current! host size)
  (unless (gl-context-host? host)
    (raise-argument-error 'make-gl-shadow-target/current! "gl-context-host?" host))
  (unless (exact-positive-integer? size)
    (raise-argument-error 'make-gl-shadow-target/current! "exact-positive-integer?" size))
  (define framebuffer #f)
  (define depth-texture #f)
  (define byte-size (* size size 4))
  (with-handlers
      ([exn? (lambda (exception)
               (for ([resource (in-list (filter values (list depth-texture framebuffer)))])
                 (gl-resource-delete-current! resource host))
               (raise exception))])
    (set! framebuffer
          (make-framebuffer-resource host (one (glGenFramebuffers 1))))
    (set! depth-texture
          (make-depth-texture-resource host (one (glGenTextures 1)) byte-size))
    (glBindFramebuffer GL_FRAMEBUFFER (gl-resource-id framebuffer))
    (glBindTexture GL_TEXTURE_2D (gl-resource-id depth-texture))
    (glTexImage2D GL_TEXTURE_2D 0 GL_DEPTH_COMPONENT24 size size 0
                  GL_DEPTH_COMPONENT GL_FLOAT #f)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_NEAREST)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_NEAREST)
    ;; A shadow map has exactly one rendered level. Explicitly constraining
    ;; the complete mip range avoids older macOS drivers treating the unused
    ;; default levels as an unloadable texture chain.
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_BASE_LEVEL 0)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAX_LEVEL 0)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_S GL_CLAMP_TO_EDGE)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_T GL_CLAMP_TO_EDGE)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_COMPARE_MODE GL_COMPARE_REF_TO_TEXTURE)
    (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_COMPARE_FUNC GL_LEQUAL)
    (glFramebufferTexture2D GL_FRAMEBUFFER GL_DEPTH_ATTACHMENT GL_TEXTURE_2D
                            (gl-resource-id depth-texture) 0)
    (glDrawBuffer GL_NONE)
    (glReadBuffer GL_NONE)
    (unless (= (glCheckFramebufferStatus GL_FRAMEBUFFER) GL_FRAMEBUFFER_COMPLETE)
      (raise-arguments-error 'make-gl-shadow-target/current! "a complete depth framebuffer"
                             "status" (glCheckFramebufferStatus GL_FRAMEBUFFER)))
    (glBindTexture GL_TEXTURE_2D 0)
    (glBindFramebuffer GL_FRAMEBUFFER 0)
    (gl-shadow-target size framebuffer depth-texture byte-size
                      (gl-context-host-identity host))))

(define (check-current who target host)
  (unless (gl-shadow-target? target)
    (raise-argument-error who "gl-shadow-target?" target))
  (unless (gl-context-host? host)
    (raise-argument-error who "gl-context-host?" host))
  (unless (equal? (gl-shadow-target-context-identity target)
                  (gl-context-host-identity host))
    (raise-arguments-error who "a shadow target from the current context generation"
                           "target" target))
  (gl-resource-check-current! (gl-shadow-target-framebuffer target) host)
  (gl-resource-check-current! (gl-shadow-target-depth-texture target) host))

(define (gl-shadow-target-bind-draw/current! target host)
  (check-current 'gl-shadow-target-bind-draw/current! target host)
  (glBindFramebuffer GL_FRAMEBUFFER
                     (gl-resource-id (gl-shadow-target-framebuffer target)))
  (glViewport 0 0 (gl-shadow-target-size target) (gl-shadow-target-size target)))

(define (gl-shadow-target-delete/current! target host)
  (check-current 'gl-shadow-target-delete/current! target host)
  (gl-resource-delete-current! (gl-shadow-target-depth-texture target) host)
  (gl-resource-delete-current! (gl-shadow-target-framebuffer target) host)
  (void))
