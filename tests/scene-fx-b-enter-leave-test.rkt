#lang racket/base

;;;
;;; FX-B Exact Entrance and Exit Tests
;;;

(require (only-in racket/math pi)
         rackunit
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

  ;; Enter begins with a structurally present relative appearance and ends with
  ;; the exact authored Visual. Samples are independent of query order.
  (define entering
    (scene-play
     (make-scene)
     (enter card
            #:translation-offset (vec2 -1 0)
            #:scale-factor 1/2
            #:rotation-offset 1/5
            #:opacity-factor 0)
     #:duration 2))
  (check-true (enter-request? (enter card)))
  (define entry-inspection
    (car (scene-animation-inspections-at entering 1)))
  (check-equal? (animation-inspection-kind entry-inspection) 'enter)
  (check-equal? (hash-ref (animation-inspection-data entry-inspection) 'target) 'card)
  (check-equal? (hash-ref (animation-inspection-data entry-inspection) 'lifecycle) 'enter)
  (check-true (scene-state-has? (scene-sample entering 0) 'card))
  (check-equal? (visual-opacity (scene-visual-at entering 'card 0)) 0)
  (check-equal? (visual-opacity (scene-visual-at entering 'card 1)) 3/8)
  (check-equal? (scene-visual-at entering 'card 2) card)
  (define entry-ascending
    (for/hash ([time (in-list '(0 1/2 1 3/2 2))])
      (values time (scene-sample entering time))))
  (for ([time (in-list '(3/2 0 2 1/2 1))])
    (check-equal? (scene-sample entering time) (hash-ref entry-ascending time)))

  ;; A semantic zero scale uses a strictly positive interior proxy while the
  ;; invisible endpoint and exact authored destination remain unambiguous.
  (define collapsed-enter
    (scene-play (make-scene)
                (enter card #:scale-factor 0 #:opacity-factor 0)
                #:duration 1))
  (define collapsed-start (scene-visual-at collapsed-enter 'card 0))
  (check-true (positive? (vec2-x (visual-scale collapsed-start))))
  (check-true (positive? (vec2-y (visual-scale collapsed-start))))
  (check-equal? (visual-opacity collapsed-start) 0)
  (check-equal? (scene-visual-at collapsed-enter 'card 1) card)

  ;; Default leave removes at the exact endpoint; retained leaves preserve the
  ;; target identity and their relative final appearance.
  (define exiting
    (scene-play
     (scene-add (make-scene) card)
     (leave 'card #:translation-offset (vec2 1 0) #:opacity-factor 0)
     #:duration 2))
  (check-true (leave-request? (leave 'card)))
  (define leave-inspection
    (car (scene-animation-inspections-at exiting 1)))
  (check-equal? (animation-inspection-kind leave-inspection) 'leave)
  (check-true
   (hash-ref (animation-inspection-data leave-inspection) 'remove-at-end?))
  (check-equal? (scene-visual-at exiting 'card 0) card)
  (check-equal? (visual-opacity (scene-visual-at exiting 'card 1)) 3/8)
  (check-false (scene-state-has? (scene-sample exiting 2) 'card))
  (define retained
    (scene-play
     (scene-add (make-scene) card)
     (leave 'card #:translation-offset (vec2 1 0) #:opacity-factor 1 #:remove? #f)
     #:duration 1))
  (check-true (scene-state-has? (scene-sample retained 1) 'card))
  (check-not-equal? (scene-visual-at retained 'card 1) card)
  (check-equal? (visual-opacity (scene-visual-at retained 'card 1)) 3/4)

  ;; The readability presets lower only to enter/leave. Their directions are
  ;; normalized, endpoint behavior is still exact, and they introduce no
  ;; second lifecycle implementation.
  (define sliding
    (scene-play (make-scene) (slide-in card 'left #:distance 3) #:duration 1))
  (check-equal?
   (visual-position (scene-visual-at sliding 'card 0))
   (vec2+ (visual-position card)
          (affine-transform-apply-vector (visual-transform card) (vec2 -3 0))))
  (check-equal? (scene-visual-at sliding 'card 1) card)
  (define spun
    (scene-play (make-scene) (spin-in card #:turns 1/2) #:duration 1))
  (check-=
   (visual-rotation (scene-visual-at spun 'card 1/2))
   (- (visual-rotation card) (/ pi 2))
   1e-12)
  (define shrunk
    (scene-play (scene-add (make-scene) card) (shrink-out 'card) #:duration 1))
  (check-true (scene-state-has? (scene-sample shrunk 1/2) 'card))
  (check-false (scene-state-has? (scene-sample shrunk 1) 'card))
  (define slid-out
    (scene-play (scene-add (make-scene) card)
                (slide-out 'card (vec2 3 4) #:distance 5)
                #:duration 1))
  (check-equal?
   (visual-position (scene-visual-at slid-out 'card 1/2))
   (vec2+
    (visual-position card)
    (vec2-scale
     1/2
     (affine-transform-apply-vector (visual-transform card) (vec2 3 4)))))
  (check-exn exn:fail:contract? (lambda () (slide-in card origin)))

  ;; Only written components conflict. An opacity-only enter can share its
  ;; clip with a rotation, while a translation enter conflicts with a move.
  (define concurrent
    (scene-play
     (make-scene)
     (enter card #:opacity-factor 0)
     (rotate-by 'card 1/2)
     #:duration 1))
  (check-equal?
   (visual-rotation (scene-visual-at concurrent 'card 1))
   (+ (visual-rotation card) 1/2))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (make-scene)
      (enter card #:translation-offset (vec2 1 0))
      (move-to 'card (vec2 4 0))
      #:duration 1)))

  ;; A nested target is updated in place without altering its sibling.
  (define sibling
    (circle #:id 'sibling #:radius 1/4 #:center (vec2 -2 0) #:fill "navy"))
  (define nested
    (group (list card sibling) #:id 'panel))
  (define nested-leave
    (scene-play
     (scene-add (make-scene) nested)
     (leave '(panel card) #:opacity-factor 1 #:rotation-offset 1/2 #:remove? #f)
     #:duration 1))
  (check-equal? (scene-visual-at nested-leave '(panel sibling) 1) sibling)
  (check-equal?
   (visual-rotation (scene-visual-at nested-leave '(panel card) 1))
   (+ (visual-rotation card) 1/2))

  ;; Local start-state preparation and endpoint removal remain valid under a
  ;; succession; later leaves resolve the exact previous endpoint.
  (define lifecycle
    (scene-play
     (make-scene)
     (succession (enter card #:opacity-factor 0)
                 (leave 'card #:opacity-factor 0))
     #:duration 2))
  (check-equal? (scene-visual-at lifecycle 'card 1) card)
  (check-false (scene-state-has? (scene-sample lifecycle 2) 'card))

  (check-exn exn:fail:contract?
             (lambda () (scene-play (scene-add (make-scene) card) (enter card))))
  (check-exn exn:fail?
             (lambda () (scene-play (make-scene) (leave 'missing)))))
