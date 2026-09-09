#lang racket/base

;;;
;;; FX-A Mapped Staggering Tests
;;;

(require rackunit
         "../3d.rkt"
         "../main.rkt")

(module+ test
  (define top
    (circle #:id 'top #:radius 1/2 #:center (vec2 0 2) #:fill "royalblue"))
  (define middle
    (rectangle #:id 'middle #:width 1 #:height 1 #:center origin #:fill "seagreen"))
  (define bottom
    (circle #:id 'bottom #:radius 1/2 #:center (vec2 0 -2) #:fill "tomato"))
  (define targets (list top middle bottom))

  (define source-indexes (box '()))
  (define mapped
    (stagger-map
     targets
     (lambda (target source-index)
       (set-box! source-indexes
                 (append (unbox source-indexes) (list source-index)))
       (move-to target
                (vec2 (+ 4 source-index)
                      (vec2-y (visual-position target)))))
     #:lag-ratio 1/2))
  (check-true (lagged-start-animation-request? mapped))
  (check-equal? (unbox source-indexes) '(0 1 2))
  (check-equal?
   mapped
   (lagged-start
    (move-to top (vec2 4 2))
    (move-to middle (vec2 5 0))
    (move-to bottom (vec2 6 -2))
    #:lag-ratio 1/2))

  ;; Vectors normalize to the same concrete source order.  A one-argument
  ;; factory remains valid, while a factory accepting both arities receives the
  ;; more informative target/source-index call.
  (check-equal?
   (stagger-map
    (vector top middle)
    (lambda (target) (move-to target (vec2 3 (vec2-y (visual-position target)))))
    #:lag-ratio 1/3)
   (lagged-start
    (move-to top (vec2 3 2))
    (move-to middle (vec2 3 0))
    #:lag-ratio 1/3))

  ;; The mapper accepts every existing composition-child family; it does not
  ;; need a special Visual-only request representation.
  (check-true
   (lagged-start-animation-request?
    (stagger-map '(alpha beta)
                 (lambda (target source-index)
                   (value-to target (+ source-index 1))))))
  (check-true
   (lagged-start-animation-request?
    (stagger-map '(first-camera second-camera)
                 (lambda (_target source-index)
                   (camera-pan-to (vec2 source-index 0))))))
  (check-true
   (lagged-start-animation-request?
    (stagger-map (list '(world cube) 'world)
                 (lambda (target source-index)
                   (if (zero? source-index)
                       (move3d-to target (vec3 1 0 0))
                       (camera3d-move-to target (vec3 0 1 6)))))))

  ;; Normalization copies a mutable vector's target spine before the factory
  ;; starts. A mutation caused by the first call cannot affect the second
  ;; source target or its index.
  (define mutable-targets (vector top middle))
  (define copied-spine-ids (box '()))
  (define copied-spine-request
    (stagger-map
     mutable-targets
     (lambda (target source-index)
       (set-box! copied-spine-ids
                 (append (unbox copied-spine-ids) (list (visual-id target))))
       (when (zero? source-index)
         (vector-set! mutable-targets 1 bottom))
       (move-to target (vec2 3 (vec2-y (visual-position target)))))))
  (check-true (lagged-start-animation-request? copied-spine-request))
  (check-equal? (unbox copied-spine-ids) '(top middle))
  (define selected-arity (box '()))
  (define arity-selected-request
    (stagger-map
     (list top)
     (case-lambda
       [(target)
        (set-box! selected-arity 'one)
        (move-to target (vec2 1 2))]
       [(target source-index)
        (set-box! selected-arity (list 'two source-index))
        (move-to target (vec2 1 2))])))
  (check-true (lagged-start-animation-request? arity-selected-request))
  (check-equal? (unbox selected-arity) '(two 0))

  ;; Reversal changes only schedule order.  The factory still ran in source
  ;; order, and the returned value is the ordinary reversed lagged tree.
  (define reverse-calls (box '()))
  (define reverse-mapped
    (stagger-map
     targets
     (lambda (target source-index)
       (set-box! reverse-calls
                 (append (unbox reverse-calls) (list source-index)))
       (move-to target (vec2 4 (vec2-y (visual-position target)))))
     #:lag-ratio 1/2
     #:order 'reverse))
  (check-equal? (unbox reverse-calls) '(0 1 2))
  (check-equal?
   reverse-mapped
   (lagged-start
    (move-to bottom (vec2 4 -2))
    (move-to middle (vec2 4 0))
    (move-to top (vec2 4 2))
    #:lag-ratio 1/2))
  (define reverse-scene
    (scene-play
     (scene-add (make-scene) top middle bottom)
     reverse-mapped
     #:duration 4))
  (check-equal? (visual-position (scene-visual-at reverse-scene 'bottom 1))
                (vec2 2 -2))
  (check-equal? (visual-position (scene-visual-at reverse-scene 'top 1))
                (vec2 0 2))
  (check-equal? (visual-position (scene-visual-at reverse-scene 'top 4))
                (vec2 4 2))

  ;; Samples remain equal when frames are requested out of timeline order.
  (define forward-scene
    (scene-play
     (scene-add (make-scene) top middle bottom)
     mapped
     #:duration 4))
  (define ascending
    (for/hash ([time (in-list '(0 1 2 3 4))])
      (values time (scene-sample forward-scene time))))
  (for ([time (in-list '(3 0 4 1 2))])
    (check-equal? (scene-sample forward-scene time)
                  (hash-ref ascending time)))
  (check-equal? (visual-position (scene-visual-at forward-scene 'top 4))
                (vec2 4 2))
  (check-equal? (visual-position (scene-visual-at forward-scene 'middle 4))
                (vec2 5 0))
  (check-equal? (visual-position (scene-visual-at forward-scene 'bottom 4))
                (vec2 6 -2))

  ;; Mapped children are regular composition children, so normal nesting and
  ;; post-expansion component-conflict checking apply unchanged.
  (check-true (timed-animation-request? (timed mapped #:duration 2)))
  (check-true (succession-animation-request? (succession mapped (rotate-by top 1))))
  (check-true (animation-group-animation-request? (animation-group mapped
                                                                      (rotate-by top 1))))
  (check-true (lagged-start-animation-request? (lagged-start mapped
                                                              (rotate-by top 1)
                                                              #:lag-ratio 1/2)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) top middle bottom)
      (stagger-map
       targets
       (lambda (_target _source-index) (move-to top (vec2 4 2)))
       #:lag-ratio 0)
      #:duration 1)))

  ;; All invalid forms fail during eager construction and include the source
  ;; index for factory-local failures.
  (check-exn exn:fail:contract?
             (lambda () (stagger-map '() (lambda (target) target))))
  (check-exn exn:fail:contract?
             (lambda () (stagger-map #() (lambda (target) target))))
  (check-exn exn:fail:contract?
             (lambda () (stagger-map 'not-a-collection (lambda (target) target))))
  (check-exn exn:fail:contract?
             (lambda () (stagger-map targets 42)))
  (check-exn exn:fail:contract?
             (lambda () (stagger-map targets (lambda () mapped))))
  (check-exn exn:fail:contract?
             (lambda () (stagger-map targets (lambda (target) 42))))
  (check-exn #rx"source-index: 1"
             (lambda ()
               (stagger-map
                targets
                (lambda (target source-index)
                  (if (= source-index 1)
                      (error 'factory "deliberate failure")
                      (move-to target (vec2 4 0)))))))
  (define invalid-order-called? (box #f))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (stagger-map
      targets
      (lambda (target)
        (set-box! invalid-order-called? #t)
        (move-to target (vec2 4 0)))
      #:order 'inside-out)))
  (check-false (unbox invalid-order-called?)))
