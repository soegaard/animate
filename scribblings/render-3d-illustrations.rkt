#lang racket/base
;; Explicit rendering step, separate from building the manual. No TeX or FFmpeg.
(require racket/class racket/cmdline racket/file racket/list racket/path
         racket/runtime-path file/sha1 json
         (only-in pict pict->bitmap)
         animate animate/3d
         animate/slides/pict animate/slides/render
         "private/three-d-catalog.rkt"
         "private/image-export.rkt")
(define-runtime-path examples "examples")
(define-runtime-path installed "figures/3d-r3")
(define-runtime-path root "..")
(define width 640)
(define height 360)
(define (file-sha1 path) (call-with-input-file path sha1))
(define (source-snapshot)
  ;; `read-json` restores object keys as symbols in an immutable `hasheq`.
  ;; Match both representations so a verified installed manifest compares equal.
  (for/hasheq ([name (in-list three-d-example-files)])
    (values (string->symbol name) (file-sha1 (build-path examples name)))))
(define (scene-picture sc time)
  ;; These lessons use a fixed outer camera. Its pixel dimensions may be changed
  ;; for documentation without changing spatial cameras, view sizes, or timing.
  (define old (scene-camera-at sc time))
  (define camera
    (make-camera #:width width #:height height
                 #:center (camera-center old)
                 #:world-width (camera-world-width old)))
  (scene-state->pict (scene-sample sc time) #:camera camera))
(module+ main
  (define install? #f)
  (define output #f)
  (command-line
   #:program "render-3d-illustrations.rkt"
   #:once-each
   [("--install") "Create the captures used by the manual" (set! install? #t)]
   #:args ([directory #f]) (set! output directory))
  (when (and install? output)
    (raise-user-error 'render-3d-illustrations "use --install or an output directory, not both"))
  (define target
    (if install? installed
        (path->complete-path (or output "slides-output/manual-3d-frames"))))
  (define sources (source-snapshot))
  (define manifest-path (build-path target "manifest.json"))
  (when (link-exists? target)
    (raise-user-error 'render-3d-illustrations "refusing a symbolic-link output directory"))
  ;; An unchanged successful --install is a no-op. Unknown or stale directories
  ;; are never overwritten. Choose a new output directory for another review.
  (when (or (file-exists? target) (directory-exists? target))
    (unless (and install? (file-exists? manifest-path))
      (raise-user-error 'render-3d-illustrations "choose a fresh output directory: ~a" target))
    (define prior (call-with-input-file manifest-path read-json))
    (unless (and (equal? (hash-ref prior 'schema #f) "animate-manual-3d-frames-v1")
                 (equal? (hash-ref prior 'drawing-policy #f) "animate-shapes-smoothed-v1")
                 (equal? (hash-ref prior 'sources #f) sources)
                 (equal? (hash-ref prior 'racket #f) (version))
                 (equal? (hash-ref prior 'recipe #f) (format "~s" three-d-strip-specs)))
      (raise-user-error 'render-3d-illustrations
                       "stored frames are stale; rename ~a before running --install again" target))
    (for* ([strip (in-hash-values (hash-ref prior 'strips))]
           [frame (in-list (hash-ref strip 'frames))])
      (define file (build-path target (hash-ref frame 'file)))
      (unless (and (file-exists? file) (equal? (file-sha1 file) (hash-ref frame 'sha1)))
        (raise-user-error 'render-3d-illustrations "stored capture is missing or changed: ~a" file))
      (for ([extension (in-list '(#".svg" #".pdf"))])
        (define sibling (path-replace-extension file extension))
        (unless (file-exists? sibling)
          (raise-user-error 'render-3d-illustrations
                            "stored vector alternative is missing: ~a" sibling))))
    (printf "3D manual frames are already installed and verified: ~a\n" target)
    (exit 0))
  (define parent (or (path-only target) root))
  (make-directory* parent)
  (define stage (make-temporary-file ".3d-frames-~a" 'directory parent))
  (dynamic-wind
   void
   (lambda ()
     (define strips
       (for/hash ([spec (in-list three-d-strip-specs)])
         (define key (list-ref spec 0))
         (define source (list-ref spec 1))
         (define binding (list-ref spec 2))
         (define kind (list-ref spec 3))
         (define value (dynamic-require (build-path examples source) binding))
         (define prepared (if (eq? kind 'storyboard) (prepare-storyboard! value) value))
         (define frames
           (for/list ([time (in-list (list-ref spec 4))] [index (in-naturals)])
             (define picture
               (if (eq? kind 'storyboard)
                   (storyboard->pict prepared #:at time #:size (list width height))
                   (scene-picture prepared time)))
             (define bitmap (pict->bitmap picture 'smoothed))
             (define base (format "~a-~a" key index))
             (define-values (_svg _pdf png)
               (pict->manual-files! picture (build-path stage base)))
             (hasheq 'file (path->string (file-name-from-path png))
                     'sha1 (file-sha1 png)
                     'width (send bitmap get-width) 'height (send bitmap get-height)
                     'time (exact->inexact time) 'exact-time (format "~a" time)
                     'caption (format "t = ~a s" time))))
         (printf "~a: ~a frame(s)\n" key (length frames))
         (values (string->symbol key)
                 (hasheq 'source source 'binding (symbol->string binding)
                         'kind (symbol->string kind) 'frames frames))))
     (call-with-output-file (build-path stage "manifest.json")
       (lambda (port)
         (write-json (hasheq 'schema "animate-manual-3d-frames-v1"
                             'drawing-policy "animate-shapes-smoothed-v1"
                             'racket (version) 'sources sources
                             'recipe (format "~s" three-d-strip-specs)
                             'strips strips) port)))
     (rename-file-or-directory stage target)
     (printf "Created genuine Animate frame captures: ~a\n" target))
   (lambda ()
     (when (directory-exists? stage) (delete-directory/files stage)))))
