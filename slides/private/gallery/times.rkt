#lang racket/base
(require racket/list "../data.rkt")
(provide gallery-sample-times gallery-review-times)

;; Mid-bridge and mid-action samples are essential: endpoint-only probes cannot
;; detect a broken wipe, easing policy, or paused geometry component.
(define (interval-samples start duration fractions)
  (for/list ([p (in-list fractions)]) (+ start (* p duration))))
(define (gallery-sample-times board)
  (sort
   (remove-duplicates
    (append
     (list 0 (prepared-storyboard-value-duration board))
     (append-map
      (lambda (shot)
        (define offset (prepared-shot-start shot))
        (append-map
         (lambda (beat)
           (interval-samples (+ offset (prepared-beat-start beat))
                             (prepared-beat-duration beat) '(0 1/2 1)))
         (prepared-clip-value-beats (prepared-shot-clip shot))))
      (prepared-storyboard-value-shots board))
     (append-map
      (lambda (bridge)
        (interval-samples (prepared-bridge-start bridge)
                          (transition-value-duration (prepared-bridge-transition bridge)) '(0 1/4 1/2 3/4 1)))
      (prepared-storyboard-value-bridges board))) =) <))
(define (gallery-review-times board)
  (define duration (prepared-storyboard-value-duration board))
  (define interior (gallery-sample-times board))
  (define boundaries
    (append (list 0 duration)
      (append-map
       (lambda (shot)
         (define start (prepared-shot-start shot))
         (list start (+ start (prepared-clip-value-duration (prepared-shot-clip shot)))))
       (prepared-storyboard-value-shots board))
      (append-map
       (lambda (bridge)
         (define start (prepared-bridge-start bridge))
         (list start (+ start (transition-value-duration (prepared-bridge-transition bridge)))))
       (prepared-storyboard-value-bridges board))))
  (sort (remove-duplicates
         (append interior
                 (for/list ([t (in-list boundaries)] #:when (> t 0)) (max 0 (- t 1/60)))
                 (for/list ([t (in-list boundaries)] #:when (< t duration)) (min duration (+ t 1/60)))) =) <))
