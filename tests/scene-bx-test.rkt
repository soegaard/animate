#lang racket/base

;; SCENE-BX: anchored formula rewrites.

(require rackunit
         "../main.rkt")

(define (part name source position)
  (formula-part
   name
   (latex-formula source #:id name #:center position)))

(define (equation equals-x #:equals-name [equals-name 'equals])
  (formula-assembly
   (list (part 'left "x" (vec2 (- equals-x 1) 0))
         (part equals-name "=" (vec2 equals-x 0))
         (part 'right "2" (vec2 (+ equals-x 1) 0)))
   #:id 'equation))

(define (part-position scene time name)
  (visual-position
   (formula-part-formula
    (formula-assembly-visual-ref
     (scene-visual-at scene 'equation time)
     name))))

(module+ test
  ;; The source passed to the second rewrite is its unanchored construction
  ;; template. The rewrite therefore must resolve the anchor from the current
  ;; scene state at compilation rather than from that stale template.
  (define initial (equation 0))
  (define middle-template (equation 3))
  (define final-template (equation -2))
  (define first
    (scene-play
     (scene-add (make-scene) initial)
     (rewrite-formula initial middle-template #:anchor 'equals)
     #:duration 1))
  (define second
    (scene-play
     first
     (rewrite-formula middle-template final-template #:anchor 'equals)
     #:duration 1))
  (check-equal? (part-position second 0 'equals) (vec2 0 0))
  (check-equal? (part-position second 1 'equals) (vec2 0 0))
  (check-equal? (part-position second 2 'equals) (vec2 0 0))

  ;; A formula-part-match anchor supports different names at the two endpoints
  ;; and also becomes an explicit correspondence match.
  (define renamed-destination (equation 4 #:equals-name 'target-equals))
  (define renamed
    (scene-play
     (scene-add (make-scene) initial)
     (rewrite-formula
      initial
      renamed-destination
      #:anchor (formula-part-match 'equals 'target-equals))
     #:duration 1))
  (check-equal? (part-position renamed 1 'target-equals) (vec2 0 0))

  ;; An explicit pair may repeat the anchor, but it cannot redirect one of the
  ;; anchor names elsewhere.
  (check-true
   (transform-formula-parts-request?
    (rewrite-formula
     initial
     middle-template
     #:anchor 'equals
     #:matches (list (formula-part-match 'equals 'equals)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (rewrite-formula
      initial
      middle-template
      #:anchor 'equals
      #:matches (list (formula-part-match 'equals 'left))))))
