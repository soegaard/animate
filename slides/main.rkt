#lang racket/base

;; Themeable slide authoring is immutable and headless. No native Scene,
;; drawing context, filesystem operation, or encoder is loaded here.
(require "private/appearance.rkt" "private/layout.rkt" "private/model.rkt"
         "private/syntax.rkt"
         (only-in "private/data.rkt"
                  diagnostic? diagnostic-severity diagnostic-code diagnostic-path
                  diagnostic-message diagnostic-details
                  exn:fail:slides? exn:fail:slides-code exn:fail:slides-path exn:fail:slides-details))
(require (only-in "private/semantic-model.rkt"
                  semantic-group semantic-group? semantic-part semantic-part?
                  content-state content-state?))
(provide semantic-group semantic-group? semantic-part semantic-part?
         content-state content-state?
         (all-from-out "private/appearance.rkt" "private/layout.rkt" "private/syntax.rkt")
         (except-out (all-from-out "private/model.rkt")
                     make-slot image-content/proc bound-source)
         diagnostic? diagnostic-severity diagnostic-code diagnostic-path diagnostic-message diagnostic-details
         exn:fail:slides? exn:fail:slides-code exn:fail:slides-path exn:fail:slides-details)
