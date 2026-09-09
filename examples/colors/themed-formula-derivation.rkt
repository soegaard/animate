#lang racket/base

;; Tagged formula fragments retain semantic color specifications across the
;; rewrite. Construction remains inside make-demo-scene, so loading is lazy.

(require animate
         animate/colors
         "../private/run-demo.rkt")

(provide make-demo-scene)

(define (equation)
  (tagged-formula #:id 'equation #:font-size 3/5
                  #:color-map (hash 'term theme-accent
                                    'constant theme-warning
                                    'answer theme-success)
                  (formula-fragment 'term "x")
                  (formula-fragment 'equals " = ")
                  (formula-fragment 'constant "2 + 3")
                  (formula-fragment 'equals-two " = ")
                  (formula-fragment 'answer "5")))

(define (make-demo-scene)
  (define title
    (plain-text "Themed formula fragments" #:id 'title #:center (vec2 0 2)
                #:font-size 2/5 #:font-weight 'bold #:color theme-foreground))
  (scene-wait (scene-add (make-scene) title (equation)) 1))

(module+ main
  (run-demo "colors/themed-formula-derivation.rkt" make-demo-scene))
