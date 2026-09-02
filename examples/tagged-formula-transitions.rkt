#lang racket/base

;;;
;;; Tagged Formula Transitions
;;;

;; A Manim-like formula transition: TeX lays out each endpoint as one formula,
;; while Animate moves its declared fragments as rigid SVG groups.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (source-equation)
  (tagged-formula
   #:id 'equation
   #:font-size 2/5
   (formula-fragment 'left-a-square "a^2")
   (formula-fragment 'plus "+")
   (formula-fragment 'b-square "b^2")
   (formula-fragment 'equals "=")
   (formula-fragment 'c-square "c^2")))

(define (subtract-a-square)
  (tagged-formula
   ;; Formula-part transitions retain the top-level assembly identity.
   #:id 'equation
   #:font-size 2/5
   (formula-fragment 'left-a-square "a^2")
   (formula-fragment 'plus "+")
   (formula-fragment 'b-square "b^2")
   (formula-fragment 'left-minus "-")
   (formula-fragment 'cancelled-a-square "a^2")
   (formula-fragment 'equals "=")
   (formula-fragment 'c-square "c^2")
   (formula-fragment 'right-minus "-")
   (formula-fragment 'right-a-square "a^2")))

(define (simplified-equation)
  (tagged-formula
   #:id 'simplified
   #:font-size 2/5
   (formula-fragment 'b-square "b^2")
   (formula-fragment 'equals "=")
   (formula-fragment 'c-square "c^2")
   (formula-fragment 'right-minus "-")
   (formula-fragment 'right-a-square "a^2")))

;; Keep the added terms invisible during the first relocation. This separates
;; "make room on both sides" from "write -a^2 on both sides", rather than
;; having the new terms fade in while b^2 and c^2 are still moving.
(define introduced-subtraction-part-names
  '(left-minus cancelled-a-square right-minus right-a-square))

(define cancelled-left-part-names
  ;; The plus belongs to the cancelled left-hand expression too; it fades in
  ;; place rather than being carried along with b^2.
  '(left-a-square plus left-minus cancelled-a-square))

(define (formula-with-hidden-parts assembly names)
  (formula-assembly-visual-with-parts
   assembly
   (for/list ([part (in-list (formula-assembly-visual-parts assembly))])
     (if (memq (formula-part-name part) names)
         (formula-part
          (formula-part-name part)
          (visual-with-opacity (formula-part-formula part) 0))
         part))))

(define (formula-without-parts assembly names)
  (formula-assembly-visual-with-parts
   assembly
   (filter (lambda (part)
             (not (memq (formula-part-name part) names)))
           (formula-assembly-visual-parts assembly))))

(define (formula-with-part-at assembly name position)
  (formula-assembly-visual-with-parts
   assembly
   (for/list ([part (in-list (formula-assembly-visual-parts assembly))])
     (if (eq? (formula-part-name part) name)
         (formula-part
          name
          (visual-with-position (formula-part-formula part) position))
         part))))

(define (formula-part-position assembly name)
  (visual-position
   (formula-part-formula
    (formula-assembly-visual-ref assembly name))))

(define (make-demo-scene)
  (define source (source-equation))
  (define subtraction (subtract-a-square))
  (define subtraction-with-space
    (formula-with-hidden-parts subtraction introduced-subtraction-part-names))
  (define simplified (simplified-equation))
  ;; The final TeX layout gives b^2 its conventional spacing just to the left
  ;; of =. Shift that one target position to the equation's current equals
  ;; position; all other visible terms retain their existing transforms.
  (define fixed-equals-position (formula-part-position subtraction 'equals))
  (define b-square-at-stationary-equals
    (vec2+
     (formula-part-position simplified 'b-square)
     (vec2- fixed-equals-position
            (formula-part-position simplified 'equals))))
  (define subtraction-with-cancelled-left
    (formula-without-parts subtraction cancelled-left-part-names))
  (define simplified-with-stationary-equals
    (formula-with-part-at subtraction-with-cancelled-left
                          'b-square
                          b-square-at-stationary-equals))
  (define title
    (plain-text
     "SCENE-BS: one TeX layout, moving tagged fragments"
     #:id 'title
     #:center (vec2 0 2)
     #:font-size 1/3
     #:font-family 'swiss
     #:font-weight 'bold
     #:color "navy"))
  (define initial
    (scene-add (scene-add (make-scene) title) source))
  (define pause-before
    (scene-wait initial 1))
  (define after-making-space
    (scene-play pause-before
                (transform-matching-formula source subtraction-with-space)
                #:duration 2))
  (define pause-before-introducing-terms
    (scene-wait after-making-space 1/2))
  (define after-introducing-terms
    (scene-play pause-before-introducing-terms
                (transform-matching-formula subtraction-with-space subtraction)
                #:duration 1))
  (define pause-before-cancelling
    (scene-wait after-introducing-terms 1))
  ;; Cancelling the left-side expression fades out just its four fragments;
  ;; every remaining term stays in place.
  (define after-cancelling
    (scene-play
     pause-before-cancelling
     ;; Keep the surviving right-side a^2 paired with itself. Without these
     ;; explicit matches, automatic matching can pair an eliminated left a^2
     ;; with the identical right a^2 and make it appear to move across =.
     (transform-matching-formula
      subtraction
      subtraction-with-cancelled-left
      #:matches
      (list (formula-part-match 'b-square 'b-square)
            (formula-part-match 'equals 'equals)
            (formula-part-match 'c-square 'c-square)
            (formula-part-match 'right-minus 'right-minus)
            (formula-part-match 'right-a-square 'right-a-square)))
     #:duration 1))
  (define pause-before-moving-b-square
    (scene-wait after-cancelling 1))
  ;; Only b^2 moves here. The equals sign and the complete right-hand side
  ;; stay fixed, so the final arrangement reads as b^2 = c^2-a^2.
  (define simplified-scene
    (scene-play
     pause-before-moving-b-square
     (transform-matching-formula subtraction-with-cancelled-left
                                 simplified-with-stationary-equals)
     #:duration 1))
  (scene-wait simplified-scene 1))

(module+ main
  (run-demo "tagged-formula-transitions.rkt" make-demo-scene))
