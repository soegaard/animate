#lang racket/base

;;;
;;; Color Theme Cycle Tests
;;;

;; Confirms role dependencies are validated as a graph, including expressions.

(require rackunit
         "../colors.rkt")

(module+ test
  (check-exn #px"dependency cycles"
             (lambda ()
               (color-theme
                #:id 'direct-cycle
                #:extends animate-light-theme
                #:roles (hash 'accent (role-color 'accent)))))
  (check-exn #px"dependency cycles"
             (lambda ()
               (color-theme
                #:id 'indirect-cycle
                #:extends animate-light-theme
                #:roles
                (hash 'accent (color-mix (role-color 'selection) white 1/2)
                      'selection (color-opacity (role-color 'accent) 1/2)))))
  (check-exn #px"missing role"
             (lambda ()
               (color-theme
                #:id 'missing-role
                #:extends animate-light-theme
                #:roles (hash 'accent (role-color 'not-defined))))))
