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
         check-source-tree!
         check-installed-package!
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

; check-source-tree! : [#:root path-string?] [#:archive-directory path-string?]
;;                       -> repository-check-report?
;;   Checks the working tree without changing the package that supplies this
;;   command.  The generated archive is retained in archive-directory for the
;;   independent installed-package phase.
(define (check-source-tree! #:root [root (current-directory)]
                            #:archive-directory [archive-directory #f])
  (unless (path-string? root)
    (raise-argument-error 'check-source-tree! "path-string?" root))
  (define root-path
    (simplify-path (path->complete-path root)))
  (unless (directory-exists? root-path)
    (raise-arguments-error 'check-source-tree!
                           "an existing repository directory"
                           "root" root))
  (define raco-path (sibling-racket-tool "raco"))
  (define racket-path (find-system-path 'exec-file))
  (define temporary-archive? (not archive-directory))
  (define package-root
    (if archive-directory
        (simplify-path (path->complete-path archive-directory))
        (make-temporary-file "animate-package-check-~a" 'directory)))
  (unless (directory-exists? package-root)
    (make-directory* package-root))
  (define documentation-root
    (make-temporary-file "animate-documentation-check-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define source-checks
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
                         "tests/documented-bindings-exist-test.rkt"
                         "tests/documentation-public-tags-test.rkt"))
        (run-check 'compile
                   "compile public modules, tests, and Racket examples"
                   raco-path root-path
                   (append
                    (list "make" "main.rkt" "3d.rkt" "authoring.rkt" "preview.rkt"
                          "render.rkt" "project.rkt")
                    (relative-racket-files root-path "examples")
                    (relative-racket-files root-path "tests")))
        (run-check 'tests
                   "full test suite"
                   raco-path root-path
                   (list "test" "tests"))
        (run-check 'documentation
                   "registered Scribble manual with strict Animate-owned references"
                   racket-path root-path
                   (list "tools/check-documentation.rkt"
                         (path->string documentation-root)))
        (create-source-archive-check raco-path root-path package-root)))
     (repository-check-report root-path source-checks))
   (lambda ()
     (delete-directory/files documentation-root)
     (when temporary-archive?
       (delete-directory/files package-root)))))

; check-installed-package! : #:archive path-string? #:user-home path-string?
;;                             -> repository-check-report?
;;   Installs only archive into a fresh package home.  Every check runs in an
;;   isolated child Racket process, so a source-tree module identity can never
;;   leak into the installed package validation.
(define (check-installed-package! #:archive archive
                                  #:user-home [user-home
                                               (make-temporary-file
                                                "animate-package-user-~a"
                                                'directory)])
  (unless (path-string? archive)
    (raise-argument-error 'check-installed-package! "path-string?" archive))
  (unless (path-string? user-home)
    (raise-argument-error 'check-installed-package! "path-string?" user-home))
  (define archive-path (simplify-path (path->complete-path archive)))
  (unless (file-exists? archive-path)
    (raise-arguments-error 'check-installed-package!
                           "an existing source package archive"
                           "archive" archive))
  (define user-root (simplify-path (path->complete-path user-home)))
  (when (directory-exists? user-root)
    (unless (null? (directory-list user-root))
      (raise-arguments-error
       'check-installed-package!
       "an empty fresh PLTUSERHOME directory"
       "user-home" user-home)))
  (unless (directory-exists? user-root)
    (make-directory* user-root))
  (define raco-path (sibling-racket-tool "raco"))
  (define racket-path (find-system-path 'exec-file))
  (define local-dependency-sources
    (filter values
            (map find-local-package-source
                 '("lexers-lib"
                   "parsers-lib"
                   "svg"
                   "opengl"
                   "poppler-aarch64-macosx-2"
                   "poppler-x86_64-macosx-2"
                   "poppler-win32-arm64-2"
                   "poppler-win32-x86_64-2"
                   "racket-poppler"
                   "latex-pict"))))
  (define install-succeeded?
    (parameterize ([current-environment-variables
                    (fresh-package-environment user-root)])
      (and (install-local-package-sources! raco-path local-dependency-sources)
           (system* raco-path "pkg" "install" "--auto" "--scope" "user"
                    (path->string archive-path))
           (system* raco-path "setup" "--pkgs" "animate"))))
  (define checks
    (list
     (repository-check
      'package-install install-succeeded?
      "install and set up the source archive in a fresh package home")
     (repository-check
      'package-public-modules
      (and install-succeeded?
           (parameterize ([current-environment-variables
                           (fresh-package-environment user-root)])
             (require-public-modules! racket-path)))
      "require every public collection module from the archive")
     (repository-check
      'package-smoke
      (and install-succeeded?
           (parameterize ([current-environment-variables
                           (fresh-package-environment user-root)])
             (run-installed-package-smoke! racket-path)))
      "run the package-owned installed smoke suite")
     (repository-check
      'package-module-identity
      (and install-succeeded?
           (parameterize ([current-environment-variables
                           (fresh-package-environment user-root)])
             (check-installed-fixture-identities! racket-path)))
      "check fixture values against predicates from the installed host")))
  (repository-check-report archive-path checks))

; check-repository! : [#:root path-string?] -> repository-check-report?
;;   Backwards-compatible composition for local use.  CI invokes the two
;;   explicit operations with separate PLTUSERHOME directories instead.
(define (check-repository! #:root [root (current-directory)])
  (define package-root
    (make-temporary-file "animate-package-check-~a" 'directory))
  (define user-root
    (make-temporary-file "animate-package-user-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define source-report
       (check-source-tree! #:root root #:archive-directory package-root))
     (define package-report
       (check-installed-package!
        #:archive (build-path package-root "animate.zip")
        #:user-home user-root))
     (repository-check-report
      (repository-check-report-root source-report)
      (append (repository-check-report-checks source-report)
              (repository-check-report-checks package-report))))
   (lambda ()
     (delete-directory/files package-root)
     (delete-directory/files user-root))))

(define (run-check name detail executable root arguments)
  (repository-check
   name
   (parameterize ([current-directory root])
     (apply system* executable arguments))
   detail))

(define (create-source-archive-check raco-path root package-root)
  (define archive
    (build-path package-root "animate.zip"))
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

;; require-public-modules! : path? -> boolean?
;; Runs a small isolated `require` for every documented public entry module.
;; The symbols are deliberately written as module references, not aliases to
;; source files, so a fresh archive catches collection-layout mistakes.
(define (require-public-modules! racket-path)
  (for/and ([module-path (in-list '(animate
                                    animate/3d
                                    animate/3d/render
                                    animate/authoring
                                    animate/preview
                                    animate/render
                                    animate/project
                                    animate/experimental))])
    (system* racket-path
             "-e"
             (format "(require ~a)" module-path))))

;; The smoke module and fixture live in the archive.  Unlike a workspace test
;; path, the package-specific library reference below resolves solely through
;; the isolated package database established above.
(define (run-installed-package-smoke! racket-path)
  (system* racket-path
           "-e"
           "(begin (require (lib \"private/installed-package-smoke.rkt\" \"animate\")) (run-installed-package-smoke!))"))

(define (check-installed-fixture-identities! racket-path)
  (system*
   racket-path
   "-e"
   (string-append
    "(begin "
    "(require animate animate/authoring animate/3d) "
    "(define fixture (quote (lib \"private/installed-package-fixture.rkt\" \"animate\"))) "
    "(unless (scene? (dynamic-require fixture (quote installed-scene))) (error (quote fixture) \"scene identity mismatch\")) "
    "(unless (scene-program? (dynamic-require fixture (quote installed-program))) (error (quote fixture) \"scene program identity mismatch\")) "
    "(unless (formula-visual? (dynamic-require fixture (quote installed-formula))) (error (quote fixture) \"formula identity mismatch\")) "
    "(unless (vec3? (dynamic-require fixture (quote installed-vector))) (error (quote fixture) \"vec3 identity mismatch\")))")))

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
