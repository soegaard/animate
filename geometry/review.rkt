#lang racket/base

;; Sparse review rendering: reuse the native geometry renderer, fonts, camera,
;; colors, and the complete timeline's frozen annotation layout. This module
;; writes only three images per step; it never renders or encodes a full video.
(require racket/class racket/format
         (only-in pict pict->bitmap)
         (prefix-in a: "../main.rkt")
         "main.rkt" "review-plan.rkt"
         "private/review-bundle.rkt" "private/review-contact-sheet.rkt")
(provide render-geometry-review! (struct-out geometry-review-result)
         (all-from-out "review-plan.rkt"))

(define (render-geometry-review! timeline directory
                                  #:name [name (symbol->string
                                                (geometry-program-name
                                                 (geometry-realization-program
                                                  (geometry-timeline-realization timeline))))]
                                  #:width [width 1280] #:height [height 720]
                                  #:fps [fps 30] #:supersample [supersample 1]
                                  #:color-theme [color-theme #f] #:theme-name [theme-name "light"]
                                  #:captions? [captions? #t] #:labels [labels (hash)]
                                  #:expanded? [expanded? #t] #:contact-sheet? [contact-sheet? #t]
                                  #:zip [zip-path #f])
  (unless (and (geometry-timeline? timeline) (exact-positive-integer? width)
               (exact-positive-integer? height) (exact-positive-integer? fps)
               (exact-positive-integer? supersample) (boolean? contact-sheet?)
               (boolean? captions?) (boolean? expanded?))
    (error 'render-geometry-review! "invalid timeline or review options"))
  (define plan (make-geometry-review-plan timeline #:expanded? expanded?))
  (define visual-at (geometry-timeline->visual-sampler timeline #:width width
                                                       #:captions? captions? #:labels labels))
  (define camera (geometry-timeline->camera timeline #:width width #:height height))
  (define base-scene (a:make-scene #:camera camera))
  (define (render-one! sample path)
    ;; Explicit boundary states matter when a step has no read delay or final
    ;; pause. Sampling the movie at the end would already show the next caption.
    (define scene (a:scene-add base-scene (visual-at (geometry-review-sample-frame sample))))
    (define image (pict->bitmap (a:scene->pict scene 0 #:theme color-theme
                                             #:supersample supersample) 'smoothed))
    (unless (send image save-file path 'png)
      (error 'render-geometry-review! "could not save ~a" path)))
  (write-geometry-review-bundle!
   timeline plan directory #:name name #:theme theme-name
   #:width width #:height height #:fps fps #:supersample supersample
   #:captions? captions? #:expanded? expanded? #:zip zip-path #:render-sample! render-one!
   #:contact-sheets!
   (and contact-sheet?
        (lambda (rows staging)
          (write-review-contact-sheets! rows staging #:name name #:theme theme-name
                                        #:aspect (/ width height))))))
