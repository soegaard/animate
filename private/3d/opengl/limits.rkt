#lang racket/base

;;;
;;; OpenGL Shader and Capability Limits
;;;

;; The GLSL programs use fixed-size uniform arrays. Keep their sizes in this
;; one immutable record: the renderer's preflight report reads it and shader
;; compilation injects the matching #defines after #version. Changing a limit
;; can therefore not make the public capability contract disagree with a
;; silently truncated shader array.

(provide opengl3d-limits
         opengl3d-limit
         opengl3d-capability-limits
         opengl3d-shader-defines)

(define opengl3d-limits
  (hasheq 'directional-lights 4
          'point-lights 8
          'spot-lights 4
          'shadow-maps 8
          'clip-planes 8))

(define (opengl3d-limit name)
  (unless (symbol? name)
    (raise-argument-error 'opengl3d-limit "symbol?" name))
  (hash-ref opengl3d-limits name
            (lambda ()
              (raise-arguments-error 'opengl3d-limit "a known OpenGL limit"
                                     "name" name))))

(define (opengl3d-capability-limits)
  (define directional (opengl3d-limit 'directional-lights))
  (define point (opengl3d-limit 'point-lights))
  (define spot (opengl3d-limit 'spot-lights))
  (hasheq 'maximum-directional-lights directional
          'maximum-point-lights point
          'maximum-spot-lights spot
          'maximum-shadow-lights (opengl3d-limit 'shadow-maps)
          'maximum-clip-planes (opengl3d-limit 'clip-planes)
          'non-ambient-lights (+ directional point spot)))

;; GLSL requires #version to be its first directive. `shader-program.rkt`
;; inserts this complete string immediately after it for every fragment
;; shader, including the depth and shadow passes that consume clip planes.
(define (opengl3d-shader-defines)
  (string-append
   (format "#define ANIMATE_OPENGL_MAX_NON_AMBIENT_LIGHTS ~a\n"
           (hash-ref (opengl3d-capability-limits) 'non-ambient-lights))
   (format "#define ANIMATE_OPENGL_MAX_SHADOW_MAPS ~a\n"
           (opengl3d-limit 'shadow-maps))
   (format "#define ANIMATE_OPENGL_MAX_CLIP_PLANES ~a\n"
           (opengl3d-limit 'clip-planes))))
