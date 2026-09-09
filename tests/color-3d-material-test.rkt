#lang racket/base

;;; Render-time material colour resolution

(require rackunit
         "../3d.rkt"
         "../colors.rkt"
         "../private/3d/color-resolution3d.rkt"
         "../private/render-color-context.rkt")

(module+ test
  (define warm-palette
    (color-palette #:id 'material-warm #:extends animate-palette
                   #:colors (hash 'aqua-c "#e03020")))
  (define cool-palette
    (color-palette #:id 'material-cool #:extends animate-palette
                   #:colors (hash 'aqua-c "#2060e0")))
  (define warm-theme
    (color-theme #:id 'material-warm-theme #:extends animate-light-theme
                 #:palette warm-palette))
  (define cool-theme
    (color-theme #:id 'material-cool-theme #:extends animate-light-theme
                 #:palette cool-palette))
  (define authored
    (material3d #:color aqua-c
                #:specular-color theme-accent
                #:emission theme-success
                #:emission-strength 1/4))

  ;; The authored value is semantic and does not select a theme by itself.
  (check-eq? (material3d-color authored) aqua-c)
  (check-eq? (material3d-specular-color authored) theme-accent)
  (check-eq? (material3d-emission authored) theme-success)

  (define warm (resolve-material3d authored (make-render-color-context warm-theme)))
  (define cool (resolve-material3d authored (make-render-color-context cool-theme)))
  (check-true (rgba-color? (material3d-color warm)))
  (check-true (rgba-color? (material3d-specular-color warm)))
  (check-true (rgba-color? (material3d-emission warm)))
  (check-not-equal? (material3d-color warm) (material3d-color cool))
  ;; Theme resolution changes neither the chosen lighting equation nor its
  ;; numerical coefficients.
  (check-eq? (material3d-lighting warm) (material3d-lighting authored))
  (check-equal? (material3d-roughness warm) (material3d-roughness authored))
  (check-equal? (material3d-specular-exponent warm)
                (material3d-specular-exponent authored)))
