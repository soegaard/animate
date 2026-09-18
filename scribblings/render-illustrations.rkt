#lang racket/base

;; Rebuild the manual's frame strips from the displayed examples and galleries.
;; Rendering is explicit. A Scribble build only reads the checked-in pictures.
(require racket/class racket/cmdline racket/file racket/list racket/path racket/runtime-path
         file/sha1 json
         (only-in pict pict->bitmap)
         (only-in animate scene? scene-duration scene-sample scene-camera-at scene-state->pict
                  make-camera)
         animate/slides animate/slides/pict animate/slides/render animate/slides/gallery
         "../slides/examples/gallery.rkt")
(define-runtime-path examples "examples")
(define-runtime-path source-catalogue "figures/illustrations.json")
(define (theme name) (if (equal? name "lecture-light") lecture-light lecture-dark))
(define (format-value name)
  (case (string->symbol name)
    [(widescreen) widescreen] [(standard) standard] [(portrait) portrait]
    [(square) square-format]
    [else (raise-user-error 'render-illustrations "unknown format: ~a" name)]))
(define (at-boundary time end)
  (cond [(< (abs time) 1e-10) 0]
        [(< (abs (- time end)) 1e-9) end]
        [else time]))
(define (load-source spec)
  (define recipe (hash-ref spec 'recipe))
  (cond
    [(equal? (hash-ref recipe 'type) "static-layout") #f]
    [(equal? (hash-ref recipe 'type) "gallery-variants") #f]
    [(equal? (hash-ref recipe 'type) "example")
     (dynamic-require (build-path examples (hash-ref recipe 'module))
                      (string->symbol (hash-ref recipe 'binding)))]
    [(and (string? (hash-ref recipe 'example #f))
          (not (equal? (hash-ref recipe 'example) "transition-gallery.rkt")))
     (dynamic-require (build-path examples (hash-ref recipe 'example)) 'film)]
    [else (make-slide-gallery #:entries (list (string->symbol (hash-ref recipe 'entry)))
                              #:theme (theme (hash-ref recipe 'theme "lecture-dark")))]))
(define (render-one spec source frame index)
  (define recipe (hash-ref spec 'recipe))
  (define type (hash-ref recipe 'type))
  (define size (list (hash-ref frame 'width) (hash-ref frame 'height)))
  (define time (hash-ref frame 'time))
  (cond
    [(equal? type "static-layout")
     (define variant (list-ref (hash-ref recipe 'variants) index))
     (define card
       (findf (lambda (card) (eq? (slide-id card) (string->symbol (hash-ref recipe 'id))))
              gallery-slides))
     (unless card (raise-user-error 'render-illustrations "missing layout example"))
     (slide->pict card #:theme (theme (car variant)) #:format (format-value (cadr variant)) #:size size)]
    [(equal? type "gallery-variants")
     (define variant (list-ref (hash-ref recipe 'variants) index))
     (define board
       (prepare-storyboard!
        (make-slide-gallery #:entries (list (string->symbol (hash-ref recipe 'entry)))
                            #:theme (theme (car variant)) #:format (format-value (cadr variant)))))
     (storyboard->pict board #:at (at-boundary time (prepared-duration board)) #:size size)]
    [(scene? source)
     (define t (at-boundary time (scene-duration source)))
     ;; The Quick Start has a stationary default camera: world width 14.
     ;; Regenerated pictures are ordinary PNGs rather than the old SVG crops.
     (scene-state->pict (scene-sample source t)
                       #:camera (make-camera #:width (car size) #:height (cadr size) #:world-width 14))]
    [else (storyboard->pict source #:at (at-boundary time (prepared-duration source)) #:size size)]))

(module+ main
  (define selected '())
  (define destination
    (command-line #:program "scribblings/render-illustrations.rkt"
      #:multi
      [("--strip") key "Render one strip; repeat for more" (set! selected (append selected (list key)))]
      #:args ([directory "slides-output/manual-illustrations"]) directory))
  (define out (path->complete-path destination))
  (when (or (directory-exists? out) (file-exists? out))
    (raise-user-error 'render-illustrations "choose a new output directory: ~a" out))
  (define catalogue (call-with-input-file source-catalogue read-json))
  (define strips (hash-ref catalogue 'strips))
  (define keys (if (null? selected) (sort (map symbol->string (hash-keys strips)) string<?) selected))
  (for ([key (in-list keys)])
    (unless (hash-has-key? strips (string->symbol key))
      (raise-user-error 'render-illustrations "unknown strip: ~a" key)))
  (make-directory* out)
  (define rendered
    (for/hash ([key (in-list keys)])
      (define spec (hash-ref strips (string->symbol key)))
      (define source0 (load-source spec))
      (define source (if (storyboard? source0) (prepare-storyboard! source0) source0))
      (define frames
        (for/list ([frame (in-list (hash-ref spec 'frames))] [i (in-naturals)])
          (define file (format "manual-~a-~a.png" key i))
          (define path (build-path out file))
          (define bm (pict->bitmap (render-one spec source frame i) 'smoothed))
          (unless (send bm save-file path 'png) (error 'render-illustrations "could not save ~a" path))
          ;; This is a fresh render, not another copy of the old review frame.
          (hash 'file file 'caption (hash-ref frame 'caption) 'time (hash-ref frame 'time)
                'width (send bm get-width) 'height (send bm get-height)
                'sha1 (call-with-input-file path sha1))))
      (printf "~a: ~a frames\n" key (length frames))
      (values (string->symbol key) (hash-set spec 'frames frames))))
  (call-with-output-file (build-path out "illustrations.json") #:exists 'error
    (lambda (port)
      (write-json (hash 'schema "animate-manual-illustrations-v1"
                        'origin (hash 'racket (version)
                                      'drawing-policy "animate-shapes-smoothed-v1" 'note "Regenerated from manual examples; review before replacing checked-in illustrations.")
                        'strips rendered) port)))
  (displayln "Fresh pictures and their catalogue are ready for review. No checked-in files were replaced."))
