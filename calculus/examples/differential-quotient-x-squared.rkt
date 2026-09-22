#lang racket/base
(require animate/calculus/render
         animate/project)

(provide differentiate-x-squared
         differentiate-x-squared-project)

(define-calculus-lesson differentiate-x-squared
  (model
    ;; Mathematical core
    [f (function (x) (* x x))]
    [df (derivative-function
         f
         #:method 'supplied
         #:using (function (x) (* 2 x))
         #:justification "Using the difference quotient, the derivative of x² is 2x.")]

    ;; Live parameters
    ;; x0 is the chosen point on the graph.
    ;; h is the secant increment.
    [x0 (parameter 1 #:domain (closed -2 2))]
    [h  (parameter 1 #:domain (open-closed 0 1))]

    ;; Main graph objects
    [G (graph f)]
    [P (point-on G #:x x0)]
    [Q (point-on G #:x (+ x0 h))]
    [P-name (point-label P "P")]
    [Q-name (point-label Q "Q")]

    ;; Secant/tangent objects
    [S (secant G P Q)]
    [T (tangent G #:at P #:derivative df)]

    ;; Increments and slope
    [change (increment P Q)]
    [triangle (slope-triangle change #:labels 'both)]
    [m (difference-quotient f x0 h)]
    [m-readout (value-readout m
                              #:label "m"
                              #:format 'decimal
                              #:digits 3)]
    [tangent-slope (slope T)]
    [answer (value-readout tangent-slope
                           #:label "f′(x₀)"
                           #:format 'decimal
                           #:digits 3)]

    ;; Goal/result formulas
    [goal (formula-of df)]

    ;; Δy expansion
    [dy-def
     (formula
      (= (ref (part change 'dy))
         (- (value-at f (+ x0 h))
            (value-at f x0))))]

    [dy-expand
     (formula
      (= (ref (part change 'dy))
         (- (expt (+ x0 h) 2)
            (expt x0 2))))]

    [dy-simplify
     (formula
      (= (ref (part change 'dy))
         (+ (* 2 x0 h)
            (expt h 2))))]

    ;; Difference quotient
    [dq-def
     (formula
      (= (ref m)
         (/ (ref (part change 'dy))
            (ref (part change 'dx)))))]

    [dq-subst
     (formula
      (= (ref m)
         (/ (+ (* 2 x0 h)
               (expt h 2))
            h)))]

    [dq-simplify
     (formula
      (= (ref m)
         (+ (* 2 x0) h)))]

    ;; Limit statement
    [L (limit-statement
        (slope S)
        #:parameter h
        #:to 0
        #:side 'right
        #:value (value-at df x0)
        #:justification
        "The secant slope is 2x₀+h, so as h approaches 0 the slope approaches 2x₀.")]
    [limit-formula (formula-of L)])

  (views
    ;; Main overview graph
    [main
     (graph-view
      #:x (closed -5/2 5/2)
      #:y (closed -1/2 13/2)
      #:objects (G P Q P-name Q-name S triangle T))]

    ;; Zoom/detail graph: same mathematical objects, second camera
    [detail
     (graph-view
      #:x (closed -5/2 5/2)
      #:y (closed -1/2 13/2)
      #:objects (G P Q S triangle T))]

    ;; Formula panel
    [facts
     (formula-view
      #:objects (goal
                 dy-def dy-expand dy-simplify
                 dq-def dq-subst dq-simplify
                 m-readout
                 limit-formula
                 answer))])

  (roles
    [G 'primary]
    [P 'input]
    [Q 'comparison]
    [S 'comparison]
    [triangle 'increment]
    [T 'result]
    [goal 'result]
    [answer 'result])

  (initially
    (show G P P-name goal))

  ;; 1. State the target
  (step introduce-problem
    #:say "We want to understand why the derivative of $x^2$ is $2x$."
    (highlight goal)
    (pause 1/2))

  ;; 2. Show the tangent early, graphically, using a second camera
  (step preview-tangent
    #:say "Graphically, the tangent is the line the graph looks like when we zoom in near the point."
    (show (in-view detail T))
    (focus detail
           #:x (closed (- x0 1/4) (+ x0 1/4))
           #:y (closed (- (value-at f x0) 1/4)
                       (+ (value-at f x0) 3/4))
           #:duration 3)
    (highlight (in-view detail P))
    (pause 1))

  ;; 3. Back out: now explain how to compute that slope
  (step ask-how
    #:say "So the question is: how do we compute the slope of that tangent?"
    (restore-view detail #:duration 1)
    (hide (in-view detail T)))

  ;; 4. Choose a nearby point and build the secant
  (step choose-neighbour
    #:say "Choose a nearby point $Q$ with horizontal change $h$, and draw the secant through $P$ and $Q$."
    (show Q Q-name S triangle))

  ;; 5. Compute Δy
  (step define-dy
    #:say "The vertical change is $f(x_0+h)-f(x_0)$."
    (show dy-def))

  (step expand-dy
    #:say "Since $f(x)=x^2$, this becomes $(x_0+h)^2-x_0^2$."
    (together
      (hide dy-def)
      (show dy-expand)))

  (step simplify-dy
    #:say "Expanding and simplifying gives $2x_0h+h^2$."
    (together
      (hide dy-expand)
      (show dy-simplify)))

  ;; 6. Form the difference quotient
  (step define-dq
    #:say "The secant slope is $\\Delta y/\\Delta x$."
    (show dq-def))

  (step substitute-dq
    #:say "Substitute the expression for $\\Delta y$."
    (together
      (hide dq-def)
      (show dq-subst)))

  (step simplify-dq
    #:say "Since $\\Delta x=h$, the secant slope simplifies to $2x_0+h$."
    (together
      (hide dq-subst)
      (show dq-simplify m-readout)))

  ;; 7. Let Q approach P, and zoom again
  (step approach-point
    #:say "Now let $Q$ approach $P$. The secant line approaches the tangent."
    (together
      (approach h #:to 0 #:side 'right #:until 1/50 #:duration 5)
      (focus detail
             #:x (closed (- x0 1/10) (+ x0 1/10))
             #:y (closed (- (value-at f x0) 1/10)
                         (+ (value-at f x0) 3/10))
             #:duration 5))
    (checkpoint near-tangent))

  ;; 8. Make the limit explicit, then reveal the tangent everywhere
  (step identify-limit
    #:say "As $h\\to0$, the secant slope $2x_0+h$ approaches $2x_0$."
    (show limit-formula))

  (step reveal-tangent
    #:say "That limiting line is the tangent, so $f'(x_0)=2x_0$."
    (limit-transition S T #:claim L)
    (hide Q Q-name triangle m-readout
          dy-simplify dq-simplify)
    (show T answer (in-view detail T)))

  ;; 9. x0 was arbitrary: generalize
  (step generalize
    #:say "And because $x_0$ was arbitrary, the derivative of $x^2$ is $2x$."
    (restore-view detail #:duration 1)
    (vary x0
          #:via (list -2 -1 0 1 3/2)
          #:to 2
          #:duration 6)
    (highlight goal)))

;; Project declaration for the reproducible MP4 shown in the examples gallery.
;; Run with:
;;   raco animate render calculus/examples/differential-quotient-x-squared.rkt
;;                       differentiate-x-squared-project
(define differentiate-x-squared-project
  (animate-project
   #:id 'differential-quotient-x-squared
   #:source
   (scene-source
    (lesson->scene differentiate-x-squared #:width 1280 #:height 720))
   #:render
   (render-spec #:fps 20 #:width 1280 #:height 720 #:workers 1 #:quality 'final)
   #:output
   (output-spec #:root "rendered-examples"
                 #:name "differential-quotient-x-squared"
                 #:format 'mp4
                 #:write-frame-sequence? #f
                 #:overwrite-policy 'replace)
   #:encoder
   (encoder-spec #:codec 'h264
                 #:pixel-format 'yuv420p
                 #:options #hasheq((crf . "20")))
   #:cache
   (cache-spec #:root ".animate-cache"
                #:policy 'read-write)))

;; Optional convenience definitions for stills/scenes:

;; (define final-pict
;;   (lesson->pict differentiate-x-squared
;;                 #:at 'final
;;                 #:width 1920
;;                 #:height 1080))
;;
;; (define final-scene
;;   (lesson->scene differentiate-x-squared
;;                  #:width 1920
;;                  #:height 1080))
