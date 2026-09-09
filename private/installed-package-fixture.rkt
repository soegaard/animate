#lang racket/base

;; Values deliberately created inside the installed archive.  The release
;; checker loads this module through the installed collection and checks them
;; with predicates from that same collection, catching duplicate module
;; identities before they become unrelated namespace or contract failures.

(require animate
         animate/authoring
         animate/3d)

(provide installed-scene
         installed-program
         installed-formula
         installed-vector)

(define installed-scene (make-scene))
(define installed-program
  (make-scene-program 'installed-package-fixture make-scene '()))
(define installed-formula (latex-formula "x" #:id 'installed-formula))
(define installed-vector (vec3 1 2 3))
