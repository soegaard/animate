#lang racket/base

;;;
;;; SCENE-EM Release Identity Tests
;;;

;; `#lang info` intentionally permits only a small expression language and
;; cannot import version.rkt. This test keeps its package literals synchronized
;; with the ordinary-module release identity used by tools and documentation.
;; SCENE-3D-P is the current release identity.

(require rackunit
         racket/file
         racket/runtime-path
         "../version.rkt")

(define-runtime-path info-path "../info.rkt")
(define-runtime-path readme-path "../README.md")
(define-runtime-path manual-path "../scribblings/animate.scrbl")

(define (contains-literal? text literal)
  (regexp-match?
   (regexp (regexp-quote literal))
   text))

(module+ test
  (define info-text (file->string info-path))
  (define readme-text (file->string readme-path))
  (define manual-text (file->string manual-path))
  (check-true
   (contains-literal? info-text
                      (format "(define version \"~a\")" animate-version)))
  (check-true
   (contains-literal? info-text
                      (format "~a:" animate-stage)))
  (check-true
   (contains-literal? readme-text
                      (format "# animate — ~a" animate-stage)))
  (check-true
   (contains-literal? readme-text
                      (format "Prototype version ~a" animate-version)))
  (check-true (contains-literal? info-text "scribblings/animate.scrbl"))
  ;; The manual evaluates the same values instead of duplicating either one.
  (check-true (contains-literal? manual-text "../version.rkt"))
  (check-true (contains-literal? manual-text "animate-stage"))
  (check-true (contains-literal? manual-text "animate-version")))
