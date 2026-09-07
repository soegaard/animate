#lang racket/base

;;;
;;; Textured Billboard Submission
;;;

;; Billboard geometry is prepared once by the backend-neutral software module.
;; This OpenGL bridge consumes those exact screen/world corners and uploads the
;; immutable ARGB image as a short-lived RGBA texture.  Keeping the source in
;; the authoring value avoids a process-global texture cache and makes preview
;; workers and final renders observe identical sprite content.

(require racket/list
         ffi/vector
         "../billboard-raster3d.rkt"
         "../billboard3d.rkt"
         "../camera3d.rkt"
         "../compiled-view3d.rkt"
         "../vec3.rkt"
         "api.rkt"
         "matrix-pack.rkt"
         "shader-program.rkt")

(provide prepare-opengl-billboards
         gl-draw-billboards/current!)

(define floats-per-vertex 6) ; clip xyzw plus uv

(define (prepare-opengl-billboards compiled frame-spec)
  (unless (compiled-view3d? compiled)
    (raise-argument-error 'prepare-opengl-billboards "compiled-view3d?" compiled))
  (unless (frame3d-spec? frame-spec)
    (raise-argument-error 'prepare-opengl-billboards "frame3d-spec?" frame-spec))
  (define camera (frame3d-spec-camera frame-spec))
  (define width (frame3d-spec-width frame-spec))
  (define height (frame3d-spec-height frame-spec))
  (define aspect (/ width height))
  (filter values
          (for/list ([billboard (in-vector (compiled-view3d-billboards compiled))])
            (prepare-billboard3d
             (compiled-billboard3d-path billboard)
             (compiled-billboard3d-position billboard)
             (compiled-billboard3d-world-transform billboard)
             (compiled-billboard3d-image billboard)
             (compiled-billboard3d-style billboard)
             (compiled-billboard3d-opacity billboard)
             (compiled-billboard3d-clip-planes billboard)
             camera aspect width height (compiled-billboard3d-drawing-index billboard)))))

;; Must be called in a current GL context.  `mode` intentionally has the same
;; three meanings as strokes and markers, so translucent image pixels never
;; change the opaque scene depth buffer.
(define (gl-draw-billboards/current! program billboards mode camera width height)
  (unless (gl-shader-program? program)
    (raise-argument-error 'gl-draw-billboards/current! "gl-shader-program?" program))
  (unless (memq mode '(hidden test always))
    (raise-argument-error 'gl-draw-billboards/current! "billboard depth mode" mode))
  (for ([billboard (in-list billboards)]
        #:when (eq? (billboard-style3d-depth-mode
                     (prepared-billboard3d-style billboard))
                    mode))
    (draw-billboard/current! program billboard mode camera width height)))

(define (draw-billboard/current! program billboard mode camera width height)
  (define vertices (prepared-billboard3d-vertices billboard))
  (define packed
    (apply f32vector (map finite-real->float32
           (append (clip-vertex (first vertices) camera width height)
                   (clip-vertex (second vertices) camera width height)
                   (clip-vertex (third vertices) camera width height)
                   (clip-vertex (first vertices) camera width height)
                   (clip-vertex (third vertices) camera width height)
                   (clip-vertex (fourth vertices) camera width height)))))
  (define image (prepared-billboard3d-image billboard))
  (define rgba (argb->rgba (billboard-image3d-argb image)))
  (define vao (u32vector-ref (glGenVertexArrays 1) 0))
  (define buffer (u32vector-ref (glGenBuffers 1) 0))
  (define texture (u32vector-ref (glGenTextures 1) 0))
  (dynamic-wind
   void
   (lambda ()
     (glUseProgram (gl-shader-program-id program))
     (glBindVertexArray vao)
     (glBindBuffer GL_ARRAY_BUFFER buffer)
     (glBufferData GL_ARRAY_BUFFER (* 4 (f32vector-length packed)) packed GL_STREAM_DRAW)
     (define stride (* floats-per-vertex 4))
     (glEnableVertexAttribArray 0)
     (glVertexAttribPointer 0 4 GL_FLOAT #f stride 0)
     (glEnableVertexAttribArray 1)
     (glVertexAttribPointer 1 2 GL_FLOAT #f stride (* 4 4))
     (glActiveTexture GL_TEXTURE0)
     (glBindTexture GL_TEXTURE_2D texture)
     (glPixelStorei GL_UNPACK_ALIGNMENT 1)
     (glTexImage2D GL_TEXTURE_2D 0 GL_RGBA8
                   (billboard-image3d-width image) (billboard-image3d-height image)
                   0 GL_RGBA GL_UNSIGNED_BYTE rgba)
     (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_NEAREST)
     (glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_NEAREST)
     (uniform-1i! program "billboardTexture" 0)
     (uniform-1f! program "billboardOpacity" (prepared-billboard3d-opacity billboard))
     (glDisable GL_CULL_FACE)
     (glEnable GL_BLEND)
     ;; The fragment shader writes premultiplied RGBA, matching the viewport
     ;; target and the main transparent mesh pass.
     (glBlendFunc GL_ONE GL_ONE_MINUS_SRC_ALPHA)
     (glDepthMask #f)
     (case mode
       [(hidden) (glEnable GL_DEPTH_TEST) (glDepthFunc GL_GREATER)]
       [(test) (glEnable GL_DEPTH_TEST) (glDepthFunc GL_LEQUAL)]
       [(always) (glDisable GL_DEPTH_TEST)])
     (when (memq mode '(hidden test))
       (glEnable GL_POLYGON_OFFSET_FILL)
       (define bias (billboard-style3d-depth-bias (prepared-billboard3d-style billboard)))
       (glPolygonOffset (if (eq? mode 'hidden) bias (- bias))
                        (if (eq? mode 'hidden) bias (- bias))))
     (glDrawArrays GL_TRIANGLES 0 6)
     (glDisable GL_POLYGON_OFFSET_FILL)
     (glDepthMask #t)
     (glDisable GL_BLEND)
     (glBindTexture GL_TEXTURE_2D 0)
     (glBindVertexArray 0)
     (glUseProgram 0))
   (lambda ()
     (when (positive? texture) (glDeleteTextures 1 (u32vector texture)))
     (when (positive? buffer) (glDeleteBuffers 1 (u32vector buffer)))
     (when (positive? vao) (glDeleteVertexArrays 1 (u32vector vao))))))

(define (clip-vertex vertex camera width height)
  (define clip
    (gl-matrix4-apply-point
     (camera3d-view-projection-matrix camera (/ width height))
     (prepared-billboard-vertex3d-world vertex)))
  (define clip-w (vector-ref clip 3))
  (list (* (- (* 2.0 (/ (prepared-billboard-vertex3d-x vertex) width)) 1.0) clip-w)
        (* (- 1.0 (* 2.0 (/ (prepared-billboard-vertex3d-y vertex) height))) clip-w)
        (vector-ref clip 2)
        clip-w
        (prepared-billboard-vertex3d-u vertex)
        (prepared-billboard-vertex3d-v vertex)))

(define (argb->rgba argb)
  (define result (make-bytes (bytes-length argb)))
  (for ([index (in-range 0 (bytes-length argb) 4)])
    (bytes-set! result index (bytes-ref argb (add1 index)))
    (bytes-set! result (add1 index) (bytes-ref argb (+ index 2)))
    (bytes-set! result (+ index 2) (bytes-ref argb (+ index 3)))
    (bytes-set! result (+ index 3) (bytes-ref argb index)))
  result)

(define (uniform/current program name)
  (hash-ref! (gl-shader-program-uniforms program) name
             (lambda () (glGetUniformLocation (gl-shader-program-id program) name))))

(define (uniform-1f! program name value)
  (define location (uniform/current program name))
  (when (>= location 0) (glUniform1f location (exact->inexact value))))

(define (uniform-1i! program name value)
  (define location (uniform/current program name))
  (when (>= location 0) (glUniform1i location value)))
