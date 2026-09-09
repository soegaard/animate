#lang racket/base

;; This is intentionally a package-owned smoke test, not a workspace-relative
;; test module.  Requiring it after `raco setup` establishes that the archive's
;; public collections and representative immutable values agree on identity.

(require animate
         animate/authoring
         animate/3d)

(provide run-installed-package-smoke!)

(define (run-installed-package-smoke!)
  (define scene (make-scene))
  (define program
    (make-scene-program 'installed-package-smoke make-scene '()))
  (define formula (latex-formula "x" #:id 'installed-smoke-formula))
  (define vector (vec3 1 2 3))
  (unless (and (scene? scene)
               (scene-program? program)
               (formula-visual? formula)
               (vec3? vector))
    (error 'run-installed-package-smoke! "installed public values have inconsistent identities"))
  (void))
