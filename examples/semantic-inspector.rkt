#lang racket/base

;;;
;;; SCENE-EN: Semantic Inspector
;;;

;; Start this file with GRacket, choose the `rewrite-equation` block, and
;; pause while the formula changes.  The preview inspector can then show:
;;
;;   * exact source-map units for the selected formula;
;;   * the compiled routes chosen by `rewrite-matching-strings`; and
;;   * the declared dependencies of the `caption` live-layout relation.

(require (only-in racket/math pi)
         racket/runtime-path
         animate
         animate/authoring
         animate/preview)

(provide semantic-inspector-demo)

(define before-equation
  (math-tex
   #:id 'equation
   #:center (vec2 0 1)
   #:font-size 3/5
   #:source-map 'tokens
   "x + 3 = 7"))

(define after-equation
  (math-tex
   #:id 'equation
   #:center (vec2 0 1)
   #:font-size 3/5
   #:source-map 'tokens
   "x = 7 - 3"))

(define dot
  (circle #:id 'dot #:center (vec2 -2 -3/2) #:radius 1/4
          #:fill "tomato" #:stroke "firebrick" #:stroke-width 2))

;; `caption` is a relation Visual, not an imperative per-frame callback.  Its
;; measured position is recomputed from dot's current rendered top anchor.
(define caption
  (follow-above
   (plain-text "live relation: follows dot"
               #:id 'caption #:font-size 1/5 #:font-family 'swiss
               #:color "darkslategray")
   'dot #:gap 1/5))

(define title
  (plain-text "SCENE-EN: semantic inspector"
              #:id 'title #:center (vec2 0 14/5)
              #:font-size 3/10 #:font-family 'swiss #:font-weight 'bold
              #:color "navy"))

(define instruction
  (plain-text "Select the formula or caption; choose rewrite-equation to inspect the active plan."
              #:id 'instruction #:center (vec2 0 21/10)
              #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))

(define-scene-program semantic-inspector-demo
  #:initial (make-scene)

  (scene-block setup (scene)
    (scene-wait
     (scene-add scene title instruction before-equation dot caption)
     1))

  (scene-block rewrite-equation (scene)
    (scene-play
     scene
     (rewrite-matching-strings
     before-equation after-equation
     #:anchor "="
      ;; The equality is the global anchor. `x` needs an author-directed
      ;; stationary constraint; the unchanged `7` is recognised automatically
      ;; even though its physical source fragment owns adjacent whitespace in
      ;; only one of the two formulas.
      #:stationary (list "x")
      #:key-map
      (list
       (string-match
        "+" "-"
        #:route (formula-arc #:angle (- (/ pi 3)))
        ;; The sign keeps this whole arc. Its appearance changes continuously
        ;; from the start, becoming `-` when the route reaches `=`.
        #:appearance-complete-at-x "="
        #:appearance-duration 1/2))
      #:mismatch-mode 'fade-transform)
     (move-to 'dot (vec2 2 -3/2))
     #:duration 3))

  (scene-block hold-result (scene)
    (scene-wait scene 1)))

(define-runtime-path source-path "semantic-inspector.rkt")

(module+ main
  (void
   (open-program-preview source-path 'semantic-inspector-demo
                         #:title "Animate: semantic inspector")))
