#lang racket/base
(require rackunit racket/list
         (only-in pict blank)
         (prefix-in a: "../../main.rkt")
         "../../colors.rkt"
         "../main.rkt" "../pict.rkt" "../scene.rkt" "../render.rkt"
         "../private/data.rkt" "../private/sample.rkt" "../private/transition.rkt"
         "helpers.rkt")
(provide tests)

(define effects '(crossfade match push wipe cover uncover zoom fade-through))
(define directional '(push wipe cover uncover))
(define directions '(left right up down))
(define from-slide (slide #:layout 'title+body [title "From"] [body "First composition"]))
(define to-slide (slide #:layout 'title+body [title "To"] [body "Second composition"]))
(define (board tr #:motion [motion 'normal])
  (prepare-storyboard!
   (storyboard #:motion motion
     (storyboard-shot 'a (hold-slide from-slide #:duration 1))
     tr
     (storyboard-shot 'b (hold-slide to-slide #:duration 1)))))
(define (leaf-side f id)
  (filter (lambda (l) (eq? (car (frame-leaf-path l)) id)) (frame-value-leaves f)))
(define (close-box? a b)
  (for/and ([x (in-list (list (box-value-x a) (box-value-y a) (box-value-width a) (box-value-height a)))]
            [y (in-list (list (box-value-x b) (box-value-y b) (box-value-width b) (box-value-height b)))])
    (< (abs (- x y)) 1e-8)))
(define (mean-difference x y)
  (define aa (pixel-bytes x)) (define bb (pixel-bytes y))
  (check-equal? (bytes-length aa) (bytes-length bb))
  (/ (for/sum ([a (in-bytes aa)] [b (in-bytes bb)]) (abs (- a b))) (bytes-length aa)))

;; A small, wholly synthetic shared frame exercises masks, backgrounds,
;; preexisting crops, and clocks without relying on a font's geometry.
(define (raw-frame id color time #:clip [crop #f])
  (define canvas (box-value 0 0 16 9))
  (define picture (asset 'pict (blank 100 100) 1 1 1 5 'end (hash) id (hash)))
  (frame-value widescreen color
               (list (frame-leaf (list id 'figure) (box-value 2 2 4 3) picture time 1 1 #f crop))
               (hash (list id 'figure) (box-value 1 1 14 7)) canvas
               (list (list (box-value 1 1 14 1/10) color 1))))
(define ra (raw-frame 'a (rgb-color 255 0 0) 2))
(define rb (raw-frame 'b (rgb-color 0 0 255) 0))

(define tests
  (test-suite
   "slide transition policies and shared composition"
   (test-case "constructor exposes immutable transition configuration"
     (for ([effect (in-list effects)])
       (define tr (slide-transition #:effect effect))
       (check-true (slide-transition? tr))
       (check-equal? (slide-transition-effect tr) effect)
       (check-equal? (slide-transition-duration tr) 0.6)
       (check-equal? (slide-transition-easing tr) 'linear))
     (check-equal? (slide-transition-direction (slide-transition #:effect 'push)) 'left)
     (check-equal? (slide-transition-scale (slide-transition #:effect 'zoom)) 0.85)
     (check-equal? (slide-transition-duration (storyboard-cut)) 0))
   (test-case "inapplicable and malformed options fail early"
     (for ([make (in-list
                 (list (lambda () (slide-transition #:effect 'cube))
                       (lambda () (slide-transition #:direction 'left))
                       (lambda () (slide-transition #:effect 'push #:direction 'diagonal))
                       (lambda () (slide-transition #:effect 'wipe #:keys '(x)))
                       (lambda () (slide-transition #:effect 'zoom #:scale 0))
                       (lambda () (slide-transition #:effect 'zoom #:scale 1))
                       (lambda () (slide-transition #:effect 'zoom #:scale +inf.0))
                       (lambda () (slide-transition #:scale 0.8))
                       (lambda () (slide-transition #:color "red"))
                       (lambda () (slide-transition #:effect 'fade-through #:color 'bogus))
                       (lambda () (slide-transition #:easing 'spring))
                       (lambda () (slide-transition #:duration 0))))])
       (check-exn exn:fail? make)))
   (test-case "transparent midpoint and directional backdrops are diagnosed"
     (check-exn (code? 'transition-color)
       (lambda () (board (slide-transition #:effect 'fade-through #:color (rgba-color 0 0 0 0.5)))))
     (define transparent-theme
       (slide-theme #:id 'transparent
         #:colors (color-theme #:id 'transparent #:extends animate-light-theme
                     #:roles (hash 'background (rgba-color 0 0 0 0)))))
     (check-exn (code? 'transition-background)
       (lambda ()
         (prepare-storyboard!
          (storyboard #:theme transparent-theme
            (storyboard-shot 'a (hold-slide from-slide #:duration 1))
            (slide-transition #:effect 'push)
            (storyboard-shot 'b (hold-slide to-slide #:duration 1)))))))
   (test-case "easing is bounded monotone and exact at endpoints"
     (for ([easing (in-list '(linear smooth ease-in ease-out ease-in-out))])
       (check-equal? (transition-progress easing 0) 0)
       (check-equal? (transition-progress easing 1) 1)
       (define ps (for/list ([i (in-range 101)]) (transition-progress easing (/ i 100))))
       (for ([a (in-list ps)] [b (in-list (cdr ps))]) (check-true (<= 0 a b 1))))
     (check-equal? (transition-progress 'ease-in 1/2) 1/4)
     (check-equal? (transition-progress 'ease-out 1/2) 3/4)
     (check-equal? (transition-progress 'smooth 1/2) 1/2))
   (test-case "bridges preserve exact endpoints and add duration"
     (for ([effect (in-list effects)])
       (define b (board (slide-transition #:effect effect #:duration 1)))
       (check-equal? (prepared-duration b) 3)
       (check-equal? (sample-signature (sample-storyboard b 1))
                     (sample-signature (prefix-frame (sample-slide (storyboard-ref b 'a) 'end) 'a)))
       (check-equal? (sample-signature (sample-storyboard b 2))
                     (sample-signature (prefix-frame (sample-slide (storyboard-ref b 'b) 'start) 'b)))))
   (test-case "directional backgrounds tile the canvas and clocks stay frozen"
     (for* ([effect (in-list directional)] [direction (in-list directions)]
            [p (in-list '(1/100 1/4 1/2 3/4 99/100))])
       (define f (directional-bridge ra rb effect direction p))
       ;; First decoration is source backdrop. The destination backdrop has
       ;; full perpendicular extent and is distinct from the thin title rules.
       (define backgrounds
         (filter (lambda (d) (or (= (box-value-width (car d)) 16)
                                  (= (box-value-height (car d)) 9)))
                 (frame-value-decorations f)))
       (check-equal? (length backgrounds) 2)
       (check-= (for/sum ([d (in-list backgrounds)])
                  (* (box-value-width (car d)) (box-value-height (car d)))) 144 1e-8)
       (for ([l (in-list (frame-value-leaves f))])
         (check-equal? (frame-leaf-time l) (if (eq? (car (frame-leaf-path l)) 'a) 2 0))
         (define c (frame-leaf-clip l))
         (check-true (and (>= (box-value-x c) 0) (>= (box-value-y c) 0)
                          (<= (+ (box-value-x c) (box-value-width c)) 16)
                          (<= (+ (box-value-y c) (box-value-height c)) 9))))))
   (test-case "push moves both panels while wipe moves neither"
     (define push (directional-bridge ra rb 'push 'left 1/2))
     (define wipe (directional-bridge ra rb 'wipe 'left 1/2))
     (check-= (box-value-x (frame-leaf-box (car (leaf-side push 'a)))) -6 1e-8)
     (check-= (box-value-x (frame-leaf-box (car (leaf-side push 'b)))) 10 1e-8)
     (check-= (box-value-x (frame-leaf-box (car (leaf-side wipe 'a)))) 2 1e-8)
     (check-= (box-value-x (frame-leaf-box (car (leaf-side wipe 'b)))) 2 1e-8))
   (test-case "cover and uncover move only the designated panel"
     (define cover (directional-bridge ra rb 'cover 'up 1/2))
     (define uncover (directional-bridge ra rb 'uncover 'up 1/2))
     (check-= (box-value-y (frame-leaf-box (car (leaf-side cover 'a)))) 2 1e-8)
     (check-= (box-value-y (frame-leaf-box (car (leaf-side cover 'b)))) 13/2 1e-8)
     (check-= (box-value-y (frame-leaf-box (car (leaf-side uncover 'a)))) -5/2 1e-8)
     (check-= (box-value-y (frame-leaf-box (car (leaf-side uncover 'b)))) 2 1e-8))
   (test-case "existing figure crops are intersected, never discarded"
     (define cropped (raw-frame 'a (rgb-color 255 0 0) 2 #:clip (box-value 3 2 2 3)))
     (define f (directional-bridge cropped rb 'wipe 'left 3/4))
     (check-true (close-box? (frame-leaf-clip (car (leaf-side f 'a))) (box-value 3 2 1 3))))
   (test-case "zoom scales boxes and crop geometry about the canvas center"
     (define f (zoom-frame ra 1/2))
     (check-true (close-box? (frame-leaf-box (car (frame-value-leaves f))) (box-value 5 13/4 2 3/2)))
     (check-equal? (frame-leaf-time (car (frame-value-leaves f))) 2))
   (test-case "fade-through has an exact solid-color midpoint"
     (define color (rgb-color 12 34 56))
     (define f (fade-through-frame ra rb color 1/2))
     (check-equal? (frame-value-background f) color)
     (check-true (andmap (lambda (l) (= (frame-leaf-opacity l) 0)) (frame-value-leaves f)))
     (check-true (andmap (lambda (d) (= (caddr d) 0)) (frame-value-decorations f))))
   (test-case "reduced motion preserves bridge timing without spatial movement"
     (define reference (board (slide-transition #:duration 1 #:easing 'smooth) #:motion 'reduced))
     (for ([effect (in-list '(match push wipe cover uncover zoom))])
       (define b (board (slide-transition #:effect effect #:duration 1 #:easing 'smooth) #:motion 'reduced))
       (check-equal? (prepared-duration b) (prepared-duration reference))
       (for ([t (in-list '(1 5/4 3/2 7/4 2))])
         (check-equal? (sample-signature (sample-storyboard b t))
                       (sample-signature (sample-storyboard reference t))))))
   (test-case "directional text, backgrounds, and chrome agree in both adapters"
     (define colors-a (color-theme #:id 'transition-a #:extends animate-light-theme
                                  #:roles (hash 'background "#FFF1D6")))
     (define colors-b (color-theme #:id 'transition-b #:extends animate-dark-theme
                                  #:roles (hash 'background "#142C46")))
     (define ta (slide-theme #:id 'a #:extends lecture-light #:colors colors-a #:decorations (hash 'title-rule? #t)))
     (define tb (slide-theme #:id 'b #:extends lecture-dark #:colors colors-b #:decorations (hash 'title-rule? #t)))
     (for* ([effect (in-list effects)]
            [direction (in-list (if (memq effect directional) directions '(#f)))])
       (define b (prepare-storyboard!
         (storyboard
           (storyboard-shot 'a (hold-slide (slide #:theme ta #:layout 'title [title "LEFT"] [subtitle "Outgoing"]) #:duration 1))
           (slide-transition #:effect effect #:duration 1 #:direction direction #:easing 'smooth)
           (storyboard-shot 'b (hold-slide (slide #:theme tb #:layout 'title [title "RIGHT"] [subtitle "Incoming"]) #:duration 1)))))
       (define s (storyboard->scene b #:size '(320 180)))
       (for ([t (in-list '(2 7/4 3/2 5/4 1 0 3))])
         (define direct (storyboard->pict b #:at t #:size '(320 180)))
         (define native (a:scene-state->pict (a:scene-sample s t) #:camera (a:scene-camera-at s t)))
         (check-true (< (mean-difference direct native) 0.05) (format "~a ~a at ~a" effect direction t)))))
   (test-case "reverse and repeated seeking is history-independent"
     (for ([effect (in-list effects)])
       (define b (board (slide-transition #:effect effect #:duration 1)))
       (define times '(0 1 5/4 3/2 7/4 2 3))
       (define expected (for/hash ([t (in-list times)]) (values t (sample-signature (sample-storyboard b t)))))
       (for ([t (in-list (append (reverse times) times (reverse times)))])
         (check-equal? (sample-signature (sample-storyboard b t)) (hash-ref expected t)))))))
(module+ test
  (require rackunit/text-ui)
  (unless (zero? (run-tests tests)) (error 'transitions-test "failed")))
