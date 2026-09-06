#lang racket/base

;; SCENE-3D-P context spike.  Run with GRacket so that Racket's GUI runtime is
;; permitted to create the invisible canvas context:
;;
;;   gracket tools/opengl-info.rkt [output.rktd]

(require racket/cmdline
         racket/file
         racket/format
         racket/list
         racket/pretty
         ffi/vector
         opengl
         "../private/3d/opengl/capabilities.rkt"
         "../private/3d/opengl/context-host.rkt")

(define output-path
  (command-line
   #:args ([output "rendered-examples/opengl-info.rktd"])
   output))

(define (one vector) (u32vector-ref vector 0))

(define (delete-buffer id) (glDeleteBuffers 1 (u32vector id)))
(define (delete-vertex-array id) (glDeleteVertexArrays 1 (u32vector id)))
(define (delete-framebuffer id) (glDeleteFramebuffers 1 (u32vector id)))
(define (delete-texture id) (glDeleteTextures 1 (u32vector id)))
(define (delete-renderbuffer id) (glDeleteRenderbuffers 1 (u32vector id)))

(define vertex-source
  "#version 150\nin vec3 position;\nvoid main() { gl_Position = vec4(position, 1.0); }\n")
(define fragment-source
  "#version 150\nout vec4 fragment;\nvoid main() { fragment = vec4(0.25, 0.5, 0.75, 1.0); }\n")

(define (compile-shader type source)
  (define shader (glCreateShader type))
  (glShaderSource shader 1 (vector source) (s32vector (string-length source)))
  (glCompileShader shader)
  (unless (= (glGetShaderiv shader GL_COMPILE_STATUS) GL_TRUE)
    (error 'opengl-info "shader compilation failed: ~a"
           (let-values ([(length log) (glGetShaderInfoLog shader
                                                              (glGetShaderiv shader GL_INFO_LOG_LENGTH))])
             (bytes->string/utf-8 log #\? 0 length))))
  shader)

(define (make-program)
  (define vertex (compile-shader GL_VERTEX_SHADER vertex-source))
  (define fragment (compile-shader GL_FRAGMENT_SHADER fragment-source))
  (define program (glCreateProgram))
  (dynamic-wind
   void
   (lambda ()
     (glAttachShader program vertex)
     (glAttachShader program fragment)
     (glBindAttribLocation program 0 "position")
     (glLinkProgram program)
     (unless (= (glGetProgramiv program GL_LINK_STATUS) GL_TRUE)
       (error 'opengl-info "program link failed: ~a"
              (let-values ([(length log) (glGetProgramInfoLog program
                                                                  (glGetProgramiv program GL_INFO_LOG_LENGTH))])
                (bytes->string/utf-8 log #\? 0 length))))
     program)
   (lambda ()
     (glDeleteShader vertex)
     (glDeleteShader fragment))))

(define (run-triangle-spike!)
  (define vao (one (glGenVertexArrays 1)))
  (define buffer (one (glGenBuffers 1)))
  (define framebuffer (one (glGenFramebuffers 1)))
  (define texture (one (glGenTextures 1)))
  (define depth (one (glGenRenderbuffers 1)))
  (define program #f)
  (dynamic-wind
   void
   (lambda ()
     (glBindVertexArray vao)
     (glBindBuffer GL_ARRAY_BUFFER buffer)
     (define positions (f32vector -0.8 -0.8 0.0 0.8 -0.8 0.0 0.0 0.8 0.0))
     (glBufferData GL_ARRAY_BUFFER (* 4 (f32vector-length positions)) positions GL_STATIC_DRAW)
     (glEnableVertexAttribArray 0)
     (glVertexAttribPointer 0 3 GL_FLOAT #f 0 0)
     (set! program (make-program))
     (glBindFramebuffer GL_FRAMEBUFFER framebuffer)
     (glBindTexture GL_TEXTURE_2D texture)
     (glTexImage2D GL_TEXTURE_2D 0 GL_RGBA8 16 16 0 GL_RGBA GL_UNSIGNED_BYTE #f)
     (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_NEAREST)
     (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_NEAREST)
     (glFramebufferTexture2D GL_FRAMEBUFFER GL_COLOR_ATTACHMENT0 GL_TEXTURE_2D texture 0)
     (glBindRenderbuffer GL_RENDERBUFFER depth)
     (glRenderbufferStorage GL_RENDERBUFFER GL_DEPTH24_STENCIL8 16 16)
     (glFramebufferRenderbuffer GL_FRAMEBUFFER GL_DEPTH_STENCIL_ATTACHMENT GL_RENDERBUFFER depth)
     (unless (= (glCheckFramebufferStatus GL_FRAMEBUFFER) GL_FRAMEBUFFER_COMPLETE)
       (error 'opengl-info "RGBA8/depth framebuffer is incomplete"))
     (glViewport 0 0 16 16)
     (glClearColor 0.0 0.0 0.0 0.0)
     (glClear (bitwise-ior GL_COLOR_BUFFER_BIT GL_DEPTH_BUFFER_BIT))
     (glUseProgram program)
     (glDrawArrays GL_TRIANGLES 0 3)
     (define pixels (make-bytes (* 16 16 4)))
     (glReadPixels 0 0 16 16 GL_RGBA GL_UNSIGNED_BYTE pixels)
     (unless (> (bytes-ref pixels (+ (* 4 (+ 8 (* 8 16))) 3)) 0)
       (error 'opengl-info "draw/readback triangle did not write the centre pixel"))
     (bytes->immutable-bytes pixels))
   (lambda ()
     (when program (glDeleteProgram program))
     (delete-renderbuffer depth)
     (delete-texture texture)
     (delete-framebuffer framebuffer)
     (delete-buffer buffer)
     (delete-vertex-array vao))))

(define (context-pass)
  (define host (make-gl-context-host))
  (dynamic-wind
   void
   (lambda ()
     (define info (probe-opengl3d-info host))
     (unless (opengl3d-info-supported? info)
       (error 'opengl-info "required OpenGL capabilities are unavailable: ~e"
              (opengl3d-info-required-capabilities info)))
     (define pixels (gl-context-host-call host run-triangle-spike!))
     (hasheq 'capabilities (opengl3d-platform-diagnostics host info)
             'readback-byte-count (bytes-length pixels)
             'readback-centre-rgba
             (for/list ([offset (in-range 4)])
               (bytes-ref pixels (+ (* 4 (+ 8 (* 8 16))) offset)))))
   (lambda () (gl-context-host-close! host))))

(define report
  (hasheq 'stage 'SCENE-3D-P
          'first-context (context-pass)
          ;; Recreating confirms that the host has no global/context-bound
          ;; resource state left behind by the first pass.
          'recreated-context (context-pass)))

(make-parent-directory* output-path)
(call-with-output-file output-path #:exists 'truncate/replace
  (lambda (out) (write report out) (newline out)))
(pretty-write report)
