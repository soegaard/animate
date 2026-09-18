#lang racket/base

;; Export genuine Animate renders for numerical SVG inspection. No TeX/FFmpeg.
(require racket/class racket/cmdline racket/file racket/list racket/path
         racket/runtime-path json file/sha1
         (only-in pict draw-pict pict->bitmap pict-width pict-height)
         (only-in racket/draw svg-dc%)
         (only-in "../main.rkt" scene-add make-scene make-camera scene->pict
                  circle rectangle vec2))

(define-runtime-path blocks-source "../scribblings/examples/source-blocks.rkt")
(define-runtime-path shape-source "../private/shape-pict-renderers.rkt")
(define-runtime-path smoothing-source "../private/shape-smoothing.rkt")

(define (save-svg p path mode)
  (define target
    (new svg-dc% [width (pict-width p)] [height (pict-height p)]
         [output path] [exists 'error]))
  (send target start-doc "Animate shape-alignment regression")
  (send target start-page)
  ;; 'default reproduces the user's exporter, with NO set-smoothing call.
  (unless (eq? mode 'default) (send target set-smoothing mode))
  (define before (send target get-smoothing))
  (draw-pict p target 0 0)
  (unless (eq? before (send target get-smoothing))
    (error 'probe-shape-alignment "shape renderer leaked the DC smoothing mode"))
  (send target end-page)
  (send target end-doc))

(define (expected-bounds w h x y width height)
  (define unit (/ w 14))
  (define cx (+ (/ w 2) (* x unit)))
  (define cy (- (/ h 2) (* y unit)))
  (map exact->inexact
       (list (- cx (* unit width 1/2)) (- cy (* unit height 1/2))
             (+ cx (* unit width 1/2)) (+ cy (* unit height 1/2)))))

(module+ main
  (define output
    (command-line #:program "tools/probe-shape-alignment.rkt"
                  #:args (destination) (path->complete-path destination)))
  (when (or (file-exists? output) (directory-exists? output) (link-exists? output))
    (raise-user-error 'probe-shape-alignment "use a fresh output directory: ~a" output))
  (make-directory* output)
  (define results '())
  (define (capture id p expected stroke-width)
    (for ([mode '(default unsmoothed aligned smoothed)])
      (define stem (format "~a-~a" id mode))
      (define svg-name (string-append stem ".svg"))
      (define png-name (string-append stem ".png"))
      (save-svg p (build-path output svg-name) mode)
      (define bm (if (eq? mode 'default) (pict->bitmap p) (pict->bitmap p mode)))
      (unless (send bm save-file (build-path output png-name) 'png)
        (error 'probe-shape-alignment "could not save ~a" png-name))
      (set! results
            (cons (hasheq 'id id 'mode (symbol->string mode)
                          'svg svg-name 'png png-name 'bounds expected
                          'stroke-width stroke-width
                          'width (pict-width p) 'height (pict-height p))
                  results))))
  (for ([size '((160 90) (640 360) (1280 720))])
    (define w (car size))
    (define h (cadr size))
    (define camera (make-camera #:width w #:height h #:world-width 14))
    (define (picture visual)
      (scene->pict (scene-add (make-scene #:camera camera) visual) 0))
    (capture (format "circle-~a" w)
             (picture (circle #:id 'dot #:center (vec2 0 0) #:radius 1/2
                              #:fill "tomato" #:stroke "firebrick" #:stroke-width 2))
             (expected-bounds w h 0 0 1 1) 2)
    (capture (format "fractional-circle-~a" w)
             (picture (circle #:id 'dot #:center (vec2 1/7 1/11) #:radius 1/2
                              #:fill "tomato" #:stroke "firebrick" #:stroke-width 3/2))
             (expected-bounds w h 1/7 1/11 1 1) 1.5)
    (capture (format "rectangle-~a" w)
             (picture (rectangle #:id 'box #:center (vec2 1/7 1/11)
                                 #:width 1 #:height 3/4 #:fill "tomato"
                                 #:stroke "firebrick" #:stroke-width 2))
             (expected-bounds w h 1/7 1/11 1 3/4) 2))
  ;; The actual program used by complete-source-blocks.html, not a reconstruction.
  (define animation (dynamic-require blocks-source 'animation))
  (for ([time '(0 2 4)] [x '(-3 0 3)])
    (capture (format "source-blocks-t~a" time)
             (scene->pict animation time
                          #:camera (make-camera #:width 640 #:height 360 #:world-width 14))
             (expected-bounds 640 360 x 0 1 1) 2))
  (call-with-output-file (build-path output "manifest.json")
    (lambda (port)
      (write-json
       (hasheq 'schema "animate-shape-alignment-probe-v1"
               'racket (version) 'platform (format "~a" (system-type))
               'sources
               (hasheq 'source-blocks (call-with-input-file blocks-source sha1)
                       'shape-renderer (call-with-input-file shape-source sha1)
                       'smoothing (call-with-input-file smoothing-source sha1))
               'cases (reverse results)) port)))
  (printf "Wrote ~a genuine SVG/PNG pairs to ~a\n" (length results) output))
