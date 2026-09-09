#lang racket/base

;;;
;;; Corrective semantic mapped-composition tests
;;;

(require rackunit
         "../main.rkt"
         "../private/request-template.rkt")

(module+ test
  (define left
    (circle #:id 'left #:radius 1/4 #:center (vec2 -1 0)))
  (define right
    (circle #:id 'right #:radius 1/4 #:center (vec2 1 0)))
  (define panel (group (list left right) #:id 'panel))

  ;; The children query does not inspect a scene at construction. It resolves
  ;; only after `enter` has established the group at this succession child's
  ;; local start. Reversed scheduling leaves source indexes unchanged.
  (define seen (box '()))
  (define local-start-scene
    (scene-play
     (make-scene)
     (succession
      (enter panel)
      (successive-map
       (children-of 'panel)
       (lambda (reference)
         (set-box! seen
                   (append (unbox seen)
                           (list (list (target-ref-path reference)
                                       (target-ref-source-index reference)
                                       (target-ref-scheduled-index reference)))))
         (move-to (target-ref-path reference)
                  (vec2 (+ 10 (target-ref-source-index reference)) 0)))
       #:order 'reverse))
     #:duration 3))
  (check-equal?
   (unbox seen)
   '(((panel right) 1 0) ((panel left) 0 1)))
  (check-equal? (visual-position (scene-visual-at local-start-scene '(panel left) 3))
                (vec2 10 0))
  (check-equal? (visual-position (scene-visual-at local-start-scene '(panel right) 3))
                (vec2 11 0))

  ;; Query construction snapshots a mutable concrete collection's spine. The
  ;; deferred template still runs once per target only at map expansion.
  (define mutable (vector left right))
  (define query (concrete-targets mutable))
  (vector-set! mutable 1 left)
  (define concrete-seen (box '()))
  (define concrete-scene
    (scene-play
     (scene-add (make-scene) left right)
     (parallel-map
      query
      (lambda (reference)
        (set-box! concrete-seen
                  (append (unbox concrete-seen)
                          (list (target-ref-path reference))))
        (indicate (target-ref-path reference))))
     #:duration 1))
  (check-equal? (unbox concrete-seen) '((left) (right)))
  (check-equal? (scene-visual-at concrete-scene 'left 1) left)
  (check-equal? (scene-visual-at concrete-scene 'right 1) right)

  ;; An empty local-start result has a deliberate diagnostic, and template
  ;; arity errors are reported when expansion knows the resolved reference.
  (define empty-panel (group '() #:id 'empty-panel))
  (check-exn
   #rx"target sequence resolving to at least one target"
   (lambda ()
     (scene-play (scene-add (make-scene) empty-panel)
                 (stagger-map (children-of 'empty-panel)
                              (lambda (_reference) (indicate 'empty-panel))))))
  (check-exn
   #rx"template procedure accepting one target-ref"
   (lambda ()
     (scene-play (scene-add (make-scene) left)
                 (stagger-map (concrete-targets (list left))
                              (lambda () (indicate 'left))))))

  ;; Lists are no longer an ambiguous alternate spelling of semantic mapping.
  ;; Callers who mean eager request construction use the explicit name.
  (check-exn exn:fail:contract?
             (lambda () (stagger-map (list left) (lambda (_reference) left))))
  (check-true
   (lagged-start-animation-request?
    (eager-stagger-map (list left) (lambda (visual) (indicate visual)))))

  ;; Closure-backed templates are honestly nonserializable. A named template is
  ;; transparent/serializable data and runs only through a trusted resolver
  ;; installed by the project/worker boundary.
  (check-false
   (request-template-serializable?
    (procedure-request-template (lambda (_reference) (indicate 'left)))))
  (define named (named-request-template 'registered-indicate))
  (check-true (request-template-serializable? named))
  (check-exn
   #rx"registered resolver"
   (lambda ()
     (scene-play (scene-add (make-scene) left)
                 (stagger-map (concrete-targets (list left)) named))))
  (check-not-exn
   (lambda ()
     (parameterize ([current-request-template-resolver
                     (lambda (name _context)
                       (unless (eq? name 'registered-indicate)
                         (error 'resolver "unknown template"))
                       (lambda (reference) (indicate (target-ref-path reference))))])
       (scene-play (scene-add (make-scene) left)
                   (stagger-map (concrete-targets (list left)) named))))))
