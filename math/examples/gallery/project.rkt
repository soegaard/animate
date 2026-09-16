#lang racket/base

;;;
;;; Gallery Project Rendering Client
;;;
;; Declares one restartable source to the existing Animate project executor. This
;; module owns no workers, shard directories, frame loop, or nested renderer pool.

;;;
;;; Imports and Exports
;;;
(require (only-in racket/runtime-path define-runtime-path)
         (for-syntax racket/base)
         (only-in racket/path path-only file-name-from-path)
         "../../private/native.rkt" "model.rkt")
(provide make-gallery-project! render-gallery-frames!)

; gallery-module : path?
;;   Locates the fixed restartable entry module independently of the current directory.
(define-runtime-path gallery-module "../gallery.rkt")

; make-gallery-project! : list? path-string? symbol? integer? integer? integer? integer?
;   integer? boolean? [#:worker-mode symbol?] [#:cache-root (or/c #f path-string?)] -> any/c
;;   Builds the ordinary project declaration with output-independent semantic options.
(define (make-gallery-project! plates destination theme fps workers width height supersample show-api?
                               #:worker-mode [worker-mode 'auto] #:cache-root [cache-root #f]
                               #:replace? [replace? #f])
  (define complete (simplify-path (path->complete-path destination)))
  (define leaf (file-name-from-path complete))
  (unless leaf (raise-user-error 'gallery "output must be a named directory, not a filesystem root"))
  (define root (path-only complete))
  (define native-theme (native 'colors (if (eq? theme 'dark) 'animate-dark-theme 'animate-light-theme)))
  ((native 'project 'animate-project)
   #:id 'math-gallery
   #:source ((native 'project 'module-builder-source) gallery-module 'gallery-render-builder
              #:prepare 'gallery-render-preparer
              #:options (hasheq 'plates (map gallery-plate-id plates) 'theme theme 'show-api? show-api?
                                 'width width 'height height 'fps fps 'supersample supersample))
   #:render ((native 'project 'render-spec) #:fps fps #:width width #:height height
              #:supersample supersample #:workers workers #:worker-mode worker-mode #:theme native-theme)
   #:output ((native 'project 'output-spec) #:root root #:name (path->string leaf)
              #:format 'png-sequence #:overwrite-policy (if replace? 'replace 'error))
   #:encoder ((native 'project 'encoder-spec) #:codec 'none)
   #:cache ((native 'project 'cache-spec)
             #:root (or cache-root (build-path root ".animate-math-gallery-render-cache"))
             #:policy 'read-write)))

; render-gallery-frames! : list? path-string? symbol? integer? integer? integer? integer?
;   integer? boolean? [#:worker-mode symbol?] [#:cache-root (or/c #f path-string?)] -> any/c
;;   Executes the existing project renderer and returns its truthful worker/cache report.
(define (render-gallery-frames! plates destination theme fps workers width height supersample show-api?
                                #:worker-mode [worker-mode 'auto] #:cache-root [cache-root #f]
                               #:replace? [replace? #f])
  ((native 'project-execution 'render-project!)
   (make-gallery-project! plates destination theme fps workers width height supersample show-api?
                          #:worker-mode worker-mode #:cache-root cache-root #:replace? replace?)
   #:directory (current-directory)))
