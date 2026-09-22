#lang racket/base
;; Differentiation af x^2 — a slides production following the original video.
;; Revised from f1bd4f983bffbedddbeed18864f082b71651c5ce, same example path.
;; Requiring this module never starts TeX, video rendering, or file output.
(require racket/list racket/class racket/file racket/path racket/cmdline json
         (prefix-in p: pict)
         (prefix-in a: animate)
         animate/slides animate/slides/render animate/slides/pict animate/slides/scene
         animate/project
         "private/differentiation-model.rkt"
         "private/differentiation-script.rkt"
         "private/differentiation-visuals.rkt")
(provide make-differentiate-x-squared-film!
         prepare-differentiate-x-squared!
         make-differentiate-x-squared-project!
         differentiate-x-squared-model
         script film-duration theorem-duration transition-duration
         write-differentiation-review!)

;; Use the same named theorem content in both layouts. It moves to the left;
;; it is not abbreviated or replaced by f'(x)=2x alone.
(define theorem-layout
  (layout #:id 'differentiation-theorem
          #:slots (list (slot-spec 'title #:required? #t #:role 'title)
                        (slot-spec 'theorem #:required? #t #:role 'body)
                        (slot-spec 'caption #:role 'caption))
          #:arrange
          (vbox #:gap .25
                (region 'title #:basis .9 #:align 'center #:valign 'center)
                (region 'theorem #:grow 1 #:align 'center #:valign 'center)
                (region 'caption #:basis .7 #:align 'center #:valign 'center))
          #:fallback 'wide))
(define split-layout
  (layout #:id 'differentiation-split
          #:slots (list (slot-spec 'title #:required? #t #:role 'title)
                        (slot-spec 'theorem #:required? #t #:role 'body)
                        (slot-spec 'graph #:required? #t #:role 'body)
                        (slot-spec 'caption #:role 'caption))
          #:arrange
          (vbox #:gap .25
                (region 'title #:basis .9 #:align 'center #:valign 'center)
                (hbox #:grow 1 #:gap .5
                      (region 'theorem #:basis 6.3 #:valign 'center)
                      (region 'graph #:grow 1 #:align 'center #:valign 'center))
                (region 'caption #:basis .7 #:align 'center #:valign 'center))
          #:fallback 'wide))

(define (make-differentiate-x-squared-film! #:theme [theme lecture-light])
  (define assets (prepare-example-assets! theme))
  (define panel-picts (example-assets-panels assets))
  (define theorem-content
    (content-state
     (scene-content (make-paper-scene (hash-ref panel-picts 'theorem)))
     #:at 0 #:viewport '(6.3 5.2)))
  (define (panel key)
    (if (eq? key 'theorem) theorem-content
        (pict-content (hash-ref panel-picts key) #:fit 'natural)))
  (define title-content (pict-content (example-assets-title assets) #:fit 'natural))
  (define opening
    (slide #:id 'theorem #:layout theorem-layout
      [title title-content]
      [theorem #:key 'theorem #:fit 'natural theorem-content]
      [caption ""]))
  (define explanation
    (slide #:id 'explanation #:layout split-layout
      [title title-content]
      [theorem #:key 'theorem #:fit 'natural theorem-content]
      [graph (scene-content (make-graph-scene assets) #:fit 'contain)]
      [caption (pict-content (hash-ref (example-assets-captions assets) 'graf) #:fit 'natural)]))
  (define opening-clip
    (build-slide opening
      (beat 'introduce-theorem
            #:narration
            (make-narration
             "Vi skal se på, hvordan man differentierer x i anden. Funktionen f af x lig med x i anden er differentiabel i hele R, og den afledede funktion er f mærke x lig med to x. Lad os først se på, hvad sætningen betyder."
             #:draft-duration theorem-duration #:captions '()))))
  (define-values (beats ignored-time ignored-panel)
    (for/fold ([beats '()] [offset 0] [previous-panel 'theorem]) ([s (in-list script)])
      (define duration (shot-duration s))
      (define actions
        (append
         (list (play-content 'graph #:from offset #:to (+ offset duration)
                                    #:duration duration))
         (if (eq? previous-panel (shot-panel s)) '()
             (list (replace-content 'theorem (panel (shot-panel s))
                                    #:duration 1/2)))
         (list (replace-content 'caption
                                (pict-content (hash-ref (example-assets-captions assets) (shot-id s))
                                              #:fit 'natural)
                                #:duration 2/5))))
      (values
       (append beats
               (list (apply beat (shot-id s)
                            #:duration duration
                            #:narration (make-narration (shot-narration s)
                                                       #:draft-duration duration #:captions '())
                            actions)))
       (+ offset duration) (shot-panel s))))
  (storyboard #:id 'differential-quotient-x-squared
              #:theme theme #:format widescreen #:subtitles? #f
    (storyboard-shot 'saetning opening-clip)
    ;; Witnessed time-0 -> time-0 replay moves the same theorem scene. There
    ;; is no guessed glyph matching or double-painted text crossfade.
    (slide-transition #:effect 'match #:keys '(theorem)
                      #:depth 'semantic #:duration transition-duration #:easing 'smooth)
    (storyboard-shot 'forklaring (apply build-slide explanation beats))))

(define (prepare-differentiate-x-squared! #:theme [theme lecture-light])
  (prepare-storyboard! (make-differentiate-x-squared-film! #:theme theme)))

;; Existing project/render pipeline; explicit in-process execution avoids
;; promising serialization of this example's custom prepared viewport closure.
(define (make-differentiate-x-squared-project! #:theme [theme lecture-light]
                                              #:width [width 1920] #:height [height 1080]
                                              #:fps [fps 30]
                                              #:output [output "rendered-examples"])
  (define prepared (prepare-differentiate-x-squared! #:theme theme))
  (animate-project
   #:id 'differential-quotient-x-squared
   #:source (timeline-source (storyboard->timeline prepared #:size (list width height)))
   #:render (render-spec #:fps fps #:width width #:height height
                         #:workers 1 #:worker-mode 'in-process #:quality 'final
                         #:theme (slide-theme-colors theme)
                         #:typography (slide-theme-typography theme))
   #:output (output-spec #:root output #:name "differential-quotient-x-squared"
                         #:format 'mp4 #:write-frame-sequence? #f #:overwrite-policy 'replace)
   #:encoder (encoder-spec #:codec 'h264 #:pixel-format 'yuv420p
                           #:options #hasheq((crf . "20")))
   #:cache (cache-spec #:policy 'off)))

(define review-shots
  '(vaelg-punkt hold-foerste andet-punkt hold-andet tangent-i-lup
    haeldning eksempel-et eksempel-to dy-kvadrat dq-del-broek
    graense-approach graense-regn tilbage-til-saetning opsamling))
(define (write-differentiation-review! destination #:theme [theme lecture-light]
                                     #:width [width 1280] #:height [height 720])
  (when (directory-exists? destination)
    (raise-user-error 'review "Choose a fresh review directory: ~a" destination))
  (make-directory* destination)
  (define prepared (prepare-differentiate-x-squared! #:theme theme))
  (define selected
    (append (list (cons 'saetning 8)
                  (cons 'overgang (+ theorem-duration (/ transition-duration 2))))
            (for/list ([id (in-list review-shots)])
              (define s (findf (lambda (s) (eq? id (shot-id s))) script))
              (cons id (+ theorem-duration transition-duration
                          (hash-ref shot-offsets id) (shot-duration s) -1/4)))))
  (define rows
    (for/list ([entry (in-list selected)] [i (in-naturals 1)])
      (define filename (format "~a-~a.png" i (car entry)))
      (define picture (storyboard->pict prepared #:at (cdr entry) #:size (list width height)))
      (unless (send (p:pict->bitmap picture) save-file (build-path destination filename) 'png)
        (raise-user-error 'review "Could not write ~a" filename))
      (hash 'id (symbol->string (car entry)) 'time (exact->inexact (cdr entry)) 'file filename)))
  (call-with-output-file (build-path destination "manifest.json") #:exists 'error
    (lambda (out)
      (write-json (hash 'racket (version) 'title "Differentiation af x^2"
                        'duration (exact->inexact (prepared-duration prepared))
                        'theme (symbol->string (slide-theme-id theme)) 'frames rows) out)))
  (call-with-output-file (build-path destination "index.html") #:exists 'error
    (lambda (out)
      (display "<!doctype html><meta charset='utf-8'><title>Differentiation af x²</title><style>body{font:18px system-ui;margin:2rem;max-width:1400px}figure{margin:2rem 0}img{max-width:100%;height:auto;border:1px solid #888}</style><h1>Differentiation af x²</h1>" out)
      (for ([r (in-list rows)])
        (fprintf out "<figure><img src='~a'><figcaption>~a — ~as</figcaption></figure>"
                 (hash-ref r 'file) (hash-ref r 'id) (hash-ref r 'time)))))
  destination)

(module+ main
  (define mode 'review)
  (define output #f)
  (define theme lecture-light)
  (define width 1920) (define height 1080) (define fps 30)
  (define (integer-option text who)
    (define n (string->number text))
    (unless (exact-positive-integer? n)
      (raise-user-error who "expected a positive integer: ~a" text)) n)
  (command-line
   #:program "differential-quotient-x-squared.rkt"
   #:once-any
   [("--review") "Render selected storyboard PNGs and HTML (default)." (set! mode 'review)]
   [("--render") "Render the complete MP4 through animate/project." (set! mode 'render)]
   [("--list") "Print manuscript beats without preparing TeX." (set! mode 'list)]
   #:once-each
   [("--output") path "Fresh review directory, or video output root." (set! output path)]
   [("--dark") "Use lecture-dark." (set! theme lecture-dark)]
   [("--width") w "Output width." (set! width (integer-option w 'width))]
   [("--height") h "Output height." (set! height (integer-option h 'height))]
   [("--fps") f "Video frames per second." (set! fps (integer-option f 'fps))]
   #:args () (void))
  (unless (= (* width 9) (* height 16))
    (raise-user-error 'output "This authored example uses 16:9; supply a matching width and height."))
  (case mode
    [(list)
     (printf "Differentiation af x^2 — ~a seconds (silent draft narration)\n" film-duration)
     (printf "0 — saetning (~as)\n" theorem-duration)
     (for ([s (in-list script)])
       (printf "~a — ~a (~as): ~a\n"
               (+ theorem-duration transition-duration (hash-ref shot-offsets (shot-id s)))
               (shot-id s) (shot-duration s) (shot-narration s)))]
    [(review)
     (displayln (write-differentiation-review! (or output "slides-output/differentiation-review")
                                              #:theme theme #:width width #:height height))]
    [(render)
     ;; Load the effectful renderer only for an explicit video request.
     (define render! (dynamic-require 'animate/render 'render-project!))
     (render! (make-differentiate-x-squared-project! #:theme theme
                                                   #:width width #:height height #:fps fps
                                                   #:output (or output "rendered-examples")))]))
