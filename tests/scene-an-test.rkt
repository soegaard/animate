#lang racket/base

;;;
;;; SCENE-AN Local Visual Timing Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define dot
    (circle #:id 'dot
            #:radius 1/2
            #:center origin
            #:fill "seagreen"))

  (define (dot-at state)
    (scene-state-ref state 'dot))

  ;; timed is a first-class wrapper for Visual and camera requests.
  (define delayed-request
    (timed (move-to dot (vec2 4 0))
           #:start 1
           #:duration 2))
  (check-true (timed-animation-request? delayed-request))
  (check-true
   (timed-animation-request?
    (timed (camera-pan-to (vec2 1 0)))))
  (check-exn exn:fail:contract?
             (lambda () (timed (move-to dot origin) #:start -1)))
  (check-exn exn:fail:contract?
             (lambda () (timed (move-to dot origin) #:duration 0)))
  (check-exn exn:fail:contract?
             (lambda () (timed (move-to dot origin) #:easing 1)))

  ;; A delayed request holds the exact start state before its local interval,
  ;; interpolates only inside that interval, and holds its endpoint afterward.
  (define delayed-scene
    (scene-play
     (scene-add (make-scene) dot)
     delayed-request
     #:duration 4))
  (check-equal? (visual-position (dot-at (scene-sample delayed-scene 0)))
                origin)
  (check-equal? (visual-position (dot-at (scene-sample delayed-scene 1/2)))
                origin)
  (check-equal? (visual-position (dot-at (scene-sample delayed-scene 1)))
                origin)
  (check-equal? (visual-position (dot-at (scene-sample delayed-scene 2)))
                (vec2 2 0))
  (check-equal? (visual-position (dot-at (scene-sample delayed-scene 3)))
                (vec2 4 0))
  (check-equal? (visual-position (dot-at (scene-sample delayed-scene 7/2)))
                (vec2 4 0))
  (check-equal? (scene-duration delayed-scene) 4)
  (check-equal? (scene-clip-count delayed-scene) 1)

  ;; Touching same-component intervals are legal. The second relative request
  ;; must compile from the first request's exact local endpoint, not clip start.
  (define sequential-rotation
    (scene-play
     (scene-add (make-scene) dot)
     (timed (rotate-by dot 1) #:start 0 #:duration 1)
     (timed (rotate-by dot 1) #:start 1 #:duration 1)
     #:duration 3))
  (check-equal?
   (visual-rotation (dot-at (scene-sample sequential-rotation 1)))
   1)
  (check-equal?
   (visual-rotation (dot-at (scene-sample sequential-rotation 3/2)))
   3/2)
  (check-equal?
   (visual-rotation (dot-at (scene-sample sequential-rotation 2)))
   2)
  (check-equal?
   (visual-rotation (dot-at (scene-sample sequential-rotation 5/2)))
   2)

  ;; Overlapping changes to disjoint components remain composable.
  (define overlapped-components
    (scene-play
     (scene-add (make-scene) dot)
     (timed (move-to dot (vec2 4 0)) #:start 0 #:duration 2)
     (timed (rotate-to dot 2) #:start 1 #:duration 2)
     #:duration 3))
  (define overlapped-mid
    (dot-at (scene-sample overlapped-components 3/2)))
  (check-equal? (visual-position overlapped-mid) (vec2 3 0))
  (check-equal? (visual-rotation overlapped-mid) 1/2)

  ;; Overlapping changes to the same component are rejected even when they have
  ;; different local starts. Exact endpoint touching above remains legal.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (timed (move-to dot (vec2 2 0)) #:start 0 #:duration 2)
      (timed (move-to dot (vec2 4 0)) #:start 1 #:duration 2)
      #:duration 3)))

  ;; A timed interval must fit inside the explicit enclosing clip.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (timed (move-to dot (vec2 4 0)) #:start 2 #:duration 2)
      #:duration 3)))

  ;; A false local easing inherits scene-play's easing. An explicit local easing
  ;; overrides it without changing the enclosing camera easing semantics.
  (define (square progress)
    (* progress progress))
  (define inherited-easing
    (scene-play
     (scene-add (make-scene) dot)
     (timed (move-to dot (vec2 4 0)) #:start 1 #:duration 2)
     #:duration 3
     #:easing square))
  (check-equal?
   (visual-position (dot-at (scene-sample inherited-easing 2)))
   (vec2 1 0))
  (define overridden-easing
    (scene-play
     (scene-add (make-scene) dot)
     (timed (move-to dot (vec2 4 0))
            #:start 1 #:duration 2 #:easing linear)
     #:duration 3
     #:easing square))
  (check-equal?
   (visual-position (dot-at (scene-sample overridden-easing 2)))
   (vec2 2 0))

  ;; Untimed Visual requests retain full-clip timing when any sibling is timed.
  (define other
    (rectangle #:id 'other
               #:width 1
               #:height 1
               #:center (vec2 0 2)
               #:fill "slateblue"))
  (define mixed-scene
    (scene-play
     (scene-add (make-scene) dot other)
     (move-to dot (vec2 6 0))
     (timed (rotate-to other 2) #:start 1 #:duration 1)
     #:duration 3))
  (check-equal?
   (visual-position (scene-state-ref (scene-sample mixed-scene 3/2) 'dot))
   (vec2 3 0))
  (check-equal?
   (visual-rotation (scene-state-ref (scene-sample mixed-scene 3/2) 'other))
   1)

  ;; Delayed structural introduction is absent before its local start, then uses
  ;; the same shared-start preparation semantics as historical scene-play.
  (define badge
    (rectangle #:id 'badge
               #:width 2
               #:height 1
               #:center (vec2 -2 0)
               #:fill "gold"
               #:opacity 4/5))
  (define introduced-scene
    (scene-play
     (make-scene)
     (timed (fade-in badge) #:start 1 #:duration 1)
     (timed (move-to 'badge (vec2 2 0)) #:start 1 #:duration 2)
     #:duration 3))
  (check-false (scene-state-has? (scene-sample introduced-scene 1/2) 'badge))
  (define introduced-start
    (scene-state-ref (scene-sample introduced-scene 1) 'badge))
  (check-equal? (visual-opacity introduced-start) 0)
  (check-equal? (visual-position introduced-start) (vec2 -2 0))
  (define introduced-mid
    (scene-state-ref (scene-sample introduced-scene 3/2) 'badge))
  (check-equal? (visual-opacity introduced-mid) 2/5)
  (check-equal? (visual-position introduced-mid) (vec2 -1 0))
  (check-equal?
   (visual-opacity (scene-state-ref (scene-sample introduced-scene 2) 'badge))
   4/5)
  (check-equal?
   (visual-position (scene-state-ref (scene-sample introduced-scene 3) 'badge))
   (vec2 2 0))

  ;; create uses the same local-start rule, but introduces empty semantic path
  ;; geometry instead of an opacity-zero complete Visual.
  (define stroke-path
    (polyline-path (list (vec2 -2 -2) (vec2 0 -1) (vec2 2 -2))))
  (define stroke
    (make-path-visual stroke-path #:id 'stroke #:stroke "navy" #:stroke-width 4))
  (define created-scene
    (scene-play
     (make-scene)
     (timed (create stroke) #:start 1 #:duration 1)
     #:duration 3))
  (check-false (scene-state-has? (scene-sample created-scene 1/2) 'stroke))
  (check-true
   (path-geometry-empty?
    (path-visual-path
     (scene-state-ref (scene-sample created-scene 1) 'stroke))))
  (check-eq?
   (path-visual-path (scene-state-ref (scene-sample created-scene 2) 'stroke))
   stroke-path)

  ;; A removal may be followed by a same-ID reintroduction at exactly the same
  ;; local boundary, but another animation cannot run beyond the removal time.
  (define replaced-badge
    (rectangle #:id 'badge
               #:width 1
               #:height 2
               #:center (vec2 3 0)
               #:fill "tomato"))
  (define reintroduced-scene
    (scene-play
     (scene-add (make-scene) badge)
     (timed (fade-out badge) #:start 0 #:duration 1)
     (timed (fade-in replaced-badge) #:start 1 #:duration 1)
     #:duration 2))
  (check-true (scene-state-has? (scene-sample reintroduced-scene 1) 'badge))
  (check-equal?
   (visual-position (scene-state-ref (scene-sample reintroduced-scene 1) 'badge))
   (vec2 3 0))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) badge)
      (timed (fade-out badge) #:start 0 #:duration 1)
      (timed (move-to badge (vec2 5 0)) #:start 0 #:duration 2)
      #:duration 2)))

  ;; Component endpoints from different start batches are sampled before a
  ;; same-time structural removal. This must not depend on request order.
  (define same-boundary-removal
    (scene-play
     (scene-add (make-scene) badge)
     (timed (fade-out badge) #:start 0 #:duration 2)
     (timed (move-to badge (vec2 5 0)) #:start 1 #:duration 1)
     #:duration 3))
  (check-false (scene-state-has? (scene-sample same-boundary-removal 2) 'badge))

  ;; Reversing caller order must not change cross-batch endpoint behavior; local
  ;; event time, not source-list position, determines compilation order.
  (define same-boundary-removal-reversed
    (scene-play
     (scene-add (make-scene) badge)
     (timed (move-to badge (vec2 5 0)) #:start 1 #:duration 1)
     (timed (fade-out badge) #:start 0 #:duration 2)
     #:duration 3))
  (check-false
   (scene-state-has? (scene-sample same-boundary-removal-reversed 2) 'badge))

  ;; camera-follow remains a full-clip camera request but follows the actual
  ;; delayed Visual sample rather than a clip-wide linear approximation.
  (define follow-camera
    (make-camera #:width 320 #:height 180 #:world-width 12 #:center origin))
  (define follow-scene
    (scene-play
     (scene-add (make-scene #:camera follow-camera) dot)
     (timed (move-to dot (vec2 4 0)) #:start 1 #:duration 1)
     (camera-follow dot)
     #:duration 3))
  (check-equal? (camera-center (scene-camera-at follow-scene 1/2)) origin)
  (check-equal? (camera-center (scene-camera-at follow-scene 3/2)) (vec2 2 0))
  (check-equal? (camera-center (scene-camera-at follow-scene 5/2)) (vec2 4 0))

  ;; The convenient single-list scene-play form accepts timed leaves too.
  (define list-form
    (scene-play
     (scene-add (make-scene) dot)
     (list (timed (move-to dot (vec2 2 0)) #:start 1 #:duration 1))
     #:duration 2))
  (check-equal?
   (visual-position (scene-state-ref (scene-sample list-form 3/2) 'dot))
   (vec2 1 0))

  ;; The no-timed branch remains the exact historical implementation.
  (define legacy-scene
    (scene-play
     (scene-add (make-scene) dot)
     (move-to dot (vec2 4 0))
     (rotate-to dot 2)
     #:duration 2))
  (check-equal?
   (visual-position (dot-at (scene-sample legacy-scene 1)))
   (vec2 2 0))
  (check-equal?
   (visual-rotation (dot-at (scene-sample legacy-scene 1)))
   1))
