#lang racket/base

;;;
;;; Copying Formula Parts and Attention Effects
;;;

;; A source-preserving formula transition with one legitimate algebraic step:
;; x = 2 becomes x + x = 2 + x by adding x to both sides. The original x is
;; still present while two transient copies follow different curved routes.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

;; Stop at clip boundaries with zero velocity, so a transient copy hands over
;; to its exact endpoint without looking like it snaps into place.
(define (smoothstep progress)
  (* progress progress (- 3 (* 2 progress))))

(define (start-equation)
  (tagged-formula
   #:id 'equation
   #:center (vec2 0 -1/5)
   #:font-size 3/5
   (formula-fragment 'original-x "x")
   (formula-fragment 'equals "=")
   (formula-fragment 'two "2")))

(define (after-adding-x)
  (tagged-formula
   #:id 'equation
   #:center (vec2 0 -1/5)
   #:font-size 3/5
   (formula-fragment 'original-x "x")
   (formula-fragment 'plus-left "+")
   (formula-fragment 'added-x-left "x")
   (formula-fragment 'equals "=")
   (formula-fragment 'two "2")
   (formula-fragment 'plus-right "+")
   (formula-fragment 'added-x-right "x")))

(define (part-position assembly name)
  (visual-position
   (formula-part-formula
    (formula-assembly-visual-ref assembly name))))

;; Keep = at the same position while the two sides make room for their added
;; terms. This makes the operation, rather than shifting punctuation, carry
;; the visual meaning.
(define (formula-with-equals-at assembly position)
  (define shift
    (vec2- position (part-position assembly 'equals)))
  (formula-assembly-visual-with-parts
   assembly
   (for/list ([part (in-list (formula-assembly-visual-parts assembly))])
     (formula-part
      (formula-part-name part)
      (visual-with-position
       (formula-part-formula part)
       (vec2+ (visual-position (formula-part-formula part)) shift))))))

;; `tagged-formula` can give otherwise equivalent full layouts slightly
;; different vertical origins. Keep existing terms on their current y values,
;; and use the equals-sign baseline for newly introduced punctuation/copies.
;; This makes the end-state replacement continuous in both coordinates.
(define (formula-with-stable-y assembly source)
  (define source-y-by-name
    (for/hash ([part (in-list (formula-assembly-visual-parts source))])
      (values (formula-part-name part)
              (vec2-y (visual-position (formula-part-formula part))))))
  (define equation-y
    (hash-ref source-y-by-name 'equals))
  (define x-y
    (hash-ref source-y-by-name 'original-x))
  (formula-assembly-visual-with-parts
   assembly
   (for/list ([part (in-list (formula-assembly-visual-parts assembly))])
     (define name (formula-part-name part))
     (define formula (formula-part-formula part))
     (define y
       (cond
         [(hash-has-key? source-y-by-name name)
          (hash-ref source-y-by-name name)]
         [(memq name '(added-x-left added-x-right)) x-y]
         [else equation-y]))
     (formula-part
      name
      (visual-with-position
       formula
       (vec2 (vec2-x (visual-position formula)) y))))))

;; The right-hand side is extended *after* the existing 2.  The complete
;; TeX layout is initially centred, so preserving its equals sign alone would
;; move 2 slightly right.  Keep the whole pre-existing right-hand group in
;; place instead; the new + x follows it.
(define (formula-with-stationary-right-hand-side assembly source)
  (define shift
    (vec2- (part-position source 'two)
           (part-position assembly 'two)))
  (formula-assembly-visual-with-parts
   assembly
   (for/list ([part (in-list (formula-assembly-visual-parts assembly))])
     (define name (formula-part-name part))
     (define formula (formula-part-formula part))
     (formula-part
      name
      (if (memq name '(two plus-right added-x-right))
          (visual-with-position
           formula
           (vec2+ (visual-position formula) shift))
          formula)))))

(define upper-copy-route
  (formula-relative-path
   (polyline-path
    (list (vec2 0 0) (vec2 1/2 2/5) (vec2 1 0)))))

(define lower-copy-route
  (formula-relative-path
   (polyline-path
    (list (vec2 0 0) (vec2 1/2 -2/5) (vec2 1 0)))))

(define (make-demo-scene)
  (define source (start-equation))
  (define destination
    (formula-with-stationary-right-hand-side
     (formula-with-stable-y
      (formula-with-equals-at
       (after-adding-x)
       (part-position source 'equals))
      source)
     source))
  (define marker
    (circle #:id 'marker #:center (vec2 -5/2 11/10)
            #:radius 3/20 #:fill "royalblue" #:stroke "navy"))
  (define marker-copy
    (circle #:id 'marker-copy #:center (vec2 -3/2 11/10)
            #:radius 3/20 #:fill "royalblue" #:stroke "navy"))
  (define title
    (plain-text
     "SCENE-BW: copies, attention, and formula routes"
     #:id 'title #:center (vec2 0 12/5)
     #:font-size 3/10 #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define marker-caption
    (plain-text
     "generic TransformFromCopy"
     #:id 'marker-caption #:center (vec2 -2 3/4)
     #:font-size 1/6 #:font-family 'swiss #:color "darkslategray"))
  (define formula-caption
    (plain-text
     "Add x to both sides: the original remains while two copies travel."
     #:id 'formula-caption #:center (vec2 0 -2)
     #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define initial
    (scene-add
     (scene-add
      (scene-add
       (scene-add (scene-add (make-scene) title) marker)
       marker-caption)
      formula-caption)
     source))
  (define copied-marker
    (scene-play
     (scene-wait initial 3/4)
     (transform-from-copy 'marker marker-copy #:path-arc 3/4)
     #:duration 1
     #:easing smoothstep))
  (define outlined
    (scene-play (scene-wait copied-marker 1/2)
                (circumscribe 'equation #:color "goldenrod")
                #:duration 1
                #:easing smoothstep))
  (define pulsed
    (scene-play (scene-wait outlined 1/4)
                (indicate 'equation #:color "goldenrod")
                #:duration 1
                #:easing smoothstep))
  (define after-operation
    (scene-play
     (scene-wait pulsed 1/2)
     (transform-matching-formula
      source
      destination
      #:matches
      ;; The original x remains in place as the newly explicit x on the
      ;; left. Two copies then travel to form the new left and right terms.
      (list (formula-part-match 'original-x 'added-x-left)
            (formula-part-match 'equals 'equals)
            (formula-part-match 'two 'two))
      #:copies
      (list (formula-part-copy 'original-x 'original-x upper-copy-route)
            (formula-part-copy 'original-x 'added-x-right lower-copy-route)))
     #:duration 2
     #:easing smoothstep))
  (scene-wait after-operation 1))

(module+ main
  (run-demo "copying-and-emphasizing-formula-parts.rkt" make-demo-scene))
