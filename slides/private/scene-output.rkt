#lang racket/base
(require racket/list racket/match
         (prefix-in a: "../../main.rkt")
         (prefix-in c: "../../colors.rkt")
         (prefix-in at: "../../authoring.rkt")
         "../../private/prepared-pict-visual.rkt"
         "data.rkt" "check.rkt" "prepare.rkt" "sample.rkt" "draw.rkt" "native.rkt" "schedule.rkt")
(provide slide->scene storyboard->scene storyboard->timeline scene-slot-ref scene-slot-id
         scene-content visual-content)

(define (scene-content scene #:fit [fit 'contain] #:poster [poster 'end] #:media [media #f] #:background? [background? #f])
  (unless (or (a:scene? scene) (at:authored-timeline? scene))
    (raise-argument-error 'scene-content "scene or authored timeline" scene))
  (check-enum 'scene-content fit '(contain cover natural))
  (when media (check-enum 'scene-content media '(visual-only import)))
  (when (and (at:authored-timeline? scene) (not media)
             (or (pair? (at:authored-timeline-audio-cues scene)) (pair? (at:authored-timeline-subtitles scene))))
    (slides-error 'embedded-media-policy '() "an authored timeline with media needs #:media 'import or 'visual-only"))
  (unless (boolean? background?) (raise-argument-error 'scene-content "boolean?" background?))
  (content-value 'scene scene (hash 'fit fit 'poster poster 'media (or media 'visual-only) 'background? background?)))
(define (visual-content visual #:fit [fit 'contain] #:width [width #f] #:height [height #f])
  (unless (a:visual? visual) (raise-argument-error 'visual-content "visual?" visual))
  (check-enum 'visual-content fit '(contain cover natural))
  (when width (check-number 'visual-content width #t))
  (when height (check-number 'visual-content height #t))
  (content-value 'visual visual (hash 'fit fit 'width width 'height height)))

;; Slot IDs use length-prefixed components, so author IDs containing '/', ':'
;; or other punctuation cannot alias another occurrence's qualified slot.
(define (encode ids)
  (string->symbol
   (string-append "$slides/"
                  (apply string-append
                         (for/list ([id (in-list ids)])
                           (define s (symbol->string id)) (format "~a:~a" (string-length s) s))))))
(define (scene-slot-id path)
  (define ids (selector-path path))
  (encode ids))
(define (scene-slot-ref scene target #:at [time (a:scene-duration scene)])
  ;; A symbol names an isolated slide slot. (shot slot) qualifies a storyboard
  ;; occurrence. This returns its current concrete, animatable native group.
  (define id (scene-slot-id target))
  (a:scene-state-resolved-ref (a:scene-sample scene time) id))
(define (clip-path width height)
  (a:polygon-path (list (a:vec2 (- (/ width 2)) (- (/ height 2)))
                       (a:vec2 (/ width 2) (- (/ height 2)))
                       (a:vec2 (/ width 2) (/ height 2))
                       (a:vec2 (- (/ width 2)) (/ height 2)))))
(define (box-center b format)
  (a:vec2 (- (+ (box-value-x b) (/ (box-value-width b) 2)) (/ (format-value-width format) 2))
          (- (/ (format-value-height format) 2) (+ (box-value-y b) (/ (box-value-height b) 2)))))
(define (leaf->visual leaf id format)
  (define b (frame-leaf-box leaf)) (define asset (frame-leaf-asset leaf))
  (define pulse (frame-leaf-scale leaf))
  (define content
    (if (eq? (asset-kind asset) 'pict)
        (prepared-pict-panel (asset-value asset) #:width (asset-width asset) #:height (asset-height asset) #:id id)
        (native-asset->visual asset (frame-leaf-time leaf) id)))
  (define w (asset-width asset)) (define h (asset-height asset))
  (define placed
    (a:visual-with-opacity
     (a:visual-with-transform content
       (a:make-affine-transform #:translation (box-center b format)
         #:scale (a:vec2 (if (= w 0) 1 (max 1e-12 (* pulse (/ (box-value-width b) w))))
                         (if (= h 0) 1 (max 1e-12 (* pulse (/ (box-value-height b) h)))))))
     (frame-leaf-opacity leaf)))
  (cond [(frame-leaf-clip leaf)
         (define clip (frame-leaf-clip leaf))
         (define cc (box-center clip format))
         (a:clip-visual (a:visual-with-position placed (a:vec2- (a:visual-position placed) cc))
                        (clip-path (box-value-width clip) (box-value-height clip))
                        #:id (encode (list id '$clip)) #:center cc)]
        [else placed]))
(define (slot-key path storyboard?) (take path (if storyboard? 2 1)))
(define (frame-slot-visual f key storyboard?)
  (define format (frame-value-format f))
  (define rectangle (hash-ref (frame-value-slots f) key #f))
  (define center (if rectangle (box-center rectangle format) a:origin))
  (define selected
    (filter (lambda (l) (equal? key (slot-key (frame-leaf-path l) storyboard?)))
            (frame-value-leaves f)))
  (define children
    (for/list ([l (in-list selected)] [index (in-naturals)])
      (define child
        (leaf->visual l (encode (append (frame-leaf-path l)
                                       (list (string->symbol (number->string index))))) format))
      (a:visual-with-position child (a:vec2- (a:visual-position child) center))))
  ;; The root anchor is the slot's center, not the center of the entire slide.
  ;; Author-appended native transforms therefore behave like normal objects.
  (a:group
   (list
    (a:clip-visual
     (a:group children #:id (encode (append key (list '$content-group))))
     (a:path-geometry-map-points
      (clip-path (format-value-width format) (format-value-height format))
      (lambda (p) (a:vec2- p center)))
     #:id (encode (append key (list '$canvas-clip)))))
   #:id (scene-slot-id key) #:center center))
(define (frame-background f)
  (a:rectangle #:id '$slides-background #:width (format-value-width (frame-value-format f))
               #:height (format-value-height (frame-value-format f)) #:fill (frame-value-background f)
               #:stroke-width 0 #:stroke (c:rgba-color 0 0 0 0)))
(define (frame-decoration f)
  (a:group
   (for/list ([entry (in-list (frame-value-decorations f))] [i (in-naturals)])
     (define b (car entry))
     (a:rectangle #:id (encode (list '$decoration (string->symbol (number->string i))))
                  #:center (box-center b (frame-value-format f))
                  #:width (box-value-width b) #:height (box-value-height b)
                  #:fill (cadr entry) #:opacity (if (pair? (cddr entry)) (caddr entry) 1) #:stroke-width 0 #:stroke (c:rgba-color 0 0 0 0)))
   #:id '$slides-chrome))
(define (all-slot-keys source storyboard?)
  (if storyboard?
      (append-map
       (lambda (shot)
         (map (lambda (s) (list (prepared-shot-id shot) (prepared-slot-name s)))
              (prepared-slide-value-slots (prepared-clip-value-slide (prepared-shot-clip shot)))))
       (prepared-storyboard-value-shots source))
      (map (lambda (s) (list (prepared-slot-name s)))
           (prepared-slide-value-slots (if (prepared-clip-value? source) (prepared-clip-value-slide source) source)))))
(define (source->scene prepared storyboard? size fit)
  (define raw-sampler
    (if storyboard?
        (lambda (t) (sample-storyboard prepared t))
        (lambda (t) (sample-slide prepared t))))
  ;; The native Scene drives one semantic clock by interpolation. Canonicalize
  ;; values infinitesimally close to authored boundaries before selecting a
  ;; shot/beat, so an exact cut has the same endpoint meaning as `slide->pict`.
  (define (sampler t)
    (raw-sampler (canonical-scene-time prepared storyboard? t)))
  (define duration (prepared-duration prepared))
  (define first (sampler 0))
  (define format (frame-value-format first))
  (define-values (width height) (output-size format size))
  (check-enum 'slide->scene fit '(error letterbox))
  (unless (or (eq? fit 'letterbox) (< (abs (- (/ width height) (/ (format-value-width format) (format-value-height format)))) 1e-8))
    (slides-error 'output-aspect '() "scene output aspect differs; select #:fit 'letterbox"))
  (define world-width (max (format-value-width format) (* (format-value-height format) (/ width height))))
  (define camera (a:make-camera #:width width #:height height #:world-width world-width #:background (frame-value-background first)))
  (define (background-for f)
    (a:rectangle #:id '$slides-background #:width world-width #:height (* world-width (/ height width))
                 #:fill (frame-value-background f) #:stroke-width 0 #:stroke (c:rgba-color 0 0 0 0)))
  (define keys (all-slot-keys prepared storyboard?))
  (define initial (a:make-scene #:camera camera))
  (cond
    [(= duration 0)
     (apply a:scene-add initial (append (list (background-for first) (frame-decoration first))
                                       (map (lambda (key) (frame-slot-visual first key storyboard?)) keys)))]
    [else
     (define clock (a:parameter '$slides-clock 0))
     (define (relation template getter)
       (a:relation-visual template #:depends-on (list (a:value-dependency '$slides-clock)) #:structure 'root-only
         (lambda (ctx template)
           (getter (sampler (a:relation-context-value-ref ctx '$slides-clock))))))
     (define start
       (apply a:scene-add (a:scene-set-value initial clock)
              (append (list (relation (background-for first) background-for)
                            (relation (frame-decoration first) frame-decoration))
                      (for/list ([key (in-list keys)])
                        (relation (a:group '() #:id (scene-slot-id key))
                                  (lambda (f) (frame-slot-visual f key storyboard?)))))))
     (define animated (a:scene-play start (a:value-to clock duration) #:duration duration #:easing a:linear))
     ;; Freeze the current endpoint into ordinary concrete slot groups. Native
     ;; scene-play appended by the author can now animate those groups without
     ;; a live slide resolver overwriting its changes. Historical clips retain
     ;; their pure clock-driven relations for random-access sampling.
     (define endpoint (sampler duration))
     (define clean (apply a:scene-remove animated (append (list '$slides-background '$slides-chrome) (map scene-slot-id keys))))
     (define clean-clock (a:scene-remove-value clean '$slides-clock))
     (apply a:scene-add clean-clock (append (list (background-for endpoint) (frame-decoration endpoint))
                                          (map (lambda (key) (frame-slot-visual endpoint key storyboard?)) keys)))]))
(define (slide->scene source #:theme [theme #f] #:format [format #f] #:size [size #f] #:fit [fit 'error])
  (source->scene (resolve-slide source #:theme theme #:format format) #f size fit))
(define (storyboard->scene source #:size [size #f] #:fit [fit 'error])
  (source->scene (resolve-storyboard source) #t size fit))
(define (storyboard->timeline source #:size [size #f] #:fit [fit 'error])
  (define board (resolve-storyboard source))
  (define scene (source->scene board #t size fit))
  (define sections
    (for/list ([shot (in-list (prepared-storyboard-value-shots board))]
               #:when (> (prepared-clip-value-duration (prepared-shot-clip shot)) 0))
      (at:section (prepared-shot-id shot) (prepared-shot-start shot)
                  (+ (prepared-shot-start shot) (prepared-clip-value-duration (prepared-shot-clip shot))))))
  (define cues '()) (define audio '()) (define captions '())
  (define subtitles? (storyboard-value-subtitles? (prepared-storyboard-value-source board)))
  (for ([shot (in-list (prepared-storyboard-value-shots board))])
    (define clip (prepared-shot-clip shot))
    (define offset (prepared-shot-start shot))
    (for ([beat (in-list (prepared-clip-value-beats clip))])
      (define start (+ offset (prepared-beat-start beat)))
      (define end (+ start (prepared-beat-duration beat)))
      (set! cues (append cues (list (at:cue (encode (list (prepared-shot-id shot) (prepared-beat-name beat) 'start)) start)
                                    (at:cue (encode (list (prepared-shot-id shot) (prepared-beat-name beat) 'end)) end))))
      (define n (prepared-beat-narration beat))
      (when n
        (define t (+ start (prepared-narration-start n)))
        (when (prepared-narration-audio n)
          (set! audio (append audio (list (at:audio-cue (prepared-narration-audio n) #:start t
                                           #:source-start (prepared-narration-source-start n) #:duration (prepared-narration-duration n))))))
        (when subtitles?
          (set! captions (append captions
             (for/list ([c (in-list (prepared-narration-captions n))])
               (at:subtitle (+ t (car c)) (+ t (cadr c)) (caddr c))))))))
    ;; Import child media only while its local clock actually advances. Frozen
    ;; transition endpoints and post-play holds never replay an audio cue.
    (for ([e (in-list (prepared-clip-value-events clip))] #:when (eq? (event-kind e) 'play))
      (define slot (findf (lambda (s) (eq? (prepared-slot-name s) (car (event-target e))))
                          (prepared-slide-value-slots (prepared-clip-value-slide clip))))
      (define leaf (car (list-ref (prepared-slot-variants slot) (event-variant e))))
      (define metadata (asset-metadata (prepared-leaf-asset leaf)))
      (define child-audio (hash-ref metadata 'audio '()))
      (define child-subtitles (hash-ref metadata 'subtitles '()))
      (when (and (pair? child-audio) (> (abs (- (event-duration e) (- (event-to e) (event-from e)))) 1e-8))
        (slides-error 'audio-retime (event-target e) "imported audio cannot be stretched; use visual-only or keep native duration"))
      (define start (+ offset (event-start e)))
      (define (map-time x) (+ start (* (if (= (event-to e) (event-from e)) 0
                                          (/ (event-duration e) (- (event-to e) (event-from e))))
                                      (- x (event-from e)))))
      (for ([q (in-list child-audio)])
        (unless (at:audio-cue-duration q)
          (slides-error 'unbounded-child-audio (event-target e) "imported audio cues need explicit durations"))
        (define from (max (event-from e) (at:audio-cue-start q)))
        (define to (min (event-to e) (+ (at:audio-cue-start q) (at:audio-cue-duration q))))
        (when (< from to)
          (define whole? (and (= from (at:audio-cue-start q))
                              (= to (+ (at:audio-cue-start q) (at:audio-cue-duration q)))))
          (when (and (not whole?)
                     (or (> (at:audio-cue-fade-in q) 0) (> (at:audio-cue-fade-out q) 0)))
            (slides-error 'trimmed-audio-envelope (event-target e)
                          "play the whole faded audio cue, or supply an explicitly trimmed recording"))
          (set! audio (append audio (list
            (at:audio-cue (at:audio-cue-source q) #:start (map-time from)
                          #:source-start (+ (at:audio-cue-source-start q) (- from (at:audio-cue-start q)))
                          #:duration (- to from) #:gain (at:audio-cue-gain q)
                          #:fade-in (if whole? (at:audio-cue-fade-in q) 0)
                          #:fade-out (if whole? (at:audio-cue-fade-out q) 0)))))))
      (when subtitles?
        (for ([q (in-list child-subtitles)])
          (define from (max (event-from e) (at:subtitle-start q))) (define to (min (event-to e) (at:subtitle-end q)))
          (when (< from to) (set! captions (append captions (list (at:subtitle (map-time from) (map-time to) (at:subtitle-cue-text q))))))))))
  (define sorted-captions (sort captions < #:key at:subtitle-start))
  (for ([a (in-list sorted-captions)] [b (in-list (if (null? sorted-captions) '() (cdr sorted-captions)))])
    (when (> (at:subtitle-end a) (at:subtitle-start b))
      (slides-error 'subtitle-overlap '() "parent and imported subtitles overlap; choose one transcript or visual-only embedding")))
  (at:make-authored-timeline scene #:sections sections #:cues cues #:audio-cues audio #:subtitles sorted-captions))
