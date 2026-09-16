#lang racket/base
(require "private/prepare.rkt" "private/data.rkt" "private/semantic-plan.rkt")
(provide storyboard-match-report prepare-slide! prepare-storyboard! prepared-slide? prepared-slide-clip? prepared-storyboard? prepared-duration)
(define (prepare-slide! source #:theme [theme #f] #:format [format #f] #:asset-base [base #f])
  (resolve-slide source #:theme theme #:format format #:effects? #t #:asset-base base))
(define (prepare-storyboard! source #:asset-base [base #f])
  (resolve-storyboard source #:effects? #t #:asset-base base))


;; Inspect the actual frozen plan, not a prediction based on unmeasured content.
(define (storyboard-match-report source)
  (define board (resolve-storyboard source))
  (for/list ([bridge (in-list (prepared-storyboard-value-bridges board))]
             #:when (eq? (transition-value-effect (prepared-bridge-transition bridge)) 'match))
    (hash 'from (prepared-bridge-from bridge) 'to (prepared-bridge-to bridge)
          'depth (transition-value-depth (prepared-bridge-transition bridge))
          'reduced-motion? (eq? (storyboard-value-motion (prepared-storyboard-value-source board)) 'reduced)
          'matches (map match-plan->datum (prepared-bridge-plan bridge)))))
