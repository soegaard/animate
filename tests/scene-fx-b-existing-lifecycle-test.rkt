#lang racket/base

;;;
;;; FX-B Existing Lifecycle Characterization Tests
;;;

;; These are deliberately endpoint-focused fixtures.  FX-B may later share
;; implementation machinery with existing effects, but must retain their
;; precise public lifecycle behavior.

(require rackunit
         "../main.rkt")

(module+ test
  (define card
    (rectangle #:id 'card
               #:width 2 #:height 1
               #:center (vec2 2 1)
               #:rotation 1/5
               #:scale (vec2 3/2 4/3)
               #:opacity 3/4
               #:fill "gold"))
  (define arrow-card
    (arrow (vec2 -2 1) (vec2 2 1) #:id 'arrow-card #:stroke "navy"))
  (define outline
    (make-path-visual
     (polygon-path (list (vec2 -1 -1/2) (vec2 1 -1/2)
                         (vec2 1 1/2) (vec2 -1 1/2)))
     #:id 'outline #:fill "gold" #:stroke "sienna"))

  (define (sampled-in-any-order scene times)
    (define ascending
      (for/hash ([time (in-list times)])
        (values time (scene-sample scene time))))
    (for ([time (in-list (reverse times))])
      (check-equal? (scene-sample scene time) (hash-ref ascending time))))

  ;; Fade-in/out preserve the authored value at their retained endpoint and
  ;; remove the target only after the fade-out completion boundary.
  (define faded-in (scene-play (make-scene) (fade-in card) #:duration 1))
  (check-equal? (visual-opacity (scene-visual-at faded-in 'card 0)) 0)
  (check-equal? (scene-visual-at faded-in 'card 1) card)
  (sampled-in-any-order faded-in '(0 1/4 1/2 3/4 1))
  (define faded-out
    (scene-play (scene-add (make-scene) card) (fade-out 'card) #:duration 1))
  (check-equal? (scene-visual-at faded-out 'card 0) card)
  (check-false (scene-state-has? (scene-sample faded-out 1) 'card))
  (sampled-in-any-order faded-out '(0 1/4 1/2 3/4 1))

  ;; Both structural growth forms finish with the caller's exact Visual.
  (define grown (scene-play (make-scene) (grow-from-center card) #:duration 1))
  (check-equal? (visual-opacity (scene-visual-at grown 'card 0)) 0)
  (check-equal? (scene-visual-at grown 'card 1) card)
  (define grown-arrow
    (scene-play (make-scene) (grow-arrow arrow-card) #:duration 1))
  (check-equal? (visual-opacity (scene-visual-at grown-arrow 'arrow-card 0)) 0)
  (check-equal? (scene-visual-at grown-arrow 'arrow-card 1) arrow-card)

  ;; Path effects retain exact supplied endpoints when introducing and remove
  ;; the current target when exiting.
  (define created (scene-play (make-scene) (create outline) #:duration 1))
  (check-equal? (scene-visual-at created 'outline 1) outline)
  (define uncreated
    (scene-play (scene-add (make-scene) outline) (uncreate 'outline) #:duration 1))
  (check-false (scene-state-has? (scene-sample uncreated 1) 'outline))
  (define border-filled
    (scene-play (make-scene) (draw-border-then-fill outline) #:duration 1))
  (check-equal? (scene-visual-at border-filled 'outline 1) outline)
  (define written (scene-play (make-scene) (write-in outline) #:duration 1))
  (check-equal? (scene-visual-at written 'outline 1) outline)
  (define unwritten
    (scene-play (scene-add (make-scene) outline) (unwrite 'outline) #:duration 1))
  (check-false (scene-state-has? (scene-sample unwritten 1) 'outline)))
