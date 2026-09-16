#lang racket/base

;; Loaded only by the native adapter, or when a static composition contains
;; explicitly native content. All slide geometry has already been fixed.
(require racket/list racket/match racket/runtime-path
         (prefix-in p: pict)
         (prefix-in a: "../../main.rkt")
         (prefix-in c: "../../colors.rkt")
         (prefix-in ty: "../../typography.rkt")
         (prefix-in at: "../../authoring.rkt")
         "../../private/prepared-pict-visual.rkt"
         "data.rkt" "check.rkt" "appearance.rkt" "preparation-session.rkt"
         (only-in "schedule.rkt" content-time))
(provide prepare-native-content native-asset->pict native-asset->visual
         native-bundle->asset build-math-bundle build-geometry-bundle prepare-native-state freeze-native-state)
(define-runtime-path math-render "../../math/render.rkt")
(define-runtime-path math-compiler "../../math/private/animate-adapter.rkt")
(define-runtime-path geometry-adapter "../../geometry/animate.rkt")
(define-runtime-path geometry-core "../../geometry/core.rkt")
(define (native-theme ctx) (theme-value-colors (content-context-value-theme ctx)))
(define (native-typography ctx) (theme-value-typography (content-context-value-theme ctx)))
(define (rgba-hex color)
  (unless (= (c:rgba-color-alpha color) 1)
    (slides-error 'math-color-alpha '()
                  "typeset mathematical foreground/background colors must be opaque"))
  (define (hex x) (define s (number->string (inexact->exact (round x)) 16))
    (if (= (string-length s) 1) (string-append "0" s) s))
  (string-append "#" (hex (c:rgba-color-red color)) (hex (c:rgba-color-green color)) (hex (c:rgba-color-blue color))))
(define (light-mode? colors)
  (define b (c:resolve-color c:theme-background colors))
  (> (+ (* .2126 (c:rgba-color-red b)) (* .7152 (c:rgba-color-green b)) (* .0722 (c:rgba-color-blue b))) 128))
(define (region-camera rectangle colors)
  (define w (max 1/100 (box-value-width rectangle)))
  (define h (max 1/100 (box-value-height rectangle)))
  (a:make-camera #:width (max 1 (inexact->exact (round (* w 100))))
                 #:height (max 1 (inexact->exact (round (* h 100))))
                 #:world-width w #:background (c:resolve-color c:theme-background colors)))
(define (without-background camera)
  (a:make-camera #:width (a:camera-width camera) #:height (a:camera-height camera)
                 #:world-width (a:camera-world-width camera) #:center (a:camera-center camera)
                 #:background (c:rgba-color 0 0 0 0)))
(define (native-bundle->asset bundle poster metadata)
  (define camera (native-bundle-camera bundle))
  (define width (a:camera-world-width camera)) (define height (a:camera-world-height camera))
  (asset 'native bundle width height height (a:scene-duration (native-bundle-scene bundle))
         poster (native-bundle-cues bundle) (native-bundle-identity bundle) metadata))
(define (build-math-bundle prepared colors typography)
  (define get (lambda (name) (dynamic-require math-render name)))
  (define camera ((get 'prepared-math-plan-camera) prepared))
  (define times (make-hash))
  (define ambiguous (make-hash))
  (define (mark scn segment name boundary)
    (when name
      (define key (list name boundary))
      (hash-set! times (list segment name boundary) (a:scene-duration scn))
      (cond [(hash-has-key? times key) (hash-set! ambiguous key #t)]
            [else (hash-set! times key (a:scene-duration scn))]))
    scn)
  (define append-plan (dynamic-require math-compiler 'append-prepared-math-plan!))
  (define-values (scn ids checkpoint)
    (append-plan (a:make-scene #:camera camera) prepared #:title "" #:id '$slide-math
                 #:on-step (lambda (scn segment name) (mark scn segment name 'start))
                 #:on-step-end (lambda (scn segment name) (mark scn segment name 'end))))
  (for ([key (in-hash-keys ambiguous)]) (hash-remove! times key))
  (native-bundle scn camera colors typography (make-immutable-hash (hash->list times)) #f '()))
;; The source boundary records realization separately from layout for tests.
;; Neither this operation nor prepare-geometry-render! is called by the decoder.
(define (log-geometry-realization!)
  (define log (getenv "ANIMATE_GEOMETRY_PREPARATION_EVENT_LOG"))
  (when log
    (call-with-output-file log #:exists 'append
      (lambda (out) (displayln "(realize)" out)))))

(define (build-geometry-bundle prepared camera colors typography cues)
  (define sampler
    ((dynamic-require geometry-adapter 'prepared-geometry->visual-sampler)
     prepared #:id '$slide-geometry))
  (define duration ((dynamic-require geometry-adapter 'prepared-geometry-render-duration) prepared))
  (unless (= (a:camera-width camera)
             ((dynamic-require geometry-adapter 'prepared-geometry-render-pixels) prepared))
    (slides-error 'geometry-viewport '() "prepared geometry pixel width differs from its captured viewport"))
  (define clock (a:parameter '$slide-geometry-clock 0))
  (define relation
    (a:relation-visual (a:group '() #:id '$slide-geometry)
       #:depends-on (list (a:value-dependency '$slide-geometry-clock)) #:structure 'root-only
       (lambda (ctx template) (sampler (a:relation-context-value-ref ctx '$slide-geometry-clock)))))
  (define initial (a:scene-add (a:scene-set-value (a:make-scene #:camera camera) clock) relation))
  (define scn (if (> duration 0)
                  (a:scene-play initial (a:value-to clock duration) #:duration duration #:easing a:linear)
                  initial))
  (native-bundle scn camera colors typography cues #f '()))

(define (prepare-native-content content role rectangle ctx)
  (define descriptor (and (content-value? content) content))
  (define kind (if descriptor (content-value-kind descriptor) 'visual))
  (define value (if descriptor (content-value-payload descriptor) content))
  (define options (if descriptor (content-value-options descriptor) (hash)))
  (define colors (native-theme ctx)) (define typography (native-typography ctx))
  (define poster (hash-ref options 'poster 'end))
  (case kind
    [(math)
     (unless (content-context-value-effects? ctx)
       (slides-error 'preparation-required '(math) "mathematical content requires prepare-slide! or prepare-storyboard!"))
     (define prepare (dynamic-require math-render 'prepare-math-plan!))
     (define camera (region-camera rectangle colors))
     (define prepared
       (prepare value #:camera camera
                      #:minimum-scale (theme-spacing (content-context-value-theme ctx) 'math-minimum-scale)
                      #:theme (if (light-mode? colors) 'light 'dark)
                      #:foreground (rgba-hex (c:resolve-color c:theme-foreground colors))
                      #:background (rgba-hex (c:resolve-color c:theme-background colors))))
     (native-bundle->asset (build-math-bundle prepared colors typography) poster
                           (hash 'kind 'math 'prepared-math prepared 'source-content content 'background? #f))]
    [(geometry)
     (preparation-ref!
      (list 'geometry content (box-value-width rectangle) (box-value-height rectangle) colors typography)
      (lambda ()
     (define timeline? (dynamic-require geometry-core 'geometry-timeline?))
     (define timeline
       (if (timeline? value) value
           (begin
             (log-geometry-realization!)
             ((dynamic-require geometry-core 'construction->timeline) value
               #:aspect (/ (box-value-width rectangle) (box-value-height rectangle))))))
     (define view ((dynamic-require geometry-core 'geometry-realization-view)
                   ((dynamic-require geometry-core 'geometry-timeline-realization) timeline)))
     (define aspect ((dynamic-require geometry-core 'geometry-view-aspect) view))
     (define vw ((dynamic-require geometry-core 'geometry-view-width) view))
     (define center ((dynamic-require geometry-core 'geometry-view-center) view))
     (define width (max 1 (inexact->exact (round (* 100 (box-value-width rectangle))))))
     (define height (max 1 (inexact->exact (round (/ width aspect)))))
     ;; Use a containing viewport when integer pixel dimensions cannot express
     ;; the realization's exact aspect; never stretch the geometry.
     (define camera
       (a:make-camera #:width width #:height height
                      #:world-width (max vw (* (/ vw aspect) (/ width height)))
                      #:center (a:vec2 ((dynamic-require geometry-core 'point-x) center)
                                      ((dynamic-require geometry-core 'point-y) center))
                      #:background (c:rgba-color 0 0 0 0)))
     (define prepared
       ((dynamic-require geometry-adapter 'prepare-geometry-render!) timeline #:width width #:captions? #f))
     (define cue-table (make-hash))
     (define ambiguous-cues (make-hash))
     (for* ([span (in-list ((dynamic-require geometry-core 'geometry-timeline-steps) timeline))]
            [entry (in-list '((start . geometry-step-span-start)
                             (action-start . geometry-step-span-action-start)
                             (action-end . geometry-step-span-action-end)
                             (end . geometry-step-span-end)))])
       (define key (list ((dynamic-require geometry-core 'geometry-step-span-id) span) (car entry)))
       (define time ((dynamic-require geometry-core (cdr entry)) span))
       (if (hash-has-key? cue-table key)
           (hash-set! ambiguous-cues key #t)
           (hash-set! cue-table key time)))
     (for ([key (in-hash-keys ambiguous-cues)]) (hash-remove! cue-table key))
     (define cues (make-immutable-hash (hash->list cue-table)))
     (native-bundle->asset (build-geometry-bundle prepared camera colors typography cues) poster
                           (hash 'kind 'geometry 'source-content content 'background? #f
                                 'prepared-geometry prepared))))]
    [(scene)
     (define timeline (and (at:authored-timeline? value) value))
     (define scn (if timeline (at:authored-timeline-scene timeline) value))
     (unless (a:scene? scn) (raise-argument-error 'scene-content "scene or authored timeline" value))
     (define policy (hash-ref options 'media 'visual-only))
     (define cues (if timeline (for/hash ([q (in-list (at:authored-timeline-cues timeline))])
                                 (values (at:cue-name q) (at:cue-time q))) (hash)))
     (native-bundle->asset
      (native-bundle scn (a:scene-camera-at scn 0) colors typography cues #f '()) poster
      (hash 'kind 'scene 'source-content content 'background? (hash-ref options 'background? #f)
            'audio (if (and timeline (eq? policy 'import)) (at:authored-timeline-audio-cues timeline) '())
            'subtitles (if (and timeline (eq? policy 'import)) (at:authored-timeline-subtitles timeline) '())))]
    [(visual)
     (unless (and (a:visual? value) (a:affine-visual? value))
       (raise-argument-error 'visual-content "affine native Visual, Pict, or declared content" value))
     (when (and (a:formula-visual? value) (not (content-context-value-effects? ctx)))
       (slides-error 'preparation-required '(formula) "native formula measurement requires explicit preparation"))
     (define camera (region-camera rectangle colors))
     (define picture (a:visual->pict value camera #:theme colors #:typography typography))
     (define w (or (hash-ref options 'width #f) (/ (p:pict-width picture) (a:camera-scale camera))))
     (define h (or (hash-ref options 'height #f) (/ (p:pict-height picture) (a:camera-scale camera))))
     (unless (and (positive-number? w) (positive-number? h))
       (slides-error 'native-bounds '() "native content needs positive width and height"))
     (define viewport
       (a:make-camera #:width (max 1 (inexact->exact (round (* w 100))))
                      #:height (max 1 (inexact->exact (round (* h 100))))
                      #:world-width w #:center (a:visual-position value)
                      #:background (c:rgba-color 0 0 0 0)))
     (define scn (a:scene-add (a:make-scene #:camera viewport) value))
     (native-bundle->asset (native-bundle scn viewport colors typography (hash) #f '()) poster
                           (hash 'kind 'visual 'source-content content 'background? #f))]
    [else (slides-error 'content-kind (list kind) "unsupported content kind")]))
(define native-time-epsilon 1e-9)
(define (canonical-native-time scn time [cues '()])
  ;; Slide clocks can be inexact even when an embedded Scene was authored with
  ;; exact rational durations.  Treat values infinitesimally close to the two
  ;; closed-interval endpoints as those exact endpoints; do not otherwise alter
  ;; local seeking semantics.
  (define duration (a:scene-duration scn))
  (cond
    [(<= (abs time) native-time-epsilon) 0]
    [(<= (abs (- time duration)) native-time-epsilon) duration]
    [else
     (or (for/first ([cue (in-list (sort (remove-duplicates cues =) <))]
                     #:when (<= (abs (- time cue)) native-time-epsilon))
           cue)
         time)]))
(define (sample-bundle a time)
  (define bundle (asset-value a))
  (define scn (native-bundle-scene bundle))
  (define t (canonical-native-time scn (hash-ref (asset-metadata a) 'state-time time)
                                   (hash-values (native-bundle-cues bundle))))
  (define state (a:scene-sample scn t))
  (define camera (a:scene-camera-at scn t))
  (values state (if (hash-ref (asset-metadata a) 'background? #f) camera (without-background camera)) bundle))
(define (native-asset->pict a time)
  (define-values (state camera bundle) (sample-bundle a time))
  (define p (a:scene-state->pict state #:camera camera #:theme (native-bundle-colors bundle)
                                #:typography (native-bundle-typography bundle)))
  (p:scale p (/ (* 100 (asset-width a)) (p:pict-width p))
             (/ (* 100 (asset-height a)) (p:pict-height p))))
(define (native-asset->visual a time id)
  (define-values (state camera bundle) (sample-bundle a time))
  (prepared-scene-panel state camera #:width (asset-width a) #:height (asset-height a)
                        #:id id #:theme (native-bundle-colors bundle) #:typography (native-bundle-typography bundle)))


;; Freeze a witnessed state of an existing domain Scene. Retain the whole native
;; plan as evidence; a semantic bridge can replay it without inventing pairings.
(define (freeze-native-state base declaration)
  (unless (eq? (asset-kind base) 'native)
    (slides-error 'semantic-state-kind '() "content-state needs a native domain asset"))
  (define bundle (asset-value base))
  (define scn (native-bundle-scene bundle))
  (define selected
    (canonical-native-time scn
      (content-time base (hash-ref (content-value-options declaration) 'at))))
  (define inner (content-value-payload declaration))
  (define origin
    (list inner (hash-ref (content-value-options declaration) 'viewport)
          (c:color-theme-fingerprint (native-bundle-colors bundle))
          (ty:typography-theme-fingerprint (native-bundle-typography bundle))))
  (define metadata
    (hash-set
     (hash-set
      (hash-set
       (hash-set (asset-metadata base) 'source-content declaration)
       'state-base base) 'state-time selected) 'state-origin origin))
  (struct-copy asset base [duration 0] [poster 'end] [cues (hash)] [identity #f]
               [metadata metadata]))
(define (prepare-native-state declaration role ctx)
  (define viewport (hash-ref (content-value-options declaration) 'viewport))
  (define canonical-box (box-value 0 0 (car viewport) (cadr viewport)))
  (define inner (content-value-payload declaration))
  (define colors (native-theme ctx))
  (define typography (native-typography ctx))
  (define base
    (preparation-ref!
     (list 'native-state inner viewport colors typography
           (theme-spacing (content-context-value-theme ctx) 'math-minimum-scale))
     (lambda ()
       (prepare-native-content inner role canonical-box
                               (struct-copy content-context-value ctx [box canonical-box])))))
  (freeze-native-state base declaration))
