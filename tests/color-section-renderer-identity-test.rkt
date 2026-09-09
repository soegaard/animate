#lang racket/base

;;; Persistent section caching requires declared renderer semantics

(require racket/class
         racket/draw
         racket/file
         racket/port
         rackunit
         (only-in pict filled-ellipse)
         "../authoring.rkt"
         "../main.rkt"
         (only-in "../private/latex-formula-pict-renderer.rkt"
                  default-latex-formula-pict-renderer)
         (only-in "../3d/render.rkt"
                  current-view3d-renderer3d
                  software-renderer3d)
         "../render.rkt")

(struct opaque-circle-renderer (colour)
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual) (circle-visual? visual))
   (define (pict-renderer-render renderer _visual _camera)
     (filled-ellipse 40 40 #:draw-border? #f #:color (opaque-circle-renderer-colour renderer)))])

(struct identified-circle-renderer (colour identity)
  #:transparent
  #:property prop:pict-renderer-cache-identity
  (lambda (renderer) (identified-circle-renderer-identity renderer))
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual) (circle-visual? visual))
   (define (pict-renderer-render renderer _visual _camera)
     (filled-ellipse 40 40 #:draw-border? #f #:color (identified-circle-renderer-colour renderer)))])

(define (center-argb path)
  (define bitmap (read-bitmap path))
  (define pixels (make-bytes 4))
  (send bitmap get-argb-pixels 40 30 1 1 pixels)
  (bytes->immutable-bytes pixels))

(define timeline
  (make-authored-timeline
   (scene-wait
    (scene-add
     (make-scene #:camera (make-camera #:width 80 #:height 60 #:world-width 4))
     (circle #:id 'dot #:radius 1))
    1)
   #:sections (list (section 'only 0 1))))

(module+ test
  (define root (make-temporary-file "animate-renderer-identity-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     ;; The built-in formula renderer has a stable adapter identity.  Formula
     ;; source and camera state are already represented in the section key;
     ;; users can clear the persistent cache after changing their TeX setup.
     (check-equal?
      (pict-renderer-cache-identity default-latex-formula-pict-renderer)
      '(latex-formula-pict-renderer-v1))
     ;; An opaque custom renderer is always renderable, but never persisted.
     (define opaque (list (opaque-circle-renderer "red")))
     (check-false
      (section-render-report-cache-hit?
       (render-timeline-section/report! timeline 'only root #:fps 1
                                       #:renderers opaque #:cache-key 'source)))
     (check-false
      (section-render-report-cache-hit?
       (render-timeline-section/report! timeline 'only root #:fps 1
                                       #:renderers opaque #:cache-key 'source)))
     ;; Declared immutable identities allow reuse, but changing that declared
     ;; appearance configuration must miss even with the same caller key.
     (define red (list (identified-circle-renderer "red" '(test-circle-v1 red))))
     (define blue (list (identified-circle-renderer "blue" '(test-circle-v1 blue))))
     (define red-first
       (render-timeline-section/report! timeline 'only root #:fps 1
                                       #:renderers red #:cache-key 'source))
     (define red-pixel (center-argb (car (section-render-report-paths red-first))))
     (check-false (section-render-report-cache-hit? red-first))
     (check-true
      (section-render-report-cache-hit?
       (render-timeline-section/report! timeline 'only root #:fps 1
                                       #:renderers red #:cache-key 'source)))
     (define blue-first
       (render-timeline-section/report! timeline 'only root #:fps 1
                                       #:renderers blue #:cache-key 'source))
     (check-false (section-render-report-cache-hit? blue-first))
     (check-not-equal? red-pixel
                       (center-argb (car (section-render-report-paths blue-first))))
     ;; Camera identity is a versioned reader datum, not the transparent
     ;; camera struct.  An equivalent reconstruction therefore finds the
     ;; manifest, while every pixel-affecting view change misses.
     (define camera-a
       (make-camera #:width 80 #:height 60 #:world-width 4
                    #:center (vec2 1 2) #:background "white"))
     (define camera-first
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:renderers red #:camera camera-a
        #:cache-key 'camera-source))
     (check-false (section-render-report-cache-hit? camera-first))
     (define camera-manifest
       (call-with-input-file
        (build-path root ".animate-section-cache.rktd") read))
     (define manifest-round-trip
       (call-with-output-bytes
        (lambda (out) (write camera-manifest out))))
     (check-equal? (read (open-input-bytes manifest-round-trip)) camera-manifest)
     (check-true
      (section-render-report-cache-hit?
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:renderers red
        #:camera (make-camera #:width 80 #:height 60 #:world-width 4
                              #:center (vec2 1 2) #:background "white")
        #:cache-key 'camera-source)))
     (for ([changed-camera
            (in-list
             (list (make-camera #:width 80 #:height 60 #:world-width 4
                                #:center (vec2 2 2) #:background "white")
                   (make-camera #:width 80 #:height 60 #:world-width 5
                                #:center (vec2 1 2) #:background "white")
                   (make-camera #:width 81 #:height 60 #:world-width 4
                                #:center (vec2 1 2) #:background "white")
                   (make-camera #:width 80 #:height 61 #:world-width 4
                                #:center (vec2 1 2) #:background "white")))])
       (check-false
        (section-render-report-cache-hit?
         (render-timeline-section/report!
          timeline 'only root #:fps 1 #:renderers red #:camera changed-camera
          #:cache-key 'camera-source))))
     ;; The built-in renderer list includes the opaque view3d adapter. Its
     ;; dynamic backend is part of the render identity, even when this tiny
     ;; scene happens not to contain a viewport. That conservatively prevents
     ;; an explicit source key from crossing software/OpenGL-style boundaries.
     (define built-in-first
       (render-timeline-section/report! timeline 'only root #:fps 1
                                       #:cache-key 'backend-source))
     (check-false (section-render-report-cache-hit? built-in-first))
     (check-false
      (section-render-report-cache-hit?
       (parameterize ([current-view3d-renderer3d (software-renderer3d)])
         (render-timeline-section/report! timeline 'only root #:fps 1
                                         #:cache-key 'backend-source)))) )
   (lambda () (delete-directory/files root))))
