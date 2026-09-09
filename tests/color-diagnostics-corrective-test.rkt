#lang racket/base

;;; Corrective contracts for contrast assumptions and group classification

(require rackunit
         "../colors.rkt")

(module+ test
  ;; Foreground alpha has a defined composite over an opaque background. A
  ;; translucent background needs a separately declared canvas and is rejected.
  (check-true (positive? (color-contrast-ratio (color-with-alpha black 1/2) white)))
  (check-exn #px"opaque background"
             (lambda ()
               (color-contrast-ratio black (color-with-alpha white 1/2))))

  ;; An arbitrary five-item custom group is categorical metadata, not a claim
  ;; about ordered lightness.
  (define custom-palette
    (color-palette
     #:id 'custom-categorical
     #:extends animate-palette
     #:colors (hash 'first-custom "#FF0000"
                    'second-custom "#00FF00"
                    'third-custom "#0000FF"
                    'fourth-custom "#FFFF00"
                    'fifth-custom "#FF00FF")
     #:groups (append (palette-groups animate-palette)
                       (list '(categorical (first-custom second-custom third-custom
                                                       fourth-custom fifth-custom))))))
  (define custom-theme
    (color-theme #:id 'custom-categorical-theme
                 #:extends animate-light-theme #:palette custom-palette))
  (check-false
   (for/or ([entry (in-list (color-theme-diagnostics custom-theme))])
     (and (eq? (hash-ref entry 'kind) 'shade-ramp)
          (eq? (hash-ref (hash-ref entry 'details) 'group) 'categorical)))))
