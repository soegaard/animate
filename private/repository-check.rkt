#lang racket/base

;;;
;;; Repository Validation Command
;;;

;; `raco animate check-repo` centralizes the release-facing checks without
;; introducing an API-compatibility policy. It validates only today's package.


;;;
;;; Imports and Exports
;;;

(require racket/file
         racket/list
         racket/path
         racket/system)

(provide (struct-out repository-check)
         (struct-out repository-check-report)
         check-repository!)


;;;
;;; Immutable Reports
;;;

(struct repository-check (name ok? detail)
  #:transparent)

;; repository-check records one release validation operation and its exit
;; outcome. detail names the operation rather than attempting to duplicate its
;; potentially long tool log.

(struct repository-check-report (root checks)
  #:transparent)

;; repository-check-report collects every requested check in deterministic
;; execution order. A false result does not prevent later independent checks.


;;;
;;; Repository Validation
;;;

; check-repository! : [#:root path-string?] -> repository-check-report?
;;   Runs the headless release checks, including a source-package smoke install.
(define (check-repository! #:root [root (current-directory)])
  (unless (path-string? root)
    (raise-argument-error 'check-repository! "path-string?" root))
  (define root-path
    (simplify-path (path->complete-path root)))
  (unless (directory-exists? root-path)
    (raise-arguments-error 'check-repository!
                           "an existing repository directory"
                           "root" root))
  (define raco-path (sibling-racket-tool "raco"))
  (define scribble-path (sibling-racket-tool "scribble"))
  (define package-root
    (make-temporary-file "animate-package-check-~a" 'directory))
  (define user-root
    (make-temporary-file "animate-package-user-~a" 'directory))
  (define documentation-root
    (make-temporary-file "animate-documentation-check-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define basic-checks
       (list
        (run-check 'metadata
                   "version/module-boundary/example catalogue tests"
                   raco-path root-path
                   (list "test"
                         "tests/version-coherence-test.rkt"
                         "tests/documentation-structure-test.rkt"
                         "tests/public-module-boundaries-test.rkt"
                         "tests/example-public-imports-test.rkt"
                         "tests/example-catalog-test.rkt"
                         "tests/documented-bindings-exist-test.rkt"))
        (run-check 'compile
                   "compile public modules, tests, and Racket examples"
                   raco-path root-path
                   (append
                    (list "make" "main.rkt" "authoring.rkt" "preview.rkt"
                          "render.rkt" "project.rkt")
                    (relative-racket-files root-path "examples")
                    (relative-racket-files root-path "tests")))
        (run-check 'tests
                   "full test suite"
                   raco-path root-path
                   (list "test" "tests"))
        (run-check 'documentation
                   "registered Scribble manual"
                   scribble-path root-path
                   (list "--htmls" "--dest" (path->string documentation-root)
                         "scribblings/animate.scrbl"))))
     (define package-check
       (source-package-check raco-path root-path package-root user-root))
     (repository-check-report root-path (append basic-checks (list package-check))))
   (lambda ()
     (delete-directory/files package-root)
     (delete-directory/files user-root)
     (delete-directory/files documentation-root))))

(define (run-check name detail executable root arguments)
  (repository-check
   name
   (parameterize ([current-directory root])
     (apply system* executable arguments))
   detail))

(define (source-package-check raco-path root package-root user-root)
  (define archive
    (build-path package-root "animate.zip"))
  ;; `latex-pict` is a runtime dependency that is commonly supplied to this
  ;; checkout as a local package via PLTCOLLECTS.  A deliberately fresh user
  ;; package scope cannot consult that collection path (it would shadow the
  ;; archive we are trying to test), and an offline check must not need a
  ;; catalog merely to rediscover the same local package.  Install an explicit
  ;; local source first when the current development environment provides one.
  ;; The normal catalog-based path is unchanged when no such source is found.
  (define local-dependency-sources
    (filter values
            (map find-local-package-source
                 ;; Order each known local transitive dependency before its
                 ;; dependent package.  The Poppler entries cover the
                 ;; platform variants declared by racket-poppler; unavailable
                 ;; variants simply yield #f and are not installed.
                 '("lexers-lib"
                   "parsers-lib"
                   "svg"
                   "poppler-aarch64-macosx-2"
                   "poppler-x86_64-macosx-2"
                   "poppler-win32-arm64-2"
                   "poppler-win32-x86_64-2"
                   "racket-poppler"
                   "latex-pict"))))
  (define archive-created?
    (run-check 'package-create
               "create a source package archive"
               raco-path root
               ;; `--source` strips generated build products and honors the
               ;; package's `source-omit-files`. It is a flag, not an option
               ;; with an argument: the old command accidentally passed the
               ;; following `--dest` as its value.
               ;; Do not pass `.` here. On Racket 9.3 `split-path` preserves
               ;; that spelling as the symbolic path component `'same`, which
               ;; the package creator then tries to convert to a string for
               ;; the archive name. The normalized absolute checkout path has
               ;; the actual package basename (`animate`).
               (list "pkg" "create" "--source" "--dest"
                     (path->string package-root)
                     (path->string root))))
  (define install-succeeded?
    (and (repository-check-ok? archive-created?)
         (file-exists? archive)
         (parameterize ([current-environment-variables
                         (fresh-package-environment user-root)])
           (and (install-local-package-sources! raco-path
                                                 local-dependency-sources)
                (apply system* raco-path
                       (list "pkg" "install" "--auto" "--scope" "user"
                             (path->string archive)))
                (apply system* raco-path (list "setup" "--pkgs" "animate"))
                ;; A source archive is coherent only when every documented
                ;; public module imports from the fresh installation.
                ;; Require each module in its own process, which produces a
                ;; precise failing surface if one package boundary has a
                ;; missing dependency. `animate/preview` is deliberately
                ;; headless on require, so this exercises it without a GUI.
                (require-public-modules! (find-system-path 'exec-file))))))
  (repository-check
   'package
   install-succeeded?
   "create, install, set up, and require a fresh source package"))

;; require-public-modules! : path? -> boolean?
;; Runs a small isolated `require` for every documented public entry module.
;; The symbols are deliberately written as module references, not aliases to
;; source files, so a fresh archive catches collection-layout mistakes.
(define (require-public-modules! racket-path)
  (for/and ([module-path (in-list '(animate
                                    animate/authoring
                                    animate/preview
                                    animate/render
                                    animate/project
                                    animate/experimental))])
    (system* racket-path
             "-e"
             (format "(require ~a)" module-path))))

;; install-local-package-sources! : path? (listof path?) -> boolean?
;; Installs the explicitly discovered local sources into the isolated user
;; scope as copies.  Linking them would make `raco setup` compile the original
;; checkout, violating isolation and potentially encountering compiled files
;; from a different Racket release.  Keeping this separate from the archive
;; installation gives a useful failure boundary and avoids inherited
;; collection paths.
(define (install-local-package-sources! raco-path source-paths)
  (or (null? source-paths)
      (apply system*
             raco-path
             (append (list "pkg" "install" "--auto" "--copy"
                           "--scope" "user")
                     (map path->string source-paths)))))

;; find-local-package-source : string? -> (or/c #f path?)
;; Finds a package root supplied either as an explicit collection root or in
;; the active Racket user's package store.  The latter matters for a local
;; package's own platform-specific dependencies, such as racket-poppler's
;; native Poppler library.  This remains a bounded lookup: it checks only the
;; active collection roots and their sibling `pkgs` directories; it never
;; searches arbitrary filesystem trees.
(define (find-local-package-source package-name)
  (or (for*/or ([collection-root (in-list (current-library-collection-paths))]
                [candidate (in-list
                            (list collection-root
                                  (build-path collection-root package-name)))]
                #:when (collection-root-package-source? candidate package-name))
        (simplify-path (path->complete-path candidate)))
      (for/or ([collection-root (in-list (current-library-collection-paths))]
               #:when (collection-directory? collection-root))
        (define candidate
          (build-path (path-only (simplify-path (path->complete-path
                                                  collection-root)))
                      "pkgs"
                      package-name))
        (and (package-source-root? candidate package-name)
             (simplify-path (path->complete-path candidate))))))

(define (collection-root-package-source? candidate package-name)
  ;; Both a package containing several collections (such as latex-pict) and a
  ;; package whose root is the one collection (such as svg) are valid package
  ;; sources.  An explicit PLTCOLLECTS root is author-supplied, so its matching
  ;; info.rkt is authoritative; we need not guess by scanning below it.
  (package-source-root? candidate package-name))

(define (package-source-root? candidate package-name)
  (and (directory-exists? candidate)
       (file-exists? (build-path candidate "info.rkt"))
       (equal? package-name
               (path-basename-string candidate))))

(define (collection-directory? path)
  (equal? "collects" (path-basename-string path)))

(define (path-basename-string path)
  (define basename
    (file-name-from-path
     (simplify-path (path->complete-path path))))
  (and basename (path->string basename)))

(define (fresh-package-environment user-root)
  (define environment
    (environment-variables-copy (current-environment-variables)))
  ;; An inherited PLTCOLLECTS can shadow the fresh package with the checkout.
  (environment-variables-set! environment #"PLTCOLLECTS" #f)
  (environment-variables-set! environment
                              #"PLTUSERHOME"
                              (path->bytes user-root))
  environment)

(define (relative-racket-files root directory-name)
  (define directory
    (build-path root directory-name))
  (sort
   (for/list ([path (in-directory directory)]
              #:when (and (file-exists? path)
                          (equal? (path-get-extension path) #".rkt")
                          (not (regexp-match? #rx"/rhombus/"
                                              (path->string path)))))
     (path->string (find-relative-path root path)))
   string<?))

(define (sibling-racket-tool name)
  (define racket-path
    (find-system-path 'exec-file))
  (define candidate
    (build-path (or (path-only racket-path) (current-directory)) name))
  (if (file-exists? candidate)
      candidate
      (or (find-executable-path name)
          (raise-arguments-error
           'check-repository!
           "a Racket tool executable"
           "tool" name))))
