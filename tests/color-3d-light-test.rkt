#lang racket/base

;;; Render-time light colour resolution and opacity validation

(require rackunit
         "../3d.rkt"
         "../colors.rkt"
         "../private/3d/color-resolution3d.rkt"
         "../private/render-color-context.rkt")

(module+ test
  (define transparent-accent-theme
    (color-theme #:id 'transparent-accent-light
                 #:extends animate-light-theme
                 #:roles (hash 'accent (color-with-alpha pure-red 1/2))))
  (define token-light
    (ambient-light3d #:id 'semantic-light #:color theme-accent))
  ;; The constructor cannot know a token's alpha.  Resolution immediately
  ;; before drawing rejects the invalid light rather than silently accepting it.
  (check-exn exn:fail?
             (lambda ()
               (resolve-light3d token-light
                                (make-render-color-context transparent-accent-theme))))

  ;; Physical defaults remain literal illumination values in a dark theme.
  (define default-light (ambient-light3d))
  (define resolved-default
    (resolve-light3d default-light (make-render-color-context animate-dark-theme)))
  (check-equal? (ambient-light3d-color resolved-default) white)
  (check-equal? (ambient-light3d-intensity resolved-default)
                (ambient-light3d-intensity default-light)))
