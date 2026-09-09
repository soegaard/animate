#lang racket/base

;;;
;;; FX-F4 Semantic Underline Sweep Tests
;;;

(require racket/list
         rackunit
         "../main.rkt")

(module+ test
  (define caption
    (plain-text "stable layout" #:id 'caption #:font-size 1/2))
  (define underlined
    (scene-play (scene-add (make-scene) caption)
                (underline-sweep 'caption #:stroke-width 3)
                #:duration 2))
  (define default-id
    (hash-ref
     (animation-inspection-data
      (car (scene-animation-inspections-at underlined 1/2)))
     'overlay-id))
  (check-false (scene-state-has? (scene-sample underlined 0) default-id))
  (define partial
    (scene-visual-at underlined default-id 1/2))
  (check-true (path-visual? partial))
  (check-true
   (< (path-geometry-length (path-visual-path partial))
      (path-geometry-length
       (path-visual-path (scene-visual-at underlined default-id 2)))))
  (check-true (scene-state-has? (scene-current-state underlined) default-id))
  (check-not-false (scene-frame->bitmap underlined 1 #:fps 2))
  (check-equal?
   (animation-inspection-kind
    (car (scene-animation-inspections-at underlined 1/2)))
   'underline-sweep)

  ;; Strike-through uses its own semantic helper and can therefore coexist
  ;; with the retained underline rather than colliding in one overlay slot.
  (define marked
    (scene-play (scene-add (make-scene) caption)
                (underline-sweep 'caption)
                (strike-through 'caption #:color "tomato")
                #:duration 1))
  (define marked-helper-ids
    (for/list ([inspection (in-list (scene-animation-inspections-at marked 1/2))])
      (hash-ref (animation-inspection-data inspection) 'overlay-id)))
  (check-equal? (length (remove-duplicates marked-helper-ids)) 2)
  (for ([helper-id (in-list marked-helper-ids)])
    (check-true (scene-state-has? (scene-current-state marked) helper-id)))
  (check-not-false (scene-frame->bitmap marked 1 #:fps 2))

  ;; A highlight is a filled semantic rectangle placed behind, not on top of,
  ;; the source text. Its default lifecycle is temporary.
  (define highlighted
    (scene-play (scene-add (make-scene) caption)
                (highlight-sweep 'caption)
                #:duration 1))
  (define highlight-id
    (hash-ref
     (animation-inspection-data
      (car (scene-animation-inspections-at highlighted 1/2)))
     'overlay-id))
  (define highlighted-order
    (map visual-id
         (scene-state-visuals-in-drawing-order
          (scene-sample highlighted 1/2))))
  (check-equal? highlighted-order
                (list highlight-id 'caption))
  (check-true (rectangle-visual?
               (scene-visual-at highlighted highlight-id 1/2)))
  (check-false (scene-state-has? (scene-current-state highlighted) highlight-id))
  (check-not-false (scene-frame->bitmap highlighted 1 #:fps 2))

  (define retained-highlight
    (scene-play (scene-add (make-scene) caption)
                (highlight-sweep 'caption #:retain? #t)
                #:duration 1))
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order
         (scene-current-state retained-highlight)))
   (list highlight-id 'caption))

  ;; Cleanup is explicit rather than implicit: the non-retained variant leaves
  ;; no helper behind at the endpoint.
  (define transient
    (scene-play (scene-add (make-scene) caption)
                (underline-sweep caption #:id 'temporary-underline #:retain? #f)
                #:duration 1))
  (check-true (scene-state-has? (scene-sample transient 1/2)
                                'temporary-underline))
  (check-false (scene-state-has? (scene-current-state transient)
                                 'temporary-underline))

  ;; Default helper identities are derived from scheduler provenance, so two
  ;; same-target decorations coexist. Explicit duplicate identities still fail.
  (check-not-exn
   (lambda ()
     (scene-play (scene-add (make-scene) caption)
                 (underline-sweep 'caption)
                 (underline-sweep 'caption))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play (scene-add (make-scene) caption)
                 (underline-sweep 'caption #:id 'duplicate)
                 (underline-sweep 'caption #:id 'duplicate))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene)
                 (plain-text "tilted" #:id 'tilted #:rotation 1/8))
      (underline-sweep 'tilted))))
  (check-exn exn:fail:contract?
             (lambda () (underline-sweep (circle #:id 'not-text)))))
