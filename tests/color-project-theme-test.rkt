#lang racket/base

;;;
;;; Project Theme Snapshot Tests
;;;

(require rackunit
         "../authoring.rkt"
         "../colors.rkt"
         "../main.rkt"
         "../project.rkt")

(module+ test
  (define palette
    (color-palette #:id 'project-theme-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#c04020")))
  (define theme
    (color-theme #:id 'project-theme
                 #:extends animate-light-theme
                 #:palette palette
                 #:provenance "tests/project-theme.rkt"))
  (define project
    (animate-project
     #:id 'project-theme
     #:source (scene-source (scene-wait (make-scene) 1))
     #:render (render-spec #:fps 2 #:theme theme)
     #:output (output-spec #:root "media" #:name "project-theme")))
  (define plan (plan-project project))
  (define recorded-theme (hash-ref (project-plan->datum plan) 'color-theme))
  (check-eq? (render-spec-theme (animate-project-render project)) theme)
  (check-eq? (hash-ref recorded-theme 'id) 'project-theme)
  (check-equal? (hash-ref recorded-theme 'datum) (theme->datum theme))
  (check-equal? (hash-ref recorded-theme 'appearance-fingerprint)
                (color-theme-fingerprint theme))
  ;; The prepared inspection datum retains the plan's full snapshot rather
  ;; than relying on the locally installed palette catalog.
  (check-equal?
   (hash-ref (prepared-project->datum (prepare-project! plan)) 'color-theme)
   recorded-theme))
