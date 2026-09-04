#lang racket/base

;;;
;;; SCENE-EL-4 Renderer-Aware Relation Tests
;;;

(require rackunit
         (only-in pict pict?)
         "../main.rkt")

(module+ test
  ;; A layout relation runs only at the Pict adapter boundary, after the
  ;; semantic target and current camera are known.  Its resolver receives a
  ;; renderer-measured anchor only after declaring the exact anchor dependency.
  (define target
    (rounded-rectangle #:id 'target #:center origin #:width 3 #:height 1
                       #:corner-radius 1/4
                       #:fill "aliceblue" #:stroke "steelblue"))
  (define label
    (relation-visual
     (plain-text "above" #:id 'label #:font-size 1/4 #:font-family 'swiss)
     #:phase 'layout
     #:depends-on (list (anchor-dependency 'target 'top))
     (lambda (context template)
       (visual-with-position
        template
        (vec2+ (relation-context-anchor-ref context 'target 'top)
               (vec2 0 1/4))))))
  (define base-state
    (scene-current-state (scene-add (make-scene) target label)))
  ;; Pure scene sampling retains the layout definition. Rendering is the phase
  ;; that resolves it to a concrete text Visual.
  (check-true (relation-visual? (scene-state-resolved-ref base-state 'label)))
  (check-true (pict? (scene-state->pict base-state)))

  ;; A later layout relation can depend on an earlier one. The Pict adapter
  ;; resolves the dependency on demand even when drawing order asks for it first.
  (define second-label
    (relation-visual
     (plain-text "and above that" #:id 'second-label #:font-size 1/5
                 #:font-family 'swiss)
     #:phase 'layout
     #:depends-on (list (anchor-dependency 'label 'top))
     (lambda (context template)
       (visual-with-position
        template
        (vec2+ (relation-context-anchor-ref context 'label 'top)
               (vec2 0 1/5))))))
  (define chained-state
    (scene-current-state
     (scene-add (scene-add (make-scene) target second-label) label)))
  (check-true (pict? (scene-state->pict chained-state)))

  ;; The declared layout graph is still validated before rendering and shares
  ;; the same full dependency paths/cycle semantics as semantic relations.
  (define left
    (relation-visual
     (plain-text "left" #:id 'left #:font-size 1/5)
     #:phase 'layout
     #:depends-on (list (anchor-dependency 'right 'top))
     (lambda (context template)
       (visual-with-position
        template
        (relation-context-anchor-ref context 'right 'top)))))
  (define right
    (relation-visual
     (plain-text "right" #:id 'right #:font-size 1/5)
     #:phase 'layout
     #:depends-on (list (anchor-dependency 'left 'top))
     (lambda (context template)
       (visual-with-position
        template
        (relation-context-anchor-ref context 'left 'top)))))
  (define cycle-state
    (scene-current-state (scene-add (make-scene) left right)))
  (check-exn exn:fail?
             (lambda () (scene-validate-relations cycle-state)))
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"renderer-layout relation graph" (exn-message error))))
   (lambda () (scene-state->pict cycle-state)))

  ;; A semantic resolver cannot smuggle renderer measurement into its phase.
  (define wrongly-semantic
    (relation-visual
     (plain-text "bad" #:id 'wrongly-semantic #:font-size 1/5)
     #:depends-on (list (anchor-dependency 'target 'top))
     (lambda (context template)
       (visual-with-position
        template
        (relation-context-anchor-ref context 'target 'top)))))
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"renderer-aware layout relation context" (exn-message error))))
   (lambda ()
     (scene-state-resolved-ref
      (scene-current-state (scene-add (make-scene) target wrongly-semantic))
      'wrongly-semantic)))

  ;; A source selection is a real semantic dependency, not a fabricated group.
  ;; The layout phase measures its selected formula leaves and hands the union
  ;; to the relation as the same public layout-box used by relative layout.
  (define equation
    (math-tex #:id 'equation #:font-size 1/2 #:source-map 'tokens "x + x = 2x"))
  (define xs (formula-source-select equation "x"))
  (define observed-box #f)
  (define x-label
    (relation-visual
     (plain-text "all x terms" #:id 'x-label #:font-size 1/5 #:font-family 'swiss)
     #:phase 'layout
     #:depends-on (list (selection-dependency xs))
     (lambda (context template)
       (set! observed-box (relation-context-selection-box context xs))
       (visual-with-position
        template
        (vec2+ (relation-context-selection-anchor context xs 'bottom)
               (vec2 0 -1/4))))))
  (check-true
   (pict?
    (scene-state->pict
     (scene-current-state (scene-add (make-scene) equation x-label)))))
  (check-true (layout-box? observed-box))
  (check-true (positive? (layout-box-width observed-box)))

  ;; Deferred relation create is also renderer-phase safe: the wrapper stays
  ;; unresolved until the Pict adapter has obtained the target anchor, then it
  ;; reveals a prefix of that frame's concrete line rather than an old line.
  (define layout-connector
    (relation-visual
     (line origin (vec2 1 0) #:id 'layout-connector #:stroke "gold")
     #:phase 'layout
     #:depends-on (list (anchor-dependency 'target 'left)
                         (anchor-dependency 'target 'right))
     (lambda (context _template)
       (line (relation-context-anchor-ref context 'target 'left)
             (relation-context-anchor-ref context 'target 'right)
             #:id 'layout-connector #:stroke "gold"))))
  (define layout-create-scene
    (scene-play
     (scene-add (make-scene) target)
     (create layout-connector)
     #:duration 1))
  (check-true
   (pict?
    (scene-state->pict (scene-sample layout-create-scene 1/2))))
  (check-true
   (relation-visual?
    (scene-state-ref (scene-current-state layout-create-scene)
                     'layout-connector))))
