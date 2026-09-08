#lang racket/base

;;; SCENE-3D-V release gate: one source of truth for GLSL array limits.

(require racket/file
         racket/runtime-path
         rackunit
         "../private/3d/opengl/limits.rkt")

(define-runtime-path mesh-lit-path "../private/3d/opengl/shaders/mesh-lit.frag")
(define-runtime-path mesh-unlit-path "../private/3d/opengl/shaders/mesh-unlit.frag")
(define-runtime-path depth-path "../private/3d/opengl/shaders/depth.frag")
(define-runtime-path shadow-path "../private/3d/opengl/shaders/shadow.frag")

(module+ test
  (define capability-limits (opengl3d-capability-limits))
  ;; The public preflight and generated GLSL declaration values come from the
  ;; same immutable record.  The total is deliberately derived, not a second
  ;; manually maintained sixteen-light constant.
  (check-equal? (hash-ref capability-limits 'maximum-directional-lights) 4)
  (check-equal? (hash-ref capability-limits 'maximum-point-lights) 8)
  (check-equal? (hash-ref capability-limits 'maximum-spot-lights) 4)
  (check-equal? (hash-ref capability-limits 'non-ambient-lights) 16)
  (check-equal? (hash-ref capability-limits 'maximum-shadow-lights) 8)
  (check-equal? (hash-ref capability-limits 'maximum-clip-planes) 8)
  (check-true (immutable? opengl3d-limits))
  (define defines (opengl3d-shader-defines))
  (for ([expected (in-list
                  '("#define ANIMATE_OPENGL_MAX_NON_AMBIENT_LIGHTS 16"
                    "#define ANIMATE_OPENGL_MAX_SHADOW_MAPS 8"
                    "#define ANIMATE_OPENGL_MAX_CLIP_PLANES 8"))])
    (check-true (regexp-match? (regexp-quote expected) defines)))
  ;; All passes that address the clip array consume the injected declaration;
  ;; the live V CI lane compiles these sources with exactly this preamble.
  (for ([path (in-list (list mesh-lit-path mesh-unlit-path depth-path shadow-path))])
    (check-true
     (regexp-match? #rx"ANIMATE_OPENGL_MAX_CLIP_PLANES" (file->string path))))
  (define lit-source (file->string mesh-lit-path))
  (check-true
   (regexp-match? #rx"ANIMATE_OPENGL_MAX_NON_AMBIENT_LIGHTS" lit-source))
  (check-true
   (regexp-match? #rx"ANIMATE_OPENGL_MAX_SHADOW_MAPS" lit-source)))
