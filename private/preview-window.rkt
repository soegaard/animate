#lang racket/base

;;;
;;; Preview Window
;;;

;; This module is intentionally the first module in the preview stack that
;; loads racket/gui/base.  The controller remains the single state owner;
;; widget callbacks send commands and controller events are marshalled back to
;; the GUI eventspace with queue-callback.

(require racket/class
         racket/draw
         racket/gui/base
         "authoring-timeline.rkt"
         "camera.rkt"
         "frame-renderer.rkt"
         "geometry.rkt"
         "pict-adapter.rkt"
         "preview-controller.rkt"
         "preview-model.rkt"
         "preview-transaction.rkt"
         "program-preview.rkt"
         "relative-layout.rkt"
         "scene-program.rkt"
         "visual-inspector.rkt"
         "scene.rkt")

(provide open-preview-window
         configure-preview-block-navigation!)

;; `open-program-preview` attaches source-program state only after the generic
;; window has opened.  This weak table lets that public operation activate the
;; optional block chooser without giving the controller or model any GUI state.
(define block-navigation-updaters (make-weak-hasheq))

(define (configure-preview-block-navigation! session)
  (unless (preview-session? session)
    (raise-argument-error 'configure-preview-block-navigation!
                          "preview-session?"
                          session))
  (define updater (hash-ref block-navigation-updaters session #f))
  (when updater
    (queue-callback updater #f))
  (void))

(struct window-model (session bitmap canvas slider frame-message time-message
                              section-choice block-choice status-message play-button
                              selection-message frame-count handling?)
  #:mutable
  #:transparent)

(define (open-preview-window source
                             #:fps [fps 30]
                             #:start [start #f]
                             #:section [section #f]
                             #:camera [camera #f]
                             #:renderers [renderers default-pict-renderers]
                             #:pixel-scale [pixel-scale 1/2]
                             #:cache-megabytes [cache-megabytes 128]
                             #:prefetch [prefetch 3]
                             #:title [title "animate preview"])
  (define frame-count
    (scene-frame-count (preview-source-scene source) #:fps fps))
  (define controller-box (box #f))
  ;; Program previews currently expose named blocks rather than authored
  ;; timeline sections.  Keep the generic section controls inert in that
  ;; case, instead of sending an invalid jump command to the controller.
  (define section-names-box (box '()))
  (define block-names-box (box '()))
  (define frame
    (new
     (class frame%
       (super-new)
       ;; `frame%` exposes `on-close` as an augmentable hook.  A callback
       ;; setter is not part of the Racket GUI API.
       (define/augment (on-close)
         (define session (unbox controller-box))
         (when (and session (preview-open? session))
           (preview-close! session))
         (inner (void) on-close)))
     [label title]
     [width 900]
     [height 650]))
  (define outer (new vertical-panel% [parent frame] [alignment '(center center)]))
  (define bitmap-box (box #f))
  (define white (make-object color% 255 255 255))
  (define canvas
    (new
     (class canvas%
       (super-new [parent outer]
                  [min-width 640]
                  [min-height 400]
                  [stretchable-width #t]
                  [stretchable-height #t])
       (define/override (on-paint)
         (define dc (send this get-dc))
         (define-values (width height) (send this get-client-size))
         (send dc set-background white)
         (send dc clear)
         (define bitmap (unbox bitmap-box))
         (when bitmap
           ;; Initial previews use draft-sized bitmaps.  Letterboxing without a
           ;; re-render on every resize keeps interaction responsive.
           (define bitmap-width (send bitmap get-width))
           (define bitmap-height (send bitmap get-height))
           (define scale
             (min (/ width bitmap-width) (/ height bitmap-height)))
           (define draw-width (max 1 (inexact->exact (round (* bitmap-width scale)))))
           (define draw-height (max 1 (inexact->exact (round (* bitmap-height scale)))))
           (define x (/ (- width draw-width) 2))
           (define y (/ (- height draw-height) 2))
           ;; Device scaling leaves the semantic render cache untouched.
           (send dc set-smoothing 'smoothed)
           (send dc set-scale scale scale)
           (send dc draw-bitmap bitmap (/ x scale) (/ y scale))
           (send dc set-scale 1 1)
           (draw-selection-overlay dc x y draw-width draw-height bitmap)))
       (define/override (on-event event)
         (when (eq? (send event get-event-type) 'left-down)
           (select-at-canvas-point this event))
         (super on-event event))
       (define/override (on-char event)
         (define session (unbox controller-box))
         (when session
           (if (send event get-shift-down)
               (case (send event get-key-code)
                 [(left) (when (pair? (unbox section-names-box))
                           (preview-previous-section! session))]
                 [(right) (when (pair? (unbox section-names-box))
                            (preview-next-section! session))]
                 [else (void)])
               (case (send event get-key-code)
                 [(#\space) (preview-toggle-play! session)]
                 [(left) (preview-step! session -1)]
                 [(right) (preview-step! session 1)]
                 [(home) (preview-seek-frame! session 0)]
                 [(end) (preview-seek! session (scene-duration (preview-source-scene (preview-source session))))]
                 [(#\[) (when (pair? (unbox section-names-box))
                           (preview-previous-section! session))]
                 [(#\]) (when (pair? (unbox section-names-box))
                           (preview-next-section! session))]
                 [(#\r #\R) (preview-refresh! session)]
                 [(escape) (preview-pause! session)]
                 [else (void)])))
         (super on-char event))
       ;; The overlay is preview-only. It is drawn after the cached bitmap and
       ;; never enters scene->pict or the production frame path.
       (define (draw-selection-overlay dc x y width height bitmap)
         (define session (unbox controller-box))
         (when (and session (preview-transaction-session? session))
           (define path (preview-selection session))
           (when path
             (with-handlers ([exn:fail? (lambda (_error) (void))])
               (define source (preview-source-scene (preview-source session)))
               (define time (preview-current-time session))
               (define camera (scene-camera-at source time))
               (define inspection (scene-inspect-path source path time #:camera camera))
               (when (and inspection (visual-inspection-layout-box inspection))
                 (define box (visual-inspection-layout-box inspection))
                 (define-values (left top)
                   (camera-world->pixel camera
                                        (vec2 (layout-box-left box) (layout-box-top box))))
                 (define-values (right bottom)
                   (camera-world->pixel camera
                                        (vec2 (layout-box-right box) (layout-box-bottom box))))
                 (define factor-x (/ width (send bitmap get-width)))
                 (define factor-y (/ height (send bitmap get-height)))
                 (send dc set-pen (make-pen #:color "#d7263d" #:width 2))
                 (send dc set-brush (make-brush #:style 'transparent))
                 (send dc draw-rectangle (+ x (* left factor-x))
                       (+ y (* top factor-y))
                       (* (- right left) factor-x)
                       (* (- bottom top) factor-y)))))))
       (define (select-at-canvas-point canvas event)
         (define session (unbox controller-box))
         (define bitmap (unbox bitmap-box))
         (when (and session bitmap (preview-transaction-session? session))
           (with-handlers ([exn:fail? (lambda (_error) (void))])
             (define-values (width height) (send canvas get-client-size))
             (define bitmap-width (send bitmap get-width))
             (define bitmap-height (send bitmap get-height))
             (define scale (min (/ width bitmap-width) (/ height bitmap-height)))
             (define drawn-width (* bitmap-width scale))
             (define drawn-height (* bitmap-height scale))
             (define offset-x (/ (- width drawn-width) 2))
             (define offset-y (/ (- height drawn-height) 2))
             (define local-x (- (send event get-x) offset-x))
             (define local-y (- (send event get-y) offset-y))
             (when (and (<= 0 local-x drawn-width) (<= 0 local-y drawn-height))
               (define source (preview-source-scene (preview-source session)))
               (define time (preview-current-time session))
               (define camera (scene-camera-at source time))
               (define semantic-x (* (/ local-x drawn-width) (camera-width camera)))
               (define semantic-y (* (/ local-y drawn-height) (camera-height camera)))
               (define selected
                 (scene-hit-test source time semantic-x semantic-y #:camera camera
                                 #:after-path (preview-selection session)))
               (preview-select! session (and selected (visual-inspection-path selected)))
               (send canvas refresh))))))))
  (define controls (new horizontal-panel% [parent outer] [alignment '(center center)]))
  (define backward
    (new button% [parent controls] [label "◀"]
         [callback (lambda (_button _event)
                     (define session (unbox controller-box))
                     (when session (preview-step! session -1)))]))
  (define play
    (new button% [parent controls] [label "Play"]
         [callback (lambda (_button _event)
                     (define session (unbox controller-box))
                     (when session (preview-toggle-play! session)))]))
  (define forward
    (new button% [parent controls] [label "▶"]
         [callback (lambda (_button _event)
                     (define session (unbox controller-box))
                     (when session (preview-step! session 1)))]))
  (define frame-message (new message% [parent controls] [label "frame 0000"]))
  (define time-message (new message% [parent controls] [label "0.000 s"]))
  (define status-message (new message% [parent controls] [label "rendering"]))
  (define selection-message (new message% [parent outer] [label "selection: none"]))
  (define copy-selection
    (new button% [parent outer] [label "Copy selected path"]
         [callback
          (lambda (_button _event)
            (define session (unbox controller-box))
            (when (and session (preview-transaction-session? session))
              (define selection (preview-selection session))
              (when selection
                ;; The GUI layer owns this side effect; the headless inspector
                ;; represents a path only as immutable data.
                (send the-clipboard set-clipboard-string (format "~s" selection) 0))))]))
  (define section-choice
    (new choice% [parent controls] [label "section"] [choices '()]
         [callback
          (lambda (choice _event)
            (define session (unbox controller-box))
            (define selected-index (send choice get-selection))
            ;; `get-number` reports how many choices exist; it is not the
            ;; selected index.  In particular, the placeholder choice below
            ;; made the old condition true as soon as the menu was populated.
            (when (and session
                       (exact-nonnegative-integer? selected-index)
                       (positive? selected-index))
              (preview-jump-to-section! session
                                        (string->symbol
                                         (send choice get-string selected-index)))))]))
  (send section-choice show #f)
  (define block-choice
    (new choice% [parent controls] [label "block"] [choices '()]
         [callback
          (lambda (choice _event)
            (define session (unbox controller-box))
            (define selected-index (send choice get-selection))
            (when (and session
                       (exact-nonnegative-integer? selected-index)
                       (positive? selected-index)
                       (program-preview-session? session))
              (preview-jump-to-block!
               session
               (string->symbol (send choice get-string selected-index)))))]))
  ;; Program context is installed after the generic window opens.  Keep this
  ;; control out of ordinary scene/timeline previews until then.
  (send block-choice show #f)
  (define slider
    (new slider% [parent outer] [label #f] [min-value 0]
         [max-value (max 1 (sub1 frame-count))]
         [init-value 0] [style '(horizontal plain)]
         [callback
          (lambda (control _event)
            (define session (unbox controller-box))
            (when session
              (preview-seek-frame! session (send control get-value))))]))
  (define model
    (window-model #f #f canvas slider frame-message time-message section-choice block-choice
                  status-message play selection-message 0 #f))
  (define (install-section-navigation! names)
    (unless (equal? names (unbox section-names-box))
      (set-box! section-names-box names)
      (send section-choice clear)
      (send section-choice append "")
      (for ([name (in-list names)])
        (send section-choice append (symbol->string name)))
      (send section-choice enable (pair? names))
      ;; A plain Scene has no meaningful section picker.  Hiding it avoids a
      ;; disabled control that looks like an available feature.
      (send section-choice show (pair? names))))
  (define (install-block-navigation!)
    (define session (unbox controller-box))
    (define program?
      (and session (program-preview-session? session)))
    (define names
      (if program?
          (map scene-block-spec-id (preview-program-blocks session))
          '()))
    (unless (equal? names (unbox block-names-box))
      (set-box! block-names-box names)
      (send block-choice clear)
      (send block-choice append "")
      (for ([name (in-list names)])
        (send block-choice append (symbol->string name)))
      (send block-choice enable (pair? names)))
    (when program?
      ;; A source program has source blocks, not implicit authored sections.
      ;; Its explicit block selector replaces the generic section control.
      (send section-choice show #f)
      (send block-choice show (pair? names))))
  (define (install-event event)
    ;; This continuation is always run in the GUI eventspace.
    (define status (preview-event-status event))
    (set-window-model-handling?! model #t)
    (when (preview-event-bitmap event)
      (set-window-model-bitmap! model (preview-event-bitmap event))
      (set-box! bitmap-box (preview-event-bitmap event))
      (send canvas refresh))
    (when status
      ;; This also refreshes the names after a source-program reload that
      ;; changed the block declarations.
      (install-block-navigation!)
      (define frame-index (preview-status-frame status))
      (send frame-message set-label
            (if frame-index
                (format "frame ~a" frame-index)
                "endpoint"))
      (send time-message set-label (format "~a s" (real->decimal-string (preview-status-time status) 3)))
      (send status-message set-label
            (cond
              [(preview-status-error status) "error"]
              [(preview-status-rendering? status) "rendering"]
              [else "ready"]))
      (send play set-label (if (preview-status-playing? status) "Pause" "Play"))
      (when frame-index (send slider set-value frame-index))
      (define current (preview-status-current-section status))
      (when current
        (define desired (symbol->string current))
        (define selection-index
          (for/first ([index (in-range (send section-choice get-number))]
                      #:when (equal? (send section-choice get-string index) desired))
            index))
        (when selection-index
          (send section-choice set-selection selection-index)))
      (when (preview-transaction-session? session)
        (define selection (preview-selection session))
        (send selection-message set-label
              (if selection
                  (format "selection: ~s" selection)
                  "selection: none"))))
    (set-window-model-handling?! model #f))
  (define session
    (open-preview-controller
     source #:fps fps #:start start #:section section #:camera camera
     #:renderers renderers #:pixel-scale pixel-scale
     #:cache-megabytes cache-megabytes #:prefetch prefetch
     #:on-event
     (lambda (event)
       (queue-callback (lambda () (install-event event)) #f))))
  (set-window-model-session! model session)
  (set-box! controller-box session)
  (attach-preview-transactions! session #:initial-scene (preview-source-scene source))
  (hash-set! block-navigation-updaters session install-block-navigation!)
  (preview-add-close-hook!
   session
   (lambda ()
     (hash-remove! block-navigation-updaters session)))
  (set-window-model-frame-count! model frame-count)
  (send slider enable (positive? frame-count))
  (define section-names (preview-section-names session))
  (install-section-navigation! section-names)
  (send frame show #t)
  session)
