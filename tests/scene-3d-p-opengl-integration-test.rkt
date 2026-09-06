#lang racket/base

;;; SCENE-3D-P: opt-in real-context integration test

;; The ordinary test suite runs in a headless Racket process.  A real GL test
;; is therefore enabled only by ANIMATE_OPENGL_INTEGRATION=1 and is intended to
;; be run under GRacket (macOS) or GRacket/Xvfb (Ubuntu).  Keeping the public
;; backend dynamically required preserves the core test suite's headless path.

(require rackunit
         (only-in racket/math pi)
         racket/file
         racket/path
         racket/runtime-path
         "../3d.rkt"
         "../3d/render.rkt")

(define-runtime-path opengl-module-path "../3d/opengl.rkt")

(define default-test-camera
  (perspective-camera3d #:position (vec3 4 3 7) #:look-at origin3
                        #:vertical-field-of-view (/ pi 5)))

(define (test-view #:camera [camera default-test-camera]
                   #:cube-position [cube-position origin3])
  (view3d
   (list
    (cube3d 2 #:id 'cube
            #:transform (make-transform3 #:translation cube-position)
            #:material (material3d #:color "tomato" #:shading 'smooth))
    (line3d (vec3 -3 -1 0) (vec3 3 -1 0)
            #:id 'line #:style (stroke3d #:color "midnightblue" #:width 4))
    (point3d (vec3 0 1 0) #:id 'point
             #:style (point-style3d #:size 10 #:color "gold"))
    (arrow3d (vec3 -2 0 0) (vec3 2 0 0) #:id 'arrow
             #:tip-style (arrow-style3d #:color "tomato" #:length 12)))
   #:id 'world #:width 4 #:height 3
   #:camera camera
   #:background "aliceblue" #:render-mode 'opaque))

;; This intentionally mixes the P semantic passes that differ most from a
;; plain opaque mesh: a render-only user clip plane and a translucent object.
;; The background remains opaque so the normal final-frame compositing contract
;; (straight ARGB over an ordinary 2D Pict frame) is exercised too.
(define (clipped-transparent-view)
  (view3d
   (list
    (clip3d
     (cube3d 2 #:id 'clipped-cube
             #:material (material3d #:color "slateblue" #:shading 'flat))
     (clip-plane3d (plane3 origin3 x-axis3) #:keep 'positive)
     #:id 'clip)
    (sphere3d 6/5 #:id 'glass
              #:transform (make-transform3 #:translation (vec3 1/2 0 1))
              #:material (material3d #:color "#f0a02099" #:shading 'smooth)))
   #:id 'clip-and-glass #:width 4 #:height 3 #:camera default-test-camera
   #:background "aliceblue" #:render-mode 'opaque))

(define (render-bytes renderer view [width 128] [height 96])
  (define request (view3d->render3d-request view width height))
  (renderer3d-render-result-argb-bytes
   (renderer3d-render renderer (renderer3d-prepare renderer request) request)))

(define (argb-difference-summary expected actual)
  (unless (= (bytes-length expected) (bytes-length actual))
    (raise-arguments-error 'argb-difference-summary "same-sized ARGB byte strings"
                           "expected-bytes" (bytes-length expected)
                           "actual-bytes" (bytes-length actual)))
  (define differences
    (for/list ([expected-byte (in-bytes expected)] [actual-byte (in-bytes actual)])
      (abs (- expected-byte actual-byte))))
  (hasheq 'mean (/ (apply + differences) (length differences))
          'maximum (apply max differences)
          'different-components (length (filter positive? differences))))

(define (check-conform-to-software label expected actual
                                   #:mean-tolerance mean-tolerance
                                   #:maximum-tolerance maximum-tolerance)
  (define summary (argb-difference-summary expected actual))
  ;; OpenGL and the software reference intentionally use different coverage
  ;; rasterizers. Opaque/antialiased marks and transparency therefore have
  ;; distinct documented bounds. A probe writes a full difference image
  ;; whenever visual diagnosis is needed.
  (check-true (<= (hash-ref summary 'mean) mean-tolerance)
              (format "~a mean ARGB difference: ~e" label (hash-ref summary 'mean)))
  (check-true (<= (hash-ref summary 'maximum) maximum-tolerance)
              (format "~a maximum ARGB difference: ~e" label (hash-ref summary 'maximum)))
  (when (equal? (getenv "ANIMATE_OPENGL_INTEGRATION_DEBUG") "1")
    (displayln (list label summary))))

(module+ test
  (when (equal? (getenv "ANIMATE_OPENGL_INTEGRATION") "1")
    (define make-renderer (dynamic-require opengl-module-path 'opengl-renderer3d))
    (define renderer? (dynamic-require opengl-module-path 'opengl-renderer3d?))
    (define available? (dynamic-require opengl-module-path 'opengl-renderer3d-available?))
    (define renderer-info (dynamic-require opengl-module-path 'opengl-renderer3d-info))
    (define renderer-statistics (dynamic-require opengl-module-path 'opengl-renderer3d-statistics))
    (define renderer-release! (dynamic-require opengl-module-path 'opengl-renderer3d-release!))
    (check-true (available?))
    (define renderer (make-renderer))
    (define baseline-bytes #f)
    (dynamic-wind
     void
     (lambda ()
       (check-true (renderer? renderer))
       (check-eq? (renderer3d-id renderer) 'opengl-racket)
       (check-true (hash? (renderer-info renderer)))
       (define request (view3d->render3d-request (test-view) 128 96))
       (define preparation (renderer3d-prepare renderer request))
       (define first (renderer3d-render renderer preparation request))
       (define second (renderer3d-render renderer preparation request))
       (check-equal? (renderer3d-render-result-width first) 128)
       (check-equal? (renderer3d-render-result-height first) 96)
       (check-equal? (bytes-length (renderer3d-render-result-argb-bytes first)) (* 4 128 96))
       ;; Identical random-access requests have a stable frame result. The
       ;; image need not be bit-identical to the software antialiasing oracle.
       (check-equal? (renderer3d-render-result-argb-bytes second)
                     (renderer3d-render-result-argb-bytes first))
       (set! baseline-bytes (renderer3d-render-result-argb-bytes first))
       (define software (software-renderer3d))
       (check-conform-to-software
        'opaque-strokes-and-markers
        (render-bytes software (test-view))
        baseline-bytes #:mean-tolerance 1 #:maximum-tolerance 160)
       (check-conform-to-software
        'clipping-and-transparency
        (render-bytes software (clipped-transparent-view))
        (render-bytes renderer (clipped-transparent-view))
        #:mean-tolerance 3 #:maximum-tolerance 160)
       (define statistics (renderer-statistics renderer))
       (check-equal? (hash-ref statistics 'backend) 'opengl-racket)
       (check-equal? (hash-ref (hash-ref statistics 'framebuffer-cache) 'allocations) 1)
       (define first-uploads
         (hash-ref (hash-ref statistics 'geometry-cache) 'uploads))
       (check-true (positive? first-uploads))
       ;; A new camera changes uniform/frame preparation only. A moved object
       ;; has a new instance transform but the same immutable cube geometry.
       (render-bytes renderer
                     (test-view #:camera
                                (perspective-camera3d #:position (vec3 -4 3 7)
                                                      #:look-at origin3
                                                      #:vertical-field-of-view (/ pi 5))))
       (render-bytes renderer (test-view #:cube-position (vec3 1 0 0)))
       (define warm-statistics (renderer-statistics renderer))
       (check-equal? (hash-ref (hash-ref warm-statistics 'geometry-cache) 'uploads)
                     first-uploads)
       (check-equal? (hash-ref (hash-ref warm-statistics 'framebuffer-cache) 'allocations) 1))
     (lambda () (renderer-release! renderer)))

    ;; A restart gives every resource a new context generation. Recreating the
    ;; renderer must still produce the same random-access result; no GLuint or
    ;; stale framebuffer may escape the previous owned context.
    (define restarted-renderer (make-renderer))
    (dynamic-wind
     void
     (lambda ()
       (define request (view3d->render3d-request (test-view) 128 96))
       (define preparation (renderer3d-prepare restarted-renderer request))
       (define restarted (renderer3d-render restarted-renderer preparation request))
       (check-equal? (renderer3d-render-result-argb-bytes restarted) baseline-bytes))
     (lambda () (renderer-release! restarted-renderer)))
  ))
