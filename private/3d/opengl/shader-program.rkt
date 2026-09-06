#lang racket/base

;;;
;;; GLSL Program Compilation and Diagnostics
;;;

(require file/sha1
         racket/file
         racket/format
         racket/list
         "api.rkt"
         "context-host.rkt"
         "gl-object.rkt")

(provide (struct-out gl-shader-program)
         make-gl-shader-program
         gl-shader-program-uniform
         gl-shader-program-id
         gl-shader-program-delete!)

(struct gl-shader-program (resource uniforms vertex-digest fragment-digest)
  #:mutable
  #:transparent)

(define (shader-log shader)
  (define length (glGetShaderiv shader GL_INFO_LOG_LENGTH))
  (if (positive? length)
      (let-values ([(actual-length bytes) (glGetShaderInfoLog shader length)])
        (bytes->string/utf-8 bytes #\? 0 actual-length))
      ""))

(define (program-log program)
  (define length (glGetProgramiv program GL_INFO_LOG_LENGTH))
  (if (positive? length)
      (let-values ([(actual-length bytes) (glGetProgramInfoLog program length)])
        (bytes->string/utf-8 bytes #\? 0 actual-length))
      ""))

(define (compile-shader! type source label)
  (define shader (glCreateShader type))
  (with-handlers ([exn? (lambda (exception)
                          (when (positive? shader) (glDeleteShader shader))
                          (raise exception))])
    (glShaderSource shader 1 (vector source) (s32vector (string-length source)))
    (glCompileShader shader)
    (unless (= (glGetShaderiv shader GL_COMPILE_STATUS) GL_TRUE)
      (define log (shader-log shader))
      (glDeleteShader shader)
      (raise-arguments-error 'make-gl-shader-program "a compiling GLSL shader"
                             "shader" label "log" log))
    shader))

(define (file-source path)
  (unless (path-string? path)
    (raise-argument-error 'make-gl-shader-program "path-string?" path))
  (file->string path))

(define (make-gl-shader-program host vertex-path fragment-path
                                #:attributes [attributes '(("position" . 0)
                                                         ("normal" . 1)
                                                         ("color" . 2))])
  (unless (gl-context-host? host)
    (raise-argument-error 'make-gl-shader-program "gl-context-host?" host))
  (unless (and (list? attributes)
               (andmap (lambda (entry)
                         (and (pair? entry) (string? (car entry))
                              (exact-nonnegative-integer? (cdr entry))))
                       attributes))
    (raise-argument-error 'make-gl-shader-program
                          "(listof (cons/c string? exact-nonnegative-integer?))"
                          attributes))
  (define vertex-source (file-source vertex-path))
  (define fragment-source (file-source fragment-path))
  (gl-context-host-call
   host
   (lambda ()
     (define vertex #f)
     (define fragment #f)
     (define program #f)
     (with-handlers ([exn? (lambda (exception)
                             (when program (glDeleteProgram program))
                             (when vertex (glDeleteShader vertex))
                             (when fragment (glDeleteShader fragment))
                             (raise exception))])
       (set! vertex (compile-shader! GL_VERTEX_SHADER vertex-source vertex-path))
       (set! fragment (compile-shader! GL_FRAGMENT_SHADER fragment-source fragment-path))
       (set! program (glCreateProgram))
       (glAttachShader program vertex)
       (glAttachShader program fragment)
       (for ([attribute (in-list attributes)])
         (glBindAttribLocation program (cdr attribute) (car attribute)))
       (glLinkProgram program)
       (unless (= (glGetProgramiv program GL_LINK_STATUS) GL_TRUE)
         (define log (program-log program))
         (raise-arguments-error 'make-gl-shader-program "a linking GLSL program"
                                "vertex" vertex-path "fragment" fragment-path "log" log))
       (glDeleteShader vertex)
       (glDeleteShader fragment)
       (gl-shader-program
        (gl-program (gl-context-host-identity host) program 0 #f
                    (format "program:~a+~a" vertex-path fragment-path)
                    glDeleteProgram)
        (make-hash)
        (sha1-bytes (string->bytes/utf-8 vertex-source))
        (sha1-bytes (string->bytes/utf-8 fragment-source)))))))

(define (gl-shader-program-id program)
  (unless (gl-shader-program? program)
    (raise-argument-error 'gl-shader-program-id "gl-shader-program?" program))
  (gl-resource-id (gl-shader-program-resource program)))

(define (gl-shader-program-uniform program host name)
  (unless (gl-shader-program? program)
    (raise-argument-error 'gl-shader-program-uniform "gl-shader-program?" program))
  (unless (string? name)
    (raise-argument-error 'gl-shader-program-uniform "string?" name))
  (gl-resource-check-current! (gl-shader-program-resource program) host)
  (hash-ref!
   (gl-shader-program-uniforms program) name
   (lambda ()
     (gl-context-host-call
      host
      (lambda ()
        (glGetUniformLocation (gl-shader-program-id program) name))))))

(define (gl-shader-program-delete! program host)
  (unless (gl-shader-program? program)
    (raise-argument-error 'gl-shader-program-delete! "gl-shader-program?" program))
  (gl-resource-delete! (gl-shader-program-resource program) host))
