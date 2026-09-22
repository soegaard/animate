#lang racket/base
;; Example-local presentation adapter. No new markup parser, slide API, or
;; calculus renderer: it consumes the model and uses Animate's existing cameras,
;; relation Visual, prepared-Pict viewport and formula backend.
(require racket/class racket/list racket/math
         (prefix-in p: pict)
         (prefix-in d: racket/draw)
         (prefix-in a: animate)
         (prefix-in c: animate/colors)
         animate/typography
         animate/slides
         (only-in animate/private/prepared-pict-visual prepared-pict-panel)
         (only-in animate/private/latex-formula-pict-renderer
                  default-latex-formula-pict-renderer)
         "differentiation-model.rkt"
         "differentiation-script.rkt")
(provide prepare-example-assets! make-graph-scene make-paper-scene graph-picture
         main-graph-camera make-lens-camera graph-size lens-radius
         (struct-out example-assets))

(define graph-size 700)
(define plot-size 600)
(define plot-inset 50)
(define lens-radius 96)
;; Isotropic axes: one mathematical unit has the same length in x and y.
(define main-graph-camera
  (a:make-camera #:width plot-size #:height plot-size #:world-width 6
                 #:center (a:vec2 0 2)))
(define (make-lens-camera x0 y0 zoom)
  (a:make-camera #:width (* 2 lens-radius) #:height (* 2 lens-radius)
                 #:world-width (/ (* 2 lens-radius)
                                  (* (a:camera-scale main-graph-camera) zoom))
                 #:center (a:vec2 x0 y0)))

(struct example-assets (theme colors title panels captions labels coefficients) #:transparent)
(define (native-color specification theme)
  (define value (c:resolve-color specification (slide-theme-colors theme)))
  (d:make-color (inexact->exact (round (c:rgba-color-red value)))
                (inexact->exact (round (c:rgba-color-green value)))
                (inexact->exact (round (c:rgba-color-blue value)))
                (c:rgba-color-alpha value)))

;; All TeX and font construction is explicit here, before scene sampling.
;; These are a few authored lines, not a competing mixed-text implementation.
;; Codex's shared TeX-text feature can later replace just this asset builder.
(define (prepare-example-assets! theme)
  (unless (slide-theme? theme)
    (raise-argument-error 'prepare-example-assets! "slide-theme?" theme))
  (define foreground (native-color c:theme-foreground theme))
  (define colors
    (hash 'background (native-color c:theme-background theme)
          'foreground foreground
          'axis (native-color c:theme-axis theme)
          'grid (native-color c:theme-grid theme)
          'muted (native-color c:theme-muted theme)
          'graph (native-color (c:series-color 0) theme)
          'point (native-color c:theme-highlight theme)
          'secant (native-color (c:series-color 1) theme)
          'tangent (native-color c:theme-success theme)
          'lens (native-color c:theme-accent theme)))
  (define measurement-camera
    (a:make-camera #:width 1600 #:height 900 #:world-width 16))
  (define cache (make-hash))
  (define (text s [role 'body] [factor 1])
    (define style (role-style theme role))
    (define font
      (d:make-font #:size (* 100 factor (text-style-font-size style))
                   #:size-in-pixels? #t
                   #:family (text-style-font-family style)
                   #:face (text-style-font-face style)
                   #:style (text-style-font-style style)
                   #:weight (text-style-font-weight style)))
    (p:colorize (p:text s font) (native-color (text-style-color style) theme)))
  (define (math s [role 'body] [factor 1] [mode 'inline])
    (hash-ref! cache (list s role factor mode)
      (lambda ()
        (p:colorize
         (a:visual->pict
          (a:latex-formula s #:id 'example-formula #:mode mode
                          #:font-size (* factor (text-style-font-size (role-style theme role)))
                          #:preamble "\\usepackage{amsmath,amssymb}")
          measurement-camera
          #:renderers (cons default-latex-formula-pict-renderer a:default-pict-renderers)
          #:theme (slide-theme-colors theme)
          #:typography (slide-theme-typography theme))
         (native-color (text-style-color (role-style theme role)) theme)))))
  (define (row . items) (apply p:hbl-append 0 items))
  (define (card . rows)
    (define content (apply p:vl-append 21 rows))
    ;; Fixed paper geometry throughout: replacements cannot shift the graph.
    (when (or (> (p:pict-width content) 604) (> (p:pict-height content) 490))
      (raise-arguments-error 'prepare-example-assets! "example paper exceeds its fixed slot"
                             "width" (p:pict-width content) "height" (p:pict-height content)))
    (p:pin-over (p:blank 630 520) 13 12 content))
  (define (heading s) (text s 'body 1.10))
  (define theorem
    (card (heading "Sætning")
          (row (text "Funktionen ") (math "f(x)=x^2"))
          (row (text "er differentiabel i hele ") (math "\\mathbb{R}") (text ","))
          (text "og den afledede funktion er")
          (math "f'(x)=2x." 'body 1.30)))
  (define panels
    (hash
     'theorem theorem
     'slope-meaning
     (card (heading "Tangenthældningen")
           (text "Den afledede funktion er")
           (math "f'(x)=2x.")
           (row (text "Ved ") (math "x_0") (text " er hældningen"))
           (math "f'(x_0)=2x_0." 'body 1.2))
     'slope-one
     (card (heading "Eksempel") (math "x_0=1")
           (math "f'(1)=2\\cdot 1=2." 'body 1.2))
     'slope-two
     (card (heading "Eksempel") (math "x_0=2")
           (math "f'(2)=2\\cdot 2=4." 'body 1.2))
     'two-goals
     (card (row (heading "For alle ") (math "x_0\\in\\mathbb{R}" 'body 1.10))
           (text "skal vi vise:")
           (row (text "1. ") (math "f") (text " er differentiabel i ") (math "x_0") (text "."))
           (row (text "2. ") (math "f'(x_0)=2x_0.")))
     'three-steps
     (card (heading "Tretrinsreglen")
           (row (text "Lad ") (math "x_0\\in\\mathbb{R}") (text " være givet."))
           (text "1. Funktions-tilvækst")
           (text "2. Differenskvotient")
           (text "3. Grænseværdi"))
     'step-one
     (card (heading "1. Funktions-tilvækst")
           (math "P=(x_0,f(x_0))")
           (math "Q=(x_0+h,f(x_0+h))")
           (math "h\\neq 0"))
     'increments
     (card (heading "1. Funktions-tilvækst")
           (math "\\Delta x=h")
           (math "\\Delta y=f(x_0+h)-f(x_0)"))
     'dy-definition
     (card (heading "1. Funktions-tilvækst")
           (math "\\Delta y=f(x_0+h)-f(x_0)"))
     'dy-substitute
     (card (heading "1. Funktions-tilvækst")
           (math "\\begin{aligned}\\Delta y&=f(x_0+h)-f(x_0)\\\\[5pt]&=(x_0+h)^2-x_0^2\\end{aligned}"
                 'body 1 'display))
     'dy-expand
     (card (heading "1. Funktions-tilvækst")
           (math "\\begin{aligned}\\Delta y&=(x_0+h)^2-x_0^2\\\\[5pt]&=x_0^2+h^2+2x_0h-x_0^2\\end{aligned}"
                 'body 1 'display)
           (text "Første kvadratsætning" 'caption))
     'dy-cancel
     (card (heading "1. Funktions-tilvækst")
           (math "\\begin{aligned}\\Delta y&=x_0^2+h^2+2x_0h-x_0^2\\\\[5pt]&=h^2+2x_0h\\end{aligned}"
                 'body 1 'display))
     'dq-definition
     (card (heading "2. Differenskvotient")
           (math "\\frac{\\Delta y}{\\Delta x}=\\frac{h^2+2x_0h}{h}" 'body 1 'display)
           (math "h\\neq0"))
     'dq-split
     (card (heading "2. Differenskvotient")
           (math "\\begin{aligned}\\frac{\\Delta y}{\\Delta x}&=\\frac{h^2+2x_0h}{h}\\\\[7pt]&=\\frac{h^2}{h}+\\frac{2x_0h}{h}\\end{aligned}"
                 'body 1 'display)
           (math "h\\neq0"))
     'dq-cancel
     (card (heading "2. Differenskvotient")
           (math "\\begin{aligned}\\frac{\\Delta y}{\\Delta x}&=\\frac{h\\cdot h}{h}+\\frac{2x_0h}{h}\\\\[7pt]&=h+2x_0\\end{aligned}"
                 'body 1 'display)
           (math "h\\neq0"))
     'limit-start
     (card (heading "3. Grænseværdi")
           (math "\\lim_{h\\to0}\\frac{\\Delta y}{\\Delta x}=\\lim_{h\\to0}(h+2x_0)" 'body 1 'display)
           (row (math "x_0") (text " er fast. ") (math "h\\to0")))
     'limit-result
     (card (heading "3. Grænseværdi")
           (math "\\begin{aligned}\\lim_{h\\to0}\\frac{\\Delta y}{\\Delta x}&=\\lim_{h\\to0}(h+2x_0)\\\\[7pt]&=0+2x_0\\\\[5pt]&=2x_0\\end{aligned}"
                 'body 1 'display))
     'proved
     (card (heading "Begge dele er bevist")
           (row (text "1. ") (math "f") (text " er differentiabel i ") (math "x_0") (text "."))
           (row (text "2. ") (math "f'(x_0)=2x_0."))
           (text "Der var intet særligt ved valget.")
           (math "x_0\\in\\mathbb{R}"))
     'summary
     (card (heading "Tretrinsreglen")
           (math "\\begin{aligned}1.\\quad\\Delta y&=h^2+2x_0h\\\\[7pt]2.\\quad\\frac{\\Delta y}{\\Delta x}&=h+2x_0\\quad(h\\ne0)\\\\[7pt]3.\\quad f'(x_0)&=2x_0\\end{aligned}"
                 'body 1 'display))))
  (define captions
    (for/hash ([s (in-list script)])
      (define picture (text (shot-caption s) 'caption))
      (when (> (p:pict-width picture) 1440)
        (raise-arguments-error 'prepare-example-assets! "caption exceeds its fixed slot"
                               "shot" (shot-id s) "caption" (shot-caption s)))
      (values (shot-id s) picture)))
  (define labels
    (hash 'x (math "x" 'label) 'y (math "y" 'label)
          'f (math "f(x)=x^2" 'label)
          'x0 (math "x_0" 'label)
          'fx0 (math "f(x_0)" 'label)
          'Qx (math "x_0+h" 'label)
          'P (math "P" 'label) 'Q (math "Q" 'label)
          'h (math "h" 'label) 'dy (math "\\Delta y" 'label)
          'm (math "m_{\\mathrm{sekant}}=h+2x_0" 'label)
          'tangent (math "m_{\\mathrm{tangent}}=2x_0" 'label)
          'zoom (text "Zoom omkring punktet" 'caption .8)
          'ticks
          (for/hash ([n (in-range -3 6)])
            (values n (text (number->string n) 'label .75)))))
  ;; Exact quadratic interpolation of THREE VALUES OF THE MODEL'S f.
  ;; Both cameras draw this same graph; neither camera invents a substitute line.
  (define ym (sample-function -1))
  (define yz (sample-function 0))
  (define yp (sample-function 1))
  (define coefficients (list (/ (+ yp ym (- (* 2 yz))) 2) (/ (- yp ym) 2) yz))
  (unless (equal? coefficients '(1 0 0))
    (raise-user-error 'prepare-example-assets! "This exact quadratic adapter is specifically for the model f(x)=x^2."))
  (example-assets theme colors
                  (row (text "Differentiation af " 'title) (math "x^2" 'title))
                  panels captions labels coefficients))

(define (graph-picture assets state)
  (define colors (example-assets-colors assets))
  (define labels (example-assets-labels assets))
  (define model (mathematical-state (hash-ref state 'x0) (hash-ref state 'h)))
  (define P (hash-ref model 'P))
  (define Q (hash-ref model 'Q))
  (define coeff (example-assets-coefficients assets))
  (define A (first coeff)) (define B (second coeff)) (define C (third coeff))
  (define (f x) (+ (* A x x) (* B x) C))
  (define (df x) (+ (* 2 A x) B))
  (define (ink key) (hash-ref colors key))
  (define (picture key) (hash-ref labels key))
  (define-values (px py) (a:camera-world->pixel main-graph-camera (a:vec2 (car P) (cdr P))))
  (define-values (qx qy) (a:camera-world->pixel main-graph-camera (a:vec2 (car Q) (cdr Q))))
  (define (draw dc)
    (define (label key x y [align 'left])
      (define pic (picture key))
      (p:draw-pict pic dc
                   (case align [(center) (- x (/ (p:pict-width pic) 2))]
                         [(right) (- x (p:pict-width pic))] [else x]) y))
    (define (pen key width [style 'solid])
      (send dc set-pen (d:make-pen #:color (ink key) #:width width #:style style)))
    (define (with-alpha alpha thunk)
      (define old (send dc get-alpha))
      (dynamic-wind (lambda () (send dc set-alpha (* old alpha))) thunk
                    (lambda () (send dc set-alpha old))))
    (define (with-clip region thunk)
      (define previous (send dc get-clipping-region))
      (when previous (send region intersect previous))
      (dynamic-wind (lambda () (send dc set-clipping-region region)) thunk
                    (lambda () (send dc set-clipping-region previous))))
    (define (dot x y key)
      (pen key 1)
      (send dc set-brush (d:make-brush #:color (ink key)))
      (send dc draw-ellipse (- x 5) (- y 5) 10 10))
    (define (curve camera left top)
      (define center (a:vec2-x (a:camera-center camera)))
      (define half (/ (a:camera-world-width camera) 2))
      (define lo (- center half)) (define hi (+ center half))
      (define delta (/ (- hi lo) 3))
      (define (screen x y)
        (define-values (sx sy) (a:camera-world->pixel camera (a:vec2 x y)))
        (values (+ left sx) (+ top sy)))
      (define-values (x1 y1) (screen lo (f lo)))
      (define-values (c1x c1y) (screen (+ lo delta) (+ (f lo) (* delta (df lo)))))
      (define-values (c2x c2y) (screen (- hi delta) (- (f hi) (* delta (df hi)))))
      (define-values (x2 y2) (screen hi (f hi)))
      (define path (new d:dc-path%))
      (send path move-to x1 y1)
      (send path curve-to c1x c1y c2x c2y x2 y2)
      (pen 'graph 3)
      (send dc set-brush (d:make-brush #:style 'transparent))
      (send dc draw-path path))
    (define (line-through-P camera left top slope key alpha)
      (when (> alpha 0)
        (with-alpha alpha
          (lambda ()
            (define lo (- (a:vec2-x (a:camera-center camera)) (/ (a:camera-world-width camera) 2)))
            (define hi (+ lo (a:camera-world-width camera)))
            (define-values (x1 y1)
              (a:camera-world->pixel camera (a:vec2 lo (+ (cdr P) (* slope (- lo (car P)))))))
            (define-values (x2 y2)
              (a:camera-world->pixel camera (a:vec2 hi (+ (cdr P) (* slope (- hi (car P)))))))
            (pen key 2.4)
            (send dc draw-line (+ left x1) (+ top y1) (+ left x2) (+ top y2))))))
    (define-values (ox oy) (a:camera-world->pixel main-graph-camera a:origin))
    (define area (new d:region% [dc dc]))
    (send area set-rectangle plot-inset plot-inset plot-size plot-size)
    (send dc set-brush (d:make-brush #:color (ink 'background)))
    (send dc set-pen (d:make-pen #:style 'transparent))
    (send dc draw-rectangle 0 0 graph-size graph-size)
    (with-clip area
      (lambda ()
        (for ([n (in-range -3 6)])
          (define-values (xx yy) (a:camera-world->pixel main-graph-camera (a:vec2 n n)))
          (pen 'grid .6)
          (when (< -3 n 3)
            (send dc draw-line (+ plot-inset xx) plot-inset (+ plot-inset xx) (+ plot-inset plot-size)))
          (when (< -1 n 5)
            (send dc draw-line plot-inset (+ plot-inset yy) (+ plot-inset plot-size) (+ plot-inset yy))))
        (pen 'axis 1.4)
        (send dc draw-line plot-inset (+ plot-inset oy) (+ plot-inset plot-size) (+ plot-inset oy))
        (send dc draw-line (+ plot-inset ox) plot-inset (+ plot-inset ox) (+ plot-inset plot-size))
        (curve main-graph-camera plot-inset plot-inset)
        (line-through-P main-graph-camera plot-inset plot-inset (hash-ref model 'm)
                        'secant (hash-ref state 'secant))
        (line-through-P main-graph-camera plot-inset plot-inset (hash-ref model 'tangent-slope)
                        'tangent (hash-ref state 'tangent))))
    (for ([n (in-list '(-2 -1 1 2))])
      (define pic (hash-ref (hash-ref labels 'ticks) n))
      (define-values (xx yy) (a:camera-world->pixel main-graph-camera (a:vec2 n n)))
      (p:draw-pict pic dc (- (+ plot-inset xx) (/ (p:pict-width pic) 2)) (+ plot-inset oy 7)))
    (for ([n (in-list '(1 2 3 4))])
      (define pic (hash-ref (hash-ref labels 'ticks) n))
      (define-values (xx yy) (a:camera-world->pixel main-graph-camera (a:vec2 n n)))
      (p:draw-pict pic dc (- (+ plot-inset ox) (p:pict-width pic) 8) (- (+ plot-inset yy) 10)))
    (label 'x (+ plot-inset plot-size 8) (+ plot-inset oy -14))
    (label 'y (+ plot-inset ox 10) 18)
    (label 'f 48 16)
    (with-alpha (hash-ref state 'point)
      (lambda ()
        (pen 'point 1.5 'short-dash)
        (send dc draw-line (+ plot-inset px) (+ plot-inset py) (+ plot-inset px) (+ plot-inset oy))
        (dot (+ plot-inset px) (+ plot-inset oy) 'point)
        (dot (+ plot-inset px) (+ plot-inset py) 'point)
        (label 'P (+ plot-inset px 10) (+ plot-inset py -33))
        ;; Axis reading stays visible outside the magnifier.
        (label 'x0 (+ plot-inset px) (+ plot-inset oy 28) 'center)))
    (with-alpha (hash-ref state 'neighbour)
      (lambda ()
        (dot (+ plot-inset qx) (+ plot-inset qy) 'secant)
        ;; Labels are explanatory, not stretched geometric triangles.
        (when (> (hash-ref state 'h) 1/5)
          (pen 'secant 1 'short-dash)
          (send dc draw-line (+ plot-inset qx) (+ plot-inset qy) (+ plot-inset qx) (+ plot-inset oy))
          (label 'Q (+ plot-inset qx 10) (+ plot-inset qy -27))
          (label 'Qx (+ plot-inset qx) (+ plot-inset oy 28) 'center))))
    (with-alpha (hash-ref state 'triangle)
      (lambda ()
        (pen 'secant 2 'short-dash)
        (send dc draw-line (+ plot-inset px) (+ plot-inset py) (+ plot-inset qx) (+ plot-inset py))
        (send dc draw-line (+ plot-inset qx) (+ plot-inset py) (+ plot-inset qx) (+ plot-inset qy))
        (label 'h (+ plot-inset (/ (+ px qx) 2)) (+ plot-inset py 9) 'center)
        (label 'dy (+ plot-inset qx 12) (+ plot-inset (/ (+ py qy) 2) -12))))
    (when (> (hash-ref state 'secant) 0)
      (with-alpha (hash-ref state 'secant) (lambda () (label 'm 48 670))))
    (when (> (hash-ref state 'tangent) 0)
      (with-alpha (hash-ref state 'tangent) (lambda () (label 'tangent 48 670))))
    (when (> (hash-ref state 'lens) 0)
      (with-alpha (hash-ref state 'lens)
        (lambda ()
          (define left (- (+ plot-inset px) lens-radius))
          (define top (- (+ plot-inset py) lens-radius))
          (define diameter (* 2 lens-radius))
          (define mask (new d:region% [dc dc]))
          (define camera (make-lens-camera (car P) (cdr P) (hash-ref state 'zoom)))
          (send mask set-ellipse left top diameter diameter)
          (with-clip mask
            (lambda ()
              (send dc set-pen (d:make-pen #:style 'transparent))
              (send dc set-brush (d:make-brush #:color (ink 'background)))
              (send dc draw-rectangle left top diameter diameter)
              (curve camera left top)
              (line-through-P camera left top (hash-ref model 'tangent-slope)
                              'tangent (hash-ref state 'tangent))
              ;; Marker radius is cosmetic: it does NOT grow with magnification.
              (dot (+ plot-inset px) (+ plot-inset py) 'point)))
          (pen 'lens 2.5)
          (send dc set-brush (d:make-brush #:style 'transparent))
          (send dc draw-ellipse left top diameter diameter)
          (label 'zoom (- graph-size 48) 16 'right)))))
  (p:dc
   (lambda (dc x y)
     (define transform (send dc get-transformation))
     (define pen (send dc get-pen)) (define brush (send dc get-brush))
     (define alpha (send dc get-alpha)) (define clip (send dc get-clipping-region))
     (define smooth (send dc get-smoothing))
     (dynamic-wind
       (lambda () (send dc translate x y) (send dc set-smoothing 'smoothed))
       (lambda () (draw dc))
       (lambda ()
         (send dc set-transformation transform) (send dc set-clipping-region clip)
         (send dc set-pen pen) (send dc set-brush brush)
         (send dc set-alpha alpha) (send dc set-smoothing smooth))))
   graph-size graph-size))

(define (make-graph-scene assets)
  (define clock (a:parameter 'differentiation-clock 0))
  (define graph
    (a:relation-visual (a:group '() #:id 'differentiation-graph)
       #:depends-on (list (a:value-dependency 'differentiation-clock))
       #:structure 'root-only
       (lambda (context _template)
         (define time (min script-duration (max 0 (a:relation-context-value-ref context 'differentiation-clock))))
         (prepared-pict-panel (graph-picture assets (state-at time))
                              #:width 7 #:height 7 #:id 'differentiation-graph))))
  (define scn
    (a:scene-add
     (a:scene-set-value
      (a:make-scene #:camera (a:make-camera #:width graph-size #:height graph-size
                                           #:world-width 7)) clock)
     graph))
  (a:scene-play scn (a:value-to clock script-duration)
                #:duration script-duration #:easing a:linear))

;; A shared zero-duration scene gives slides a witnessed continuity identity.
;; Matching can replay time 0 -> 0 rather than crossfade two equal-looking Picts.
(define (make-paper-scene picture)
  (a:scene-add
   (a:make-scene #:camera (a:make-camera #:width 630 #:height 520 #:world-width 6.3))
   (prepared-pict-panel picture #:width 6.3 #:height 5.2 #:id 'theorem-paper)))
