#lang racket/base

;;;
;;; Color Immutability Tests
;;;

;; Checks that the public constructors retain only immutable normalized data.

(require rackunit
         "../colors.rkt")

(module+ test
  (define mutable-literal (string-copy "#19c5ce"))
  (define expression (color-mix mutable-literal theme-accent 1/2))
  (string-set! mutable-literal 1 #\f)
  (check-equal?
   (color-spec->datum expression)
   '(animate-color-spec 1
                        (mix srgb-linear premultiplied 1/2
                             (rgba 25 197 206 1)
                             (role accent))))

  ;; There is no mutable caller-owned state inside a token or expression. The
  ;; same declarative datum reconstructs the same independently usable value.
  (check-equal? (datum->color-spec (color-spec->datum expression)) expression)
  (check-equal? (role-color 'custom-role) (role-color 'custom-role)))
