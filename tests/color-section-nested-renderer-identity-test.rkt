#lang racket/base

;;; Nested Pict dispatch must not make an opaque renderer cacheable

(require racket/class
         racket/draw
         racket/file
         rackunit
         (only-in pict filled-ellipse)
         "../authoring.rkt"
         "../main.rkt"
         "../render.rkt")

(struct opaque-circle-renderer (colour)
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual) (circle-visual? visual))
   (define (pict-renderer-render renderer _visual _camera)
     (filled-ellipse 40 40 #:draw-border? #f
                     #:color (opaque-circle-renderer-colour renderer)))])

(struct identified-circle-renderer (colour identity)
  #:transparent
  #:property prop:pict-renderer-cache-identity
  (lambda (renderer) (identified-circle-renderer-identity renderer))
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual) (circle-visual? visual))
   (define (pict-renderer-render renderer _visual _camera)
     (filled-ellipse 40 40 #:draw-border? #f
                     #:color (identified-circle-renderer-colour renderer)))])

(define camera
  (make-camera #:width 80 #:height 60 #:world-width 4 #:background "white"))

(define (timeline-for visual)
  (make-authored-timeline
   (scene-wait (scene-add (make-scene #:camera camera) visual) 1)
   #:sections (list (section 'only 0 1))))

(define (center-argb path)
  (define bitmap (read-bitmap path))
  (define pixels (make-bytes 4))
  (send bitmap get-argb-pixels 40 30 1 1 pixels)
  (bytes->immutable-bytes pixels))

(define (opaque-renderers colour)
  (cons (opaque-circle-renderer colour) default-pict-renderers))

(module+ test
  (define root (make-temporary-file "animate-nested-renderer-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define leaf (circle #:id 'dot #:radius 1))
     (define nested (group (list leaf) #:id 'nested))
     (define nested-timeline (timeline-for nested))

     ;; Actual Pict lowering reaches the group's child and selects the opaque
     ;; renderer. Red and blue therefore produce different fresh pixels, but
     ;; neither render is allowed to write or reuse a persistent manifest.
     (define red
       (render-timeline-section/report!
        nested-timeline 'only root #:fps 1
        #:renderers (opaque-renderers "red") #:cache-key 'nested-source))
     (define red-pixel (center-argb (car (section-render-report-paths red))))
     (check-false (section-render-report-cache-hit? red))
     (define blue
       (render-timeline-section/report!
        nested-timeline 'only root #:fps 1
        #:renderers (opaque-renderers "blue") #:cache-key 'nested-source))
     (check-false (section-render-report-cache-hit? blue))
     (check-not-equal? red-pixel
                       (center-argb (car (section-render-report-paths blue))))

     ;; The conservative rule applies to every supplied opaque renderer,
     ;; including each representative composite path through the Pict adapter.
     (define left-half
       (polygon-path (list (vec2 -2 -2) (vec2 0 -2)
                           (vec2 0 2) (vec2 -2 2))))
     (for ([visual
            (in-list
             (list leaf
                   nested
                   (clip-visual nested left-half #:id 'clipped)
                   (affine-map leaf identity-affine2)))])
       (define timeline (timeline-for visual))
       (define first
         (render-timeline-section/report!
          timeline 'only root #:fps 1 #:renderers (opaque-renderers "red")
          #:cache-key (visual-id visual)))
       (check-false (section-render-report-cache-hit? first))
       (check-false
        (section-render-report-cache-hit?
         (render-timeline-section/report!
          timeline 'only root #:fps 1 #:renderers (opaque-renderers "red")
          #:cache-key (visual-id visual)))))

     ;; A renderer with an explicit identity still benefits from persistent
     ;; reuse. Changing that identity must invalidate the same source key.
     (define identified-red
       (cons (identified-circle-renderer "red" '(nested-circle-v1 red))
             default-pict-renderers))
     (define identified-blue
       (cons (identified-circle-renderer "blue" '(nested-circle-v1 blue))
             default-pict-renderers))
     (define identified-first
       (render-timeline-section/report!
        nested-timeline 'only root #:fps 1 #:renderers identified-red
        #:cache-key 'identified-nested-source))
     (check-false (section-render-report-cache-hit? identified-first))
     (check-true
      (section-render-report-cache-hit?
       (render-timeline-section/report!
        nested-timeline 'only root #:fps 1 #:renderers identified-red
        #:cache-key 'identified-nested-source)))
     (check-false
      (section-render-report-cache-hit?
       (render-timeline-section/report!
        nested-timeline 'only root #:fps 1 #:renderers identified-blue
        #:cache-key 'identified-nested-source))))
   (lambda () (delete-directory/files root))))
