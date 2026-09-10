#lang racket/base

;;;
;;; A First Multi-Scene Video: Solving a Linear Equation
;;;
;; This example is intentionally small enough to read from top to bottom.
;; The tutorial-local API comes first.  It is implemented entirely in terms of
;; Animate's existing immutable scenes, authored timelines, tagged formulas,
;; TransformFromCopy, and formula-part transitions.
;;
;; The mathematics:
;;
;;   3x + 5 = 17
;;   3x     = 12
;;   x      = 4
;;
;; A solution is a number that can be inserted for x and makes the original
;; equation true.  Isolating x is the method used to find such numbers.

(require racket/cmdline
         racket/list
         animate
         animate/authoring
         animate/render)

(provide make-demo-video
         make-demo-timeline
         make-demo-scene
         tutorial-video?
         tutorial-video-title
         tutorial-video-timeline)

;; ============================================================================
;; Tutorial-local API
;; ============================================================================

(struct tutorial-scene (name build) #:transparent)
(struct tutorial-video (title timeline) #:transparent)

;; scene : symbol? (scene? -> scene?) -> tutorial-scene?
;;
;; A tutorial scene is a named authoring unit.  It is not a second rendering
;; model: its builder simply extends Animate's ordinary immutable scene.
(define (scene name build)
  (unless (symbol? name)
    (raise-argument-error 'scene "symbol?" name))
  (unless (procedure? build)
    (raise-argument-error 'scene "procedure?" build))
  (tutorial-scene name build))

;; video : #:title string? tutorial-scene? ... -> tutorial-video?
;;
;; Thread one ordinary Animate scene through the builders and record the time
;; span of each builder as an authoring section.  The result can therefore be
;; rendered as one video or addressed scene-by-scene through Animate's existing
;; section machinery.
(define (video #:title title . scenes)
  (unless (string? title)
    (raise-argument-error 'video "string?" title))
  (unless (and (pair? scenes) (andmap tutorial-scene? scenes))
    (raise-argument-error 'video "nonempty list of tutorial-scene? values" scenes))
  (define names (map tutorial-scene-name scenes))
  (unless (= (length names) (length (remove-duplicates names)))
    (raise-arguments-error 'video
                           "scene names must be distinct"
                           "scene-names" names))
  (define-values (finished sections-reversed)
    (for/fold ([scn (make-scene)]
               [sections-reversed '()])
              ([entry (in-list scenes)])
      (define start (scene-duration scn))
      (define next ((tutorial-scene-build entry) scn))
      (unless (scene? next)
        (raise-arguments-error 'video
                               "a scene builder must return an Animate scene"
                               "scene-name" (tutorial-scene-name entry)
                               "result" next))
      (define end (scene-duration next))
      (unless (< start end)
        (raise-arguments-error 'video
                               "each tutorial scene must advance time"
                               "scene-name" (tutorial-scene-name entry)
                               "start" start
                               "end" end))
      (values next
              (cons (section (tutorial-scene-name entry) start end)
                    sections-reversed))))
  (tutorial-video
   (string->immutable-string title)
   (make-authored-timeline finished
                           #:sections (reverse sections-reversed))))

;; equation : symbol? vec2? formula-fragment? ... -> formula-assembly-visual?
;;
;; Typeset all fragments together as one TeX formula, but keep the declared
;; pieces addressable for animation.  Every working layout in this tutorial
;; uses the same font size.
(define (equation id center . fragments)
  (unless (and (pair? fragments) (andmap formula-fragment? fragments))
    (raise-argument-error 'equation
                          "nonempty list of formula-fragment? values"
                          fragments))
  (keyword-apply tagged-formula
                 '(#:center #:font-size #:id)
                 (list center 3/5 id)
                 fragments))

(define (frag name tex)
  (formula-fragment name tex))

;; copy-equation : scene? formula-assembly-visual? formula-assembly-visual?
;;                 [#:duration positive-real?] -> scene?
;;
;; The reference equation remains in place while a working copy moves below it.
(define (copy-equation scn source destination #:duration [duration 3/4])
  (scene-play scn
              (transform-from-copy source destination)
              #:duration duration))

;; rewrite-equation : scene? formula-assembly-visual? formula-assembly-visual?
;;                    [#:matches (listof formula-part-match?)]
;;                    [#:mismatch-mode 'fade/'fade-transform]
;;                    [#:duration positive-real?] -> scene?
(define (rewrite-equation scn source destination
                          #:matches [matches '()]
                          #:mismatch-mode [mismatch-mode 'fade]
                          #:duration [duration 3/5])
  (scene-play
   scn
   (transform-matching-parts source destination
                             #:matches matches
                             #:mismatch-mode mismatch-mode)
   #:duration duration))

;; same-parts : symbol? ... -> (listof formula-part-match?)
(define (same-parts . names)
  (for/list ([name (in-list names)])
    (formula-part-match name name)))

(define (formula-part-position assembly name)
  (visual-position
   (formula-part-formula
    (formula-assembly-visual-ref assembly name))))

;; Shift all local formula parts rigidly so NAME lands at POSITION.
;; All layouts in one working line have the same top-level center, so this fixes
;; the chosen part in world space as well.  We use it for the equality sign.
(define (formula-with-anchor-at assembly name position)
  (define shift
    (vec2- position (formula-part-position assembly name)))
  (formula-assembly-visual-with-parts
   assembly
   (for/list ([part (in-list (formula-assembly-visual-parts assembly))])
     (define visual (formula-part-formula part))
     (formula-part
      (formula-part-name part)
      (visual-with-position visual
                            (vec2+ (visual-position visual) shift))))))

(define (formula-with-part-at assembly name position)
  (formula-assembly-visual-with-parts
   assembly
   (for/list ([part (in-list (formula-assembly-visual-parts assembly))])
     (if (eq? name (formula-part-name part))
         (formula-part
          name
          (visual-with-position (formula-part-formula part) position))
         part))))

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

(define (formula-ref assembly name)
  (formula-assembly-visual-ref assembly name))

;; Replace BASE's ordered part list explicitly.  Reusing parts from BASE keeps
;; them pixel-stationary; borrowing a newly typeset part from another layout
;; introduces only that new mathematical material.
(define (formula-with-parts base . parts)
  (formula-assembly-visual-with-parts base parts))

(define upper-line (vec2 0 6/5))
(define working-line (vec2 0 -3/5))

;; ============================================================================
;; Scene 1 — The problem
;; ============================================================================

(define problem-scene
  (scene
   'problem
   (lambda (scn)
     (define title
       (title-text "Solving a Linear Equation"
                   #:id 'problem-title
                   #:center (vec2 0 2)))
     (define eq
       (equation 'problem-equation origin
                 ;; Keep x addressable so the next scene can emphasize it
                 ;; without replacing the equation.
                 (frag 'three "3")
                 (frag 'x "x")
                 (frag 'plus-five "+5")
                 (frag 'equals "=")
                 (frag 'rhs-17 "17")))
     (define with-title
       (scene-play scn (fade-in title) #:duration 2/5))
     (define with-equation
       (scene-play with-title (fade-in eq) #:duration 3/5))
     (define held (scene-wait with-equation 6/5))
     ;; The title belongs only to this opening scene. Keep the equation so
     ;; Scene 2 can move the same authored formula into its teaching position.
     (scene-remove held 'problem-title))))

;; ============================================================================
;; Scene 2 — What "solve" means
;; ============================================================================

(define meaning-scene
  (scene
   'meaning
   (lambda (scn)
     (define goal
       (body-text
        "Find all numbers that make the equation true when inserted for x."
        #:id 'meaning-goal
        #:center (vec2 0 -4/5)
        #:width 12))
     (define method
       (label-text "Method: isolate x."
                   #:id 'meaning-method
                   #:center (vec2 0 -8/5)))
     ;; Continue directly from Scene 1 instead of fading in a replacement
     ;; equation at a different position.
     (define shown
       (scene-play scn
                   (move-to 'problem-equation (vec2 0 4/5))
                   #:duration 2/5))
     (define x-emphasized
       (scene-play shown
                   ;; A pulse keeps the equation readable, unlike an outline
                   ;; around a single glyph.
                   (pulse '(problem-equation x) #:scale-factor 6/5)
                   #:duration 4/5))
     (define goal-shown
       (scene-play x-emphasized (fade-in goal) #:duration 2/5))
     (define goal-held (scene-wait goal-shown 6/5))
     (define method-shown
       (scene-play goal-held (fade-in method) #:duration 2/5))
     (define held (scene-wait method-shown 6/5))
     (scene-remove held 'problem-equation 'meaning-goal 'meaning-method))))

;; ============================================================================
;; Scene 3 — Subtract 5 from both sides
;; ============================================================================

(define subtract-five-scene
  (scene
   'subtract-five
   (lambda (scn)
     (define reference
       (equation 'subtract-reference upper-line
                 (frag 'three-x "3x")
                 (frag 'plus-five "+5")
                 (frag 'equals "=")
                 (frag 'rhs-17 "17")))
     (define work
       (equation 'subtract-work working-line
                 (frag 'three-x "3x")
                 (frag 'plus-five "+5")
                 (frag 'equals "=")
                 (frag 'rhs-17 "17")))

     ;; Full target after subtracting 5 on each side.
     (define expanded-layout
       (equation 'subtract-work working-line
                 (frag 'three-x "3x")
                 (frag 'plus-five "+5")
                 (frag 'left-minus-five "-5")
                 (frag 'equals "=")
                 (frag 'rhs-17 "17")
                 (frag 'right-minus-five "-5")))
     (define fixed-equals (formula-part-position work 'equals))
     (define expanded
       (formula-with-anchor-at expanded-layout 'equals fixed-equals))

     ;; First move the old terms to make space.  The two new -5 fragments exist
     ;; in the target layout but are fully transparent.
     (define expanded-with-space
       (formula-with-hidden-parts
        expanded
        '(left-minus-five right-minus-five)))

     ;; After +5-5 is cancelled, the surviving 3x is deliberately left where
     ;; the expanded layout put it.  No automatic gap closing is allowed here.
     (define cancelled
       (formula-without-parts expanded '(plus-five left-minus-five)))

     ;; Compute the conventional location of 3x in "3x = 17-5", aligned to the
     ;; same equality sign; then move only 3x there.
     (define compact-layout
       (equation 'subtract-work working-line
                 (frag 'three-x "3x")
                 (frag 'equals "=")
                 (frag 'rhs-17 "17")
                 (frag 'right-minus-five "-5")))
     (define compact-aligned
       (formula-with-anchor-at compact-layout 'equals fixed-equals))
     (define compact
       (formula-with-part-at
        cancelled
        'three-x
        (formula-part-position compact-aligned 'three-x)))

     ;; Final right-hand simplification.  Reuse 3x and = from COMPACT exactly,
     ;; and borrow only the new 12 fragment from a fixed-equals TeX layout.
     (define final-layout
       (equation 'subtract-work working-line
                 (frag 'three-x "3x")
                 (frag 'equals "=")
                 (frag 'rhs-12 "12")))
     (define final-aligned
       (formula-with-anchor-at final-layout 'equals fixed-equals))
     (define final
       (formula-with-parts
        compact
        (formula-ref compact 'three-x)
        (formula-ref compact 'equals)
        (formula-ref final-aligned 'rhs-12)))

     ;; 1. Copy the equation.
     (define reference-shown
       (scene-play scn (fade-in reference) #:duration 2/5))
     (define before-copy (scene-wait reference-shown 1/4))
     (define copied
       (copy-equation before-copy reference work #:duration 3/4))
     (define before-room (scene-wait copied 1/4))

     ;; 2. Make room for -5 on the lhs while = is fixed.
     (define room-made
       (rewrite-equation
        before-room work expanded-with-space
        #:matches (same-parts 'three-x 'plus-five 'equals 'rhs-17)
        #:duration 3/4))
     (define before-minus-fives (scene-wait room-made 1/4))

     ;; 3. Fade in -5 on both sides.
     (define minus-fives-shown
       (rewrite-equation
        before-minus-fives expanded-with-space expanded
        #:matches
        (same-parts 'three-x 'plus-five 'left-minus-five
                    'equals 'rhs-17 'right-minus-five)
        #:duration 1/2))
     (define before-cancellation (scene-wait minus-fives-shown 1/3))

     ;; 4. Fade out +5-5 on the left; every survivor stays in place.
     (define cancelled-scene
       (rewrite-equation
        before-cancellation expanded cancelled
        #:matches
        (same-parts 'three-x 'equals 'rhs-17 'right-minus-five)
        #:duration 3/5))
     (define before-compacting (scene-wait cancelled-scene 1/4))

     ;; 5. Move only 3x closer to the fixed equality sign.
     (define compacted
       (rewrite-equation
        before-compacting cancelled compact
        #:matches
        (same-parts 'three-x 'equals 'rhs-17 'right-minus-five)
        #:duration 1/2))
     (define before-rhs (scene-wait compacted 1/3))

     ;; Finish 17-5 -> 12.
     (define simplified
       (rewrite-equation
        before-rhs compact final
        #:matches (same-parts 'three-x 'equals)
        #:mismatch-mode 'fade-transform
        #:duration 3/5))
     (define held (scene-wait simplified 1))
     (scene-remove held 'subtract-reference 'subtract-work))))

;; ============================================================================
;; Scene 4 — Divide both sides by 3
;; ============================================================================

(define divide-by-three-scene
  (scene
   'divide-by-three
   (lambda (scn)
     (define reference
       (equation 'divide-reference upper-line
                 (frag 'three-x "3x")
                 (frag 'equals "=")
                 (frag 'rhs-12 "12")))
     (define work
       (equation 'divide-work working-line
                 (frag 'three-x "3x")
                 (frag 'equals "=")
                 (frag 'rhs-12 "12")))
     (define fixed-equals (formula-part-position work 'equals))

     ;; Genuine TeX fractions on both sides.
     (define divided-layout
       (equation 'divide-work working-line
                 (frag 'lhs-fraction "\\frac{3x}{3}")
                 (frag 'equals "=")
                 (frag 'rhs-fraction "\\frac{12}{3}")))
     (define divided
       (formula-with-anchor-at divided-layout 'equals fixed-equals))

     ;; Show the left simplification explicitly as 1*x before suppressing 1*.
     (define one-times-layout
       (equation 'divide-work working-line
                 (frag 'one-times "1\\cdot")
                 (frag 'x "x")
                 (frag 'equals "=")
                 (frag 'rhs-fraction "\\frac{12}{3}")))
     (define one-times
       (formula-with-anchor-at one-times-layout 'equals fixed-equals))

     ;; Removing 1* does not move x.  That makes the next pause genuinely about
     ;; noticing that x has been isolated.
     (define isolated
       (formula-without-parts one-times '(one-times)))

     ;; Only after the pause does 12/3 become 4.  Preserve x and = exactly.
     (define solution-layout
       (equation 'divide-work working-line
                 (frag 'x "x")
                 (frag 'equals "=")
                 (frag 'rhs-4 "4")))
     (define solution-aligned
       (formula-with-anchor-at solution-layout 'equals fixed-equals))
     (define solution
       (formula-with-parts
        isolated
        (formula-ref isolated 'x)
        (formula-ref isolated 'equals)
        (formula-ref solution-aligned 'rhs-4)))

     ;; 1. Copy 3x=12.
     (define reference-shown
       (scene-play scn (fade-in reference) #:duration 2/5))
     (define before-copy (scene-wait reference-shown 1/4))
     (define copied
       (copy-equation before-copy reference work #:duration 3/4))
     (define before-division (scene-wait copied 1/3))

     ;; 2. Add division by 3 on both sides as real fractions.
     (define divided-scene
       (rewrite-equation
        before-division work divided
        #:matches (same-parts 'equals)
        #:mismatch-mode 'fade-transform
        #:duration 4/5))
     (define before-reduction (scene-wait divided-scene 1/3))

     ;; 3. Reduce 3/3 to 1* (displayed as 1·x).
     (define reduced
       (rewrite-equation
        before-reduction divided one-times
        #:matches (same-parts 'equals 'rhs-fraction)
        #:mismatch-mode 'fade-transform
        #:duration 7/10))
     (define before-one-fades (scene-wait reduced 1/4))

     ;; 4. Fade 1* away; x, = and 12/3 do not move.
     (define isolated-scene
       (rewrite-equation
        before-one-fades one-times isolated
        #:matches (same-parts 'x 'equals 'rhs-fraction)
        #:duration 1/2))

     ;; 5. Pause with x isolated.
     (define isolated-held (scene-wait isolated-scene 1))

     ;; 6. Transform 12/3 to 4 on the rhs only.
     (define solved
       (rewrite-equation
        isolated-held isolated solution
        #:matches (same-parts 'x 'equals)
        #:mismatch-mode 'fade-transform
        #:duration 3/5))
     (define held (scene-wait solved 1))
     (scene-remove held 'divide-reference 'divide-work))))

;; ============================================================================
;; Scene 5 — Check x=4 in the original equation
;; ============================================================================

(define check-scene
  (scene
   'check
   (lambda (scn)
     ;; Split 3 and x here because x itself is the part being substituted.
     (define reference
       (equation 'check-reference upper-line
                 (frag 'three "3")
                 (frag 'x "x")
                 (frag 'plus-five "+5")
                 (frag 'equals "=")
                 (frag 'rhs-17 "17")))
     (define work
       (equation 'check-work working-line
                 (frag 'three "3")
                 (frag 'x "x")
                 (frag 'plus-five "+5")
                 (frag 'equals "=")
                 (frag 'rhs-17 "17")))
     (define fixed-equals (formula-part-position work 'equals))

     (define substituted-layout
       (equation 'check-work working-line
                 (frag 'three "3")
                 (frag 'left-paren "(")
                 (frag 'value-4 "4")
                 (frag 'right-paren ")")
                 (frag 'plus-five "+5")
                 (frag 'equals "=")
                 (frag 'rhs-17 "17")))
     (define substituted
       (formula-with-anchor-at substituted-layout 'equals fixed-equals))

     ;; Build 12+5=17 while preserving +5, =, and the rhs exactly.
     (define multiplied-layout
       (equation 'check-work working-line
                 (frag 'lhs-12 "12")
                 (frag 'plus-five "+5")
                 (frag 'equals "=")
                 (frag 'rhs-17 "17")))
     (define multiplied-aligned
       (formula-with-anchor-at multiplied-layout 'equals fixed-equals))
     (define multiplied
       (formula-with-parts
        substituted
        (formula-ref multiplied-aligned 'lhs-12)
        (formula-ref substituted 'plus-five)
        (formula-ref substituted 'equals)
        (formula-ref substituted 'rhs-17)))

     ;; Build 17=17 with = and the original rhs untouched.
     (define true-layout
       (equation 'check-work working-line
                 (frag 'lhs-17 "17")
                 (frag 'equals "=")
                 (frag 'rhs-17 "17")))
     (define true-aligned
       (formula-with-anchor-at true-layout 'equals fixed-equals))
     (define truth
       (formula-with-parts
        multiplied
        (formula-ref true-aligned 'lhs-17)
        (formula-ref multiplied 'equals)
        (formula-ref multiplied 'rhs-17)))

     (define checkmark
       (label-text "✓"
                   #:id 'checkmark
                   #:center (vec2 5/2 -3/5)
                   #:font-size 1/2))

     ;; Start from the original equation and make a working copy.
     (define reference-shown
       (scene-play scn (fade-in reference) #:duration 2/5))
     (define before-copy (scene-wait reference-shown 1/4))
     (define copied
       (copy-equation before-copy reference work #:duration 3/4))
     (define before-substitution (scene-wait copied 1/3))

     ;; Substitute x with 4.
     (define substituted-scene
       (rewrite-equation
        before-substitution work substituted
        #:matches
        (append
         (same-parts 'three 'plus-five 'equals 'rhs-17)
         (list (formula-part-match 'x 'value-4)))
        #:duration 7/10))
     (define before-multiplication (scene-wait substituted-scene 1/3))

     ;; 3(4)+5=17 -> 12+5=17.
     (define multiplied-scene
       (rewrite-equation
        before-multiplication substituted multiplied
        #:matches (same-parts 'plus-five 'equals 'rhs-17)
        #:mismatch-mode 'fade-transform
        #:duration 3/5))
     (define before-addition (scene-wait multiplied-scene 1/3))

     ;; 12+5=17 -> 17=17.
     (define true-scene
       (rewrite-equation
        before-addition multiplied truth
        #:matches (same-parts 'equals 'rhs-17)
        #:mismatch-mode 'fade-transform
        #:duration 3/5))
     (define checked
       (scene-play true-scene (fade-in checkmark) #:duration 2/5))
     (define held (scene-wait checked 6/5))
     (scene-remove held 'check-reference 'check-work 'checkmark))))

;; ============================================================================
;; Scene 6 — Summary
;; ============================================================================

(define summary-scene
  (scene
   'summary
   (lambda (scn)
     ;; Typeset each line independently, then put every equals sign on x=0.
     (define row1-layout
       (equation 'summary-row-1 (vec2 0 6/5)
                 (frag 'lhs "3x+5")
                 (frag 'equals "=")
                 (frag 'rhs "17")))
     (define row2-layout
       (equation 'summary-row-2 origin
                 (frag 'lhs "3x")
                 (frag 'equals "=")
                 (frag 'rhs "12")))
     (define row3-layout
       (equation 'summary-row-3 (vec2 0 -6/5)
                 (frag 'lhs "x")
                 (frag 'equals "=")
                 (frag 'rhs "4")))
     (define (equals-on-axis formula)
       (define p (formula-part-position formula 'equals))
       (formula-with-anchor-at formula 'equals (vec2 0 (vec2-y p))))
     (define row1 (equals-on-axis row1-layout))
     (define row2 (equals-on-axis row2-layout))
     (define row3 (equals-on-axis row3-layout))
     (define first
       (scene-play scn (fade-in row1) #:duration 2/5))
     (define second
       (scene-play (scene-wait first 1/4)
                   (fade-in row2)
                   #:duration 2/5))
     (define third
       (scene-play (scene-wait second 1/4)
                   (fade-in row3)
                   #:duration 2/5))
     (scene-wait third 3/2))))

;; ============================================================================
;; Assemble the complete six-scene tutorial
;; ============================================================================

(define (make-demo-video)
  (video #:title "Solving a Linear Equation"
         problem-scene
         meaning-scene
         subtract-five-scene
         divide-by-three-scene
         check-scene
         summary-scene))

(define (make-demo-timeline)
  (tutorial-video-timeline (make-demo-video)))

(define (make-demo-scene)
  (authored-timeline-scene (make-demo-timeline)))

(define (run-tutorial)
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "linear-equation-tutorial.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define scn (make-demo-scene))
  (define paths
    (render-frames! scn output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n"
          (length paths)
          output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))

(module+ main
  (run-tutorial))
