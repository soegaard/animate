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
         racket/match
         racket/string
         "affine-transform.rkt"
         "authoring-timeline.rkt"
         "camera.rkt"
         "frame-renderer.rkt"
         "formula-part-transition.rkt"
         "formula-parts-visual.rkt"
         "formula-source.rkt"
         "formula-source-map.rkt"
         "source-document.rkt"
         "scene-frame-grid.rkt"
         "scene-state.rkt"
         "geometry.rkt"
         "pict-adapter.rkt"
         "preview-controller.rkt"
         "preview-repl.rkt"
         "preview-timeline-model.rkt"
         "waveform.rkt"
         "inspector-document.rkt"
         "preview-model.rkt"
         "preview-transaction.rkt"
         "program-preview.rkt"
         "relative-layout.rkt"
         "scene-program.rkt"
         "3d/affine3.rkt"
         "3d/camera3d.rkt"
         "3d/bounds3.rkt"
         "3d/clipping3d.rkt"
         "3d/preview-camera3d-override.rkt"
         "3d/projection3d.rkt"
         "3d/ray-plane.rkt"
         "3d/rotation3.rkt"
         "3d/spatial-inspection.rkt"
         "3d/vec3.rkt"
         "3d/view3d-visual.rkt"
         "visual-inspector.rkt"
         "visual-model.rkt"
         "scene.rkt")

(provide open-preview-window
         configure-preview-block-navigation!)

;; `open-program-preview` attaches source-program state only after the generic
;; window has opened.  This weak table lets that public operation activate the
;; optional block chooser without giving the controller or model any GUI state.
(define block-navigation-updaters (make-weak-hasheq))

;; These helpers describe source text only. Keeping them outside the GUI
;; constructor makes the source-index calculation independent of widget state
;; and, in particular, prevents a character hit from being inferred from a
;; rendered formula glyph.
(define (inspector-document-formula document)
  (define candidate
    (and (inspector-document? document)
         (let ([value (inspector-subject-value
                       (inspector-document-subject document))])
           (cond
             [(formula-assembly-visual? value) value]
             [(and (pair? value) (formula-assembly-visual? (car value)))
              (car value)]
             [else #f]))))
  ;; Interior formula-transition layers are formula assemblies solely so the
  ;; renderer can cross-fade their glyphs. They deliberately carry no durable
  ;; source map. The source panel must not treat such a temporary layer as a
  ;; source-addressable formula during a repaint.
  (and candidate
       (with-handlers ([exn:fail? (lambda (_error) #f)])
         (and (formula-source-map candidate) candidate))))

(define (inspector-document-selected-source-match document)
  (and (inspector-document? document)
       (let ([value (inspector-subject-value
                     (inspector-document-subject document))])
         (and (pair? value)
              (formula-assembly-visual? (car value))
              (formula-source-match? (cdr value))
              (cdr value)))))

(define (source-character-color formula selected-match index)
  (define mapping (formula-source-map formula))
  (define matching
    (and mapping
         (for/first ([candidate (in-list (formula-source-map-matches mapping))]
                     #:when (let ([span (formula-source-match-span candidate)])
                              (and (<= (source-span-start span) index)
                                   (< index (source-span-end span)))))
           candidate)))
  (cond
    [(and selected-match
          (let ([span (formula-source-match-span selected-match)])
            (and (<= (source-span-start span) index)
                 (< index (source-span-end span)))))
     "crimson"]
    [matching "steelblue"]
    [(char-whitespace? (string-ref (formula-source formula) index)) "gray"]
    [else "darkorange"]))

(define (source-character-selected? selected-match index)
  (and selected-match
       (let ([span (formula-source-match-span selected-match)])
         (and (<= (source-span-start span) index)
              (< index (source-span-end span))))))

(define (source-character-index-at dc source x y)
  ;; Formula source spans use Racket string indexes.  This deliberately
  ;; measures displayed characters rather than deriving an index from a
  ;; proportional-font average; a click is either on one exact character or
  ;; on no source character at all.
  (send dc set-font (make-object font% 14 'modern 'normal 'normal))
  (define-values (_sample-width line-height _descent _space)
    (send dc get-text-extent "M"))
  (let loop ([index 0] [cursor-x 6] [cursor-y 4])
    (cond
      ((= index (string-length source)) #f)
      (else
       (define character (string-ref source index))
       (cond
         ((char=? character #\newline)
          (loop (add1 index) 6 (+ cursor-y line-height)))
         (else
          (define-values (character-width _height _d _s)
            (send dc get-text-extent (string character)))
          (cond
            ((and (<= cursor-y y) (< y (+ cursor-y line-height))
                  (<= cursor-x x) (< x (+ cursor-x character-width)))
             index)
            (else
             (loop (add1 index) (+ cursor-x character-width) cursor-y)))))))))

;; Racket GUI accepts at most 200 characters for a list-box label. Inspector
;; values can legitimately be richer than that (for example, a compiled
;; string-match route). The complete immutable row remains in
;; `inspector-rows-box` for actions such as Copy; this helper constrains only
;; the one-line presentation required by the native control.
(define list-control-label-maximum-length 200)

(define (list-control-label text)
  (define single-line
    (string-trim
     (string-replace
      (string-replace text "\n" " ")
      "\r" " ")))
  (if (<= (string-length single-line) list-control-label-maximum-length)
      single-line
      (string-append
       (substring single-line 0 (sub1 list-control-label-maximum-length))
       "…")))

(define (configure-preview-block-navigation! session)
  (unless (preview-session? session)
    (raise-argument-error 'configure-preview-block-navigation!
                          "preview-session?"
                          session))
  (define updater (hash-ref block-navigation-updaters session #f))
  (when updater
    (queue-callback updater #f))
  (void))

(struct window-model (session bitmap canvas timeline-canvas frame-message time-message
                              section-choice block-choice status-message play-button
                              selection-message inspector-message frame-count handling?)
  #:mutable
  #:transparent)

(define (open-preview-window source
                             #:fps [fps 30]
                             #:start [start #f]
                             #:section [section #f]
                             #:camera [camera #f]
                             #:renderers [renderers default-pict-renderers]
                             #:pixel-scale [pixel-scale 1]
                             #:cache-megabytes [cache-megabytes 128]
                             #:prefetch [prefetch 3]
                             #:worker-mode [worker-mode 'in-process]
                             #:producer [producer #f]
                             #:waveform [wave #f]
                             #:audio-mute-available? [audio-mute-available? (lambda () #f)]
                             #:audio-muted? [audio-muted? (lambda () #f)]
                             #:set-audio-muted! [set-audio-muted! (lambda (_muted?) (void))]
                             #:on-preview-event [on-preview-event void]
                             #:title [title "Animate"])
  (unless (procedure? on-preview-event)
    (raise-argument-error 'open-preview-window "procedure?" on-preview-event))
  (unless (procedure-arity-includes? audio-mute-available? 0)
    (raise-argument-error
     'open-preview-window "procedure accepting zero arguments" audio-mute-available?))
  (unless (procedure-arity-includes? audio-muted? 0)
    (raise-argument-error
     'open-preview-window "procedure accepting zero arguments" audio-muted?))
  (unless (procedure-arity-includes? set-audio-muted! 1)
    (raise-argument-error
     'open-preview-window "procedure accepting one argument" set-audio-muted!))
  (define frame-count
    (scene-frame-count (preview-source-scene source) #:fps fps))
  (define controller-box (box #f))
  (define current-pixel-scale (box pixel-scale))
  (define pixel-scale-items-box (box '()))
  (define pixel-scale-options
    (list (cons "50%" 1/2)
          (cons "100%" 1)
          (cons "200%" 2)))
  (define (update-pixel-scale-checkmarks!)
    (for ([item (in-list (unbox pixel-scale-items-box))]
          [option (in-list pixel-scale-options)])
      (send item check (= (cdr option) (unbox current-pixel-scale)))))
  (define (set-preview-pixel-scale! scale)
    (define session (unbox controller-box))
    (cond
      [(= scale (unbox current-pixel-scale))
       ;; A checkable menu item toggles before its callback runs. Restore the
       ;; active radio-style choice when it was clicked again.
       (update-pixel-scale-checkmarks!)]
      [else
       (set-box! current-pixel-scale scale)
       (update-pixel-scale-checkmarks!)
       (when session
         ;; Replacing the immutable render spec atomically invalidates the
         ;; bitmap cache and requests the same semantic frame at the new scale.
         (preview-set-render-spec!
          session
          (make-preview-render-spec #:fps fps #:camera camera #:renderers renderers
                                    #:pixel-scale scale)))]))
  ;; Program previews currently expose named blocks rather than authored
  ;; timeline sections.  Keep the generic section controls inert in that
  ;; case, instead of sending an invalid jump command to the controller.
  (define section-names-box (box '()))
  (define block-names-box (box '()))
  ;; Cues are point events in an authored timeline.  They need their own
  ;; navigation state: unlike sections, there is no "current cue" while the
  ;; playhead is between two markers, and unlike source blocks they are not
  ;; part of a program-preview source.
  (define cue-names-box (box '()))
  ;; Timeline data is semantic, immutable, and shared with headless preview
  ;; tests. The widget below is only a view/controller for this model.
  (define timeline-model-box
    (box
     (make-preview-timeline
      (scene-duration (preview-source-scene source))
      #:timeline (and (authored-timeline? source) source)
      #:waveform wave)))
  ;; The controller owns whether a marked selection is an active loop. The
  ;; window mirrors its immutable status only for painting; it never derives
  ;; loop boundaries from a rendered bitmap or frame number.
  (define loop-range-box (box #f))
  ;; Production diagnostics are optional UI chrome. Their contents are an
  ;; immutable controller snapshot, never a second mutable clock or renderer.
  (define diagnostics-panel-box (box #f))
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
  (define menu-bar (new menu-bar% [parent frame]))
  (define animate-menu (new menu% [parent menu-bar] [label "Animate"]))
  (define pixel-scale-menu
    (new menu% [parent animate-menu] [label "Pixel scale"] ))
  (define pixel-scale-items
    (for/list ([option (in-list pixel-scale-options)])
      (new checkable-menu-item%
           [parent pixel-scale-menu]
           [label (car option)]
           [callback (lambda (_item _event)
                       (set-preview-pixel-scale! (cdr option)))])))
  (set-box! pixel-scale-items-box pixel-scale-items)
  (update-pixel-scale-checkmarks!)
  ;; Inspection navigation is intentionally a separate preview layer.  These
  ;; actions do not change the source scene, its authored camera, or its
  ;; ordinary two-dimensional render camera.
  (define inspection-camera-menu
    (new menu% [parent animate-menu] [label "3D inspection camera"]))
  (new menu-item%
       [parent inspection-camera-menu]
       [label "Reset inspection camera"]
       [callback (lambda (_item _event) (reset-inspection-camera!))])
  (new menu-item%
       [parent inspection-camera-menu]
       [label "Copy camera expression"]
       [callback (lambda (_item _event) (copy-inspection-camera-expression!))])
  (new menu-item%
       [parent inspection-camera-menu]
       [label "Copy camera animation from authored camera"]
       [callback (lambda (_item _event) (copy-inspection-camera-animation!))])
  (new menu-item%
       [parent inspection-camera-menu]
       [label "Use inspection camera as REPL scratch camera"]
       [callback (lambda (_item _event) (install-inspection-camera-in-repl!))])
  ;; Spatial selection is similarly preview-only.  These actions operate on
  ;; the exact ray/triangle pick retained in `spatial-pick-box`, never on a
  ;; colour sampled from the rendered bitmap and never on authored scene data.
  (define spatial-selection-menu
    (new menu% [parent animate-menu] [label "3D selection"] ))
  (new menu-item%
       [parent spatial-selection-menu]
       [label "Copy spatial path"]
       [callback (lambda (_item _event) (copy-spatial-path!))])
  (new menu-item%
       [parent spatial-selection-menu]
       [label "Copy hit position"]
       [callback (lambda (_item _event) (copy-spatial-point!))])
  (new menu-item%
       [parent spatial-selection-menu]
       [label "Copy surface normal"]
       [callback (lambda (_item _event) (copy-spatial-normal!))])
  (new menu-item%
       [parent spatial-selection-menu]
       [label "Focus inspection camera on selection"]
       [callback (lambda (_item _event) (focus-inspection-camera-on-selection!))])
  (new menu-item%
       [parent spatial-selection-menu]
       [label "Use selection as REPL scratch values"]
       [callback (lambda (_item _event) (install-spatial-selection-in-repl!))])
  (define outer (new vertical-panel% [parent frame] [alignment '(center center)]))
  (define bitmap-box (box #f))
  ;; The active view is selected by the most recent drag/wheel gesture. It is
  ;; not a semantic scene selection and therefore never competes with the
  ;; existing Visual-inspector path state.
  (define inspection-view-id-box (box #f))
  (define inspection-drag-box (box #f))
  ;; This is deliberately separate from `preview-selection`: the latter is an
  ;; authored 2D Visual path, while a spatial pick names an object inside a
  ;; view3d and is valid only as preview inspection state.
  (define spatial-pick-box (box #f))
  (define white (make-object color% 255 255 255))
  ;; Convert a pointer position through the same letterbox and immutable 2D
  ;; preview camera used for ordinary semantic hit testing.  The returned
  ;; coordinates locate a viewport; they do not sample a rendered bitmap.
  (define (canvas-event->semantic-point canvas event)
    (define session (unbox controller-box))
    (define bitmap (unbox bitmap-box))
    (and session bitmap (preview-transaction-session? session)
         (with-handlers ([exn:fail? (lambda (_error) #f)])
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
           (and (<= 0 local-x drawn-width) (<= 0 local-y drawn-height)
                (let* ([source (preview-source-scene (preview-source session))]
                       [time (preview-current-time session)]
                       [preview-camera (or camera (scene-camera-at source time))])
                  (list source time preview-camera
                        (* (/ local-x drawn-width) (camera-width preview-camera))
                        (* (/ local-y drawn-height) (camera-height preview-camera))))))))
  ;; Returns the top-level view3d identity beneath a canvas event. A regular
  ;; 2D Visual remains selectable by the existing click path; only an actual
  ;; viewport starts an inspection-camera gesture.
  (define (view3d-id-at-canvas-event canvas event)
    (define location (canvas-event->semantic-point canvas event))
    (and location
         (match location
           [(list source time preview-camera semantic-x semantic-y)
            (define hit
              (scene-hit-test source time semantic-x semantic-y
                              #:camera preview-camera))
            (define path (and hit (visual-inspection-path hit)))
            (and path
                 (let ([visual (scene-state-ref (scene-sample source time) path)])
                   (and (view3d? visual) (visual-id visual))))])))
  (define (authored-view3d session view-id)
    (define source (preview-source-scene (preview-source session)))
    (define view (scene-state-ref (scene-sample source (preview-current-time session))
                                  view-id))
    (and (view3d? view) view))
  (define (current-inspection-override session view-id)
    (define authored (authored-view3d session view-id))
    (and authored
         (hash-ref (preview-camera3d-overrides session) view-id
                   (lambda ()
                     (make-preview-camera3d-override
                      view-id (view3d-camera authored))))))
  (define (set-inspection-override! session override)
    (set-box! inspection-view-id-box (preview-camera3d-override-view-id override))
    (preview-set-camera3d-override! session override))
  (define (navigate-inspection-camera! view-id dx dy shift?)
    (define session (unbox controller-box))
    (when session
      (define override (current-inspection-override session view-id))
      (when override
        (define camera3d (preview-camera3d-override-camera override))
        (define next
          (if shift?
              ;; Pan in the camera's screen axes; the scale follows the current
              ;; inspection distance rather than canvas pixel history.
              (let* ([distance (max 1/10
                                    (vec3-distance (camera3d-position camera3d)
                                                   (preview-camera3d-override-target override)))]
                     [unit (/ distance 300)]
                     [delta (vec3+
                             (vec3-scale (* -1 dx unit) (camera3d-right camera3d))
                             (vec3-scale (* dy unit) (camera3d-up camera3d)))])
                (preview-camera3d-override-pan override delta))
              (preview-camera3d-override-orbit override
                                                (* -1/100 dx)
                                                (* -1/100 dy))))
        (set-inspection-override! session next))))
  (define (dolly-inspection-camera! view-id amount)
    (define session (unbox controller-box))
    (when session
      (define override (current-inspection-override session view-id))
      (when override
        (set-inspection-override!
         session
         (preview-camera3d-override-dolly override (* 1/4 amount))))))
  (define (active-inspection-view-id)
    (define session (unbox controller-box))
    (or (unbox inspection-view-id-box)
        (and session
             (= (hash-count (preview-camera3d-overrides session)) 1)
             (car (hash-keys (preview-camera3d-overrides session))))))
  (define (reset-inspection-camera!)
    (define session (unbox controller-box))
    (when session
      (define selected (active-inspection-view-id))
      (if selected
          (preview-clear-camera3d-override! session selected)
          (for ([view-id (in-list (hash-keys (preview-camera3d-overrides session)))])
            (preview-clear-camera3d-override! session view-id)))
      (set-box! inspection-view-id-box #f)))
  (define (vec3-expression value)
    (format "(vec3 ~s ~s ~s)" (vec3-x value) (vec3-y value) (vec3-z value)))
  (define (rotation3-expression value)
    (define components (rotation3-components value))
    (define w (vector-ref components 0))
    (define x (vector-ref components 1))
    (define y (vector-ref components 2))
    (define z (vector-ref components 3))
    (define axis-length (sqrt (+ (* x x) (* y y) (* z z))))
    (if (zero? axis-length)
        "identity-rotation3"
        (format "(axis-angle (vec3 ~s ~s ~s) ~s)"
                (/ x axis-length) (/ y axis-length) (/ z axis-length)
                (* 2 (acos (max -1 (min 1 w)))))))
  (define (camera3d-expression camera3d)
    (define projection (camera3d-projection camera3d))
    (define lens
      (if (perspective-projection3d? projection)
          (format "#:vertical-field-of-view ~s"
                  (perspective-projection3d-vertical-field-of-view projection))
          (format "#:vertical-size ~s"
                  (orthographic-projection3d-vertical-size projection))))
    (format "(~a #:position ~a #:rotation ~a #:near ~s #:far ~s ~a)"
            (if (perspective-projection3d? projection)
                "perspective-camera3d"
                "orthographic-camera3d")
            (vec3-expression (camera3d-position camera3d))
            (rotation3-expression (camera3d-rotation camera3d))
            (camera3d-near camera3d)
            (camera3d-far camera3d)
            lens))
  (define (active-inspection-camera)
    (define session (unbox controller-box))
    (define view-id (and session (active-inspection-view-id)))
    (and session view-id
         (let ([override (current-inspection-override session view-id)])
           (and override (cons view-id (preview-camera3d-override-camera override))))))
  (define (copy-inspection-camera-expression!)
    (define active (active-inspection-camera))
    (when active
      (send the-clipboard set-clipboard-string
            (camera3d-expression (cdr active)) 0)))
  (define (copy-inspection-camera-animation!)
    (define active (active-inspection-camera))
    (when active
      (define view-id (car active))
      (define target-camera (cdr active))
      (define target
        (vec3+ (camera3d-position target-camera)
               (camera3d-forward target-camera)))
      (define lens
        (if (perspective-projection3d? (camera3d-projection target-camera))
            (format "\n  (camera3d-field-of-view-to '~a ~s)"
                    view-id
                    (perspective-projection3d-vertical-field-of-view
                     (camera3d-projection target-camera)))
            (format "\n  (camera3d-orthographic-height-to '~a ~s)"
                    view-id
                    (orthographic-projection3d-vertical-size
                     (camera3d-projection target-camera)))))
      (send the-clipboard set-clipboard-string
            (format "(animation-group\n  (camera3d-move-to '~a ~a)\n  (camera3d-look-at-to '~a ~a #:up ~a)~a)"
                    view-id (vec3-expression (camera3d-position target-camera))
                    view-id (vec3-expression target)
                    (vec3-expression (camera3d-up target-camera)) lens)
            0)))
  (define (install-inspection-camera-in-repl!)
    (define active (active-inspection-camera))
    (when active
      (define session (unbox controller-box))
      (preview-repls-set-scratch-binding! session 'inspection-camera (cdr active))
      (send the-clipboard set-clipboard-string
            (format "(define inspection-camera ~a)"
                    (camera3d-expression (cdr active)))
            0)))
  ;; A `view3d` uses its active inspection camera for picking as well as for
  ;; drawing.  Applying that immutable override here keeps click rays and the
  ;; preview bitmap in the same coordinate system.
  (define (resolved-inspection-view session view-id)
    (and session
         (let* ([source (preview-source-scene (preview-source session))]
                [time (preview-current-time session)]
                [sampled (scene-sample source time)]
                [override (current-inspection-override session view-id)]
                [state (if override
                           (preview-camera3d-override-apply sampled override)
                           sampled)]
                [view (scene-state-resolved-ref state view-id)])
           (and (view3d? view) view))))
  ;; The measured outer visual retains its complete 2D transform.  Spatial
  ;; picking must invert that transform before mapping the local viewport
  ;; coordinates to a camera ray: an axis-aligned layout box would make a
  ;; rotated or non-uniformly scaled `view3d` pick the wrong 3D pixel.
  (define (view3d-layout-inspection session view-id)
    (define source (preview-source-scene (preview-source session)))
    (define time (preview-current-time session))
    (define preview-camera (or camera (scene-camera-at source time)))
    (scene-inspect-path source (list view-id) time #:camera preview-camera))
  (define (view3d-world->local-point layout-inspection world-point)
    (define transform
      (and layout-inspection
           (visual-inspection-composed-transform layout-inspection)))
    (define inverse
      (and transform
           (affine2-invert (affine-transform->affine2 transform))))
    (and inverse
         (affine2-apply-point inverse world-point)))
  (define (spatial-pick-at-canvas-event canvas event)
    (define session (unbox controller-box))
    (define view-id (view3d-id-at-canvas-event canvas event))
    (define location (canvas-event->semantic-point canvas event))
    (and session view-id location
         (match location
           [(list source time preview-camera semantic-x semantic-y)
            (define layout-inspection
              (view3d-layout-inspection session view-id))
            (define view (resolved-inspection-view session view-id))
            (and view
                 (let ([local-point
                        (view3d-world->local-point
                         layout-inspection
                         (camera-pixel->world
                          preview-camera semantic-x semantic-y))])
                   (and local-point
                        (let* ([horizontal (view3d-width view)]
                               [vertical (view3d-height view)]
                               [pixel-x
                                (* 1000
                                   (max 0 (min 1
                                               (/ (+ (vec2-x local-point)
                                                     (/ horizontal 2))
                                                  horizontal))))]
                               [pixel-y
                                (* 1000
                                   (max 0 (min 1
                                               (/ (- (/ vertical 2)
                                                     (vec2-y local-point))
                                                  vertical))))]
                               [pick (view3d-pixel-pick view pixel-x pixel-y
                                                        #:width 1000 #:height 1000)])
                          (and pick (cons view-id pick))))))]
           [_ #f])))
  (define (select-spatial-at-canvas-point canvas event)
    (define picked (spatial-pick-at-canvas-event canvas event))
    (set-box! spatial-pick-box picked)
    (when picked
      (set-box! inspection-view-id-box (car picked)))
    (update-selection-message!)
    picked)
  (define (active-spatial-pick)
    (define value (unbox spatial-pick-box))
    (and value (cdr value)))
  (define (active-spatial-view-id)
    (define value (unbox spatial-pick-box))
    (and value (car value)))
  (define (copy-spatial-path!)
    (define pick (active-spatial-pick))
    (when pick
      (send the-clipboard set-clipboard-string
            (format "'~s" (spatial-pick-path pick)) 0)))
  (define (copy-spatial-point!)
    (define pick (active-spatial-pick))
    (when pick
      (send the-clipboard set-clipboard-string
            (vec3-expression (spatial-pick-point pick)) 0)))
  (define (copy-spatial-normal!)
    (define pick (active-spatial-pick))
    (when pick
      (send the-clipboard set-clipboard-string
            (vec3-expression (spatial-pick-normal pick)) 0)))
  (define (focus-inspection-camera-on-selection!)
    (define session (unbox controller-box))
    (define view-id (active-spatial-view-id))
    (define pick (active-spatial-pick))
    (when (and session view-id pick)
      (define override (current-inspection-override session view-id))
      (when override
        (define target (spatial-pick-point pick))
        (define focused
          (camera3d-look-at (preview-camera3d-override-camera override) target))
        (set-inspection-override!
         session
         (make-preview-camera3d-override view-id focused #:target target)))))
  (define (install-spatial-selection-in-repl!)
    (define session (unbox controller-box))
    (define view-id (active-spatial-view-id))
    (define pick (active-spatial-pick))
    (when (and session view-id pick)
      ;; These are normal immutable values.  They are intentionally scratch
      ;; bindings rather than edits to a scene program: an author can inspect
      ;; the point, create a projected label, or use the plane in a clipping
      ;; experiment without creating a hidden preview-only scene mutation.
      (define point (spatial-pick-point pick))
      (define normal (spatial-pick-normal pick))
      (preview-repls-set-scratch-binding! session 'spatial-selection pick)
      (preview-repls-set-scratch-binding! session 'spatial-path (spatial-pick-path pick))
      (preview-repls-set-scratch-binding! session 'spatial-point point)
      (preview-repls-set-scratch-binding! session 'spatial-normal normal)
      (preview-repls-set-scratch-binding! session 'spatial-clipping-plane
                                          (clip-plane3d (plane3 point normal)))
      (send the-clipboard set-clipboard-string
            (format ";; selected ~s in view '~a\n(define spatial-point ~a)\n(define spatial-normal ~a)\n(define spatial-clipping-plane\n  (clip-plane3d (plane3 spatial-point spatial-normal)))"
                    (spatial-pick-path pick) view-id
                    (vec3-expression point) (vec3-expression normal))
            0)))
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
           ;; Native-resolution previews are letterboxed without a re-render
           ;; on every resize, keeping interaction responsive.
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
         (case (send event get-event-type)
           [(left-down)
            (define view-id (view3d-id-at-canvas-event this event))
            (if view-id
                (begin
                  (set-box! inspection-view-id-box view-id)
                  ;; Store only the most recent device point and a movement
                  ;; flag. The camera itself remains an immutable controller
                  ;; value, never drag-session state.
                  (set-box! inspection-drag-box
                            (vector view-id (send event get-x) (send event get-y) #f)))
                (begin
                  ;; A normal 2D click begins a different inspection session;
                  ;; do not leave a stale spatial overlay floating over it.
                  (set-box! spatial-pick-box #f)
                  (select-at-canvas-point this event)))]
           [(motion)
            (define drag (unbox inspection-drag-box))
            (cond
              [drag
               (define x (send event get-x))
               (define y (send event get-y))
               (define dx (- x (vector-ref drag 1)))
               (define dy (- y (vector-ref drag 2)))
               (when (or (not (zero? dx)) (not (zero? dy)))
                 (navigate-inspection-camera! (vector-ref drag 0) dx dy
                                               (send event get-shift-down))
                 (vector-set! drag 1 x)
                 (vector-set! drag 2 y)
                 (vector-set! drag 3 #t))]
              [else
               ;; Wheel events are key events in racket/gui and therefore
               ;; carry no pointer position.  Remember the viewport currently
               ;; under the pointer so a subsequent wheel event controls it.
               (define view-id (view3d-id-at-canvas-event this event))
               (when view-id
                 (set-box! inspection-view-id-box view-id))])]
           [(left-up)
           ;; A click in a viewport retains ordinary selection behavior. A
           ;; real drag is reserved for the non-authoring inspection camera.
            (define drag (unbox inspection-drag-box))
            (when (and drag (not (vector-ref drag 3)))
              ;; Exact spatial selection is an additional preview inspection
              ;; layer. The ordinary outer `view3d` Visual is still selected
              ;; below for the existing 2D inspector and keyboard workflow.
              (select-spatial-at-canvas-point this event)
              (select-at-canvas-point this event))
            (set-box! inspection-drag-box #f)]
           [else (void)])
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
                 [(wheel-up)
                  (define view-id (active-inspection-view-id))
                  (when view-id
                    (dolly-inspection-camera! view-id
                                                (- (send event get-wheel-steps))))]
                 [(wheel-down)
                  (define view-id (active-inspection-view-id))
                  (when view-id
                    (dolly-inspection-camera! view-id
                                                (send event get-wheel-steps)))]
                 [(#\r #\R) (reset-inspection-camera!)]
                 [(escape) (preview-pause! session)]
                 [else (void)])))
         (super on-char event))
       ;; Draw one measured semantic Visual box in preview device
       ;; coordinates.  This small bridge is shared by ordinary selection and
       ;; inspector overlays: the camera, not the preview bitmap scale, is the
       ;; authoritative mapping from an immutable scene path to pixels.
       (define (draw-visual-box-overlay dc source time preview-camera
                                        path x y width height color pen-width)
         (define inspection
           (scene-inspect-path source path time #:camera preview-camera))
         (when (and inspection (visual-inspection-layout-box inspection))
           (define box (visual-inspection-layout-box inspection))
           (define-values (left top)
             (camera-world->pixel preview-camera
                                  (vec2 (layout-box-left box) (layout-box-top box))))
           (define-values (right bottom)
             (camera-world->pixel preview-camera
                                  (vec2 (layout-box-right box) (layout-box-bottom box))))
           ;; `left` etc. are pixels in `preview-camera`, while the bitmap can
           ;; be a draft-scale rendering.  Scale from camera pixels directly,
           ;; not from bitmap pixels, otherwise the preview pixel scale is
           ;; applied twice.
           (define factor-x (/ width (camera-width preview-camera)))
           (define factor-y (/ height (camera-height preview-camera)))
           (send dc set-pen (make-pen #:color color #:width pen-width))
           (send dc set-brush (make-brush #:style 'transparent))
           (send dc draw-rectangle (+ x (* left factor-x))
                 (+ y (* top factor-y))
                 (* (- right left) factor-x)
                 (* (- bottom top) factor-y))))
       ;; A selected spatial item is overlaid after the rasterized viewport.
       ;; All of these marks are derived from immutable inspection data: they
       ;; are never appended to `view3d-children`, do not affect depth sorting,
       ;; and are absent from a rendered movie frame.
       (define (draw-spatial-selection-overlay dc source time preview-camera
                                               x y width height)
         (define selection (unbox spatial-pick-box))
         (when selection
           (define view-id (car selection))
           (define prior-pick (cdr selection))
           (define layout-inspection
             (scene-inspect-path source (list view-id) time #:camera preview-camera))
           (define outer-transform
             (and layout-inspection
                  (visual-inspection-composed-transform layout-inspection)))
           (define session (unbox controller-box))
           (define view (and session (resolved-inspection-view session view-id)))
           (when (and outer-transform view)
             (define inspection
               (or (view3d-spatial-inspection-at view (spatial-pick-path prior-pick))
                   (spatial-pick-inspection prior-pick)))
             (define bounds (spatial-inspection-world-bounds inspection))
             (define camera3d (view3d-camera view))
             (define aspect (/ (view3d-width view) (view3d-height view)))
             (define factor-x (/ width (camera-width preview-camera)))
             (define factor-y (/ height (camera-height preview-camera)))
             (define (project point)
               (define ndc (camera3d-project camera3d point #:aspect aspect))
               (and ndc
                    (let* ([local-point
                            (vec2 (* (/ (view3d-width view) 2) (vec2-x ndc))
                                  (* (/ (view3d-height view) 2) (vec2-y ndc)))]
                           [world-point
                            (affine2-apply-point
                             (affine-transform->affine2 outer-transform)
                             local-point)])
                      (define-values (pixel-x pixel-y)
                        (camera-world->pixel preview-camera world-point))
                      (cons (+ x (* pixel-x factor-x))
                            (+ y (* pixel-y factor-y))))))
             (define (draw-line-between first second)
               (when (and first second)
                 (send dc draw-line (car first) (cdr first) (car second) (cdr second))))
             (define (bounds-corners box)
               (define lo (aabb3-minimum box))
               (define hi (aabb3-maximum box))
               (for*/list ([px (in-list (list (vec3-x lo) (vec3-x hi)))]
                           [py (in-list (list (vec3-y lo) (vec3-y hi)))]
                           [pz (in-list (list (vec3-z lo) (vec3-z hi)))])
                 (vec3 px py pz)))
             ;; The world-space AABB is an honest bound even after local
             ;; rotation or shear.  Its twelve projected edges make selection
             ;; legible without creating a hidden wireframe object.
             (when (not (aabb3-empty? bounds))
               (define corners (map project (bounds-corners bounds)))
               (send dc set-smoothing 'smoothed)
               (send dc set-pen (make-pen #:color "goldenrod" #:width 2))
               (for ([edge (in-list '((0 1) (0 2) (0 4) (1 3) (1 5) (2 3)
                                      (2 6) (3 7) (4 5) (4 6) (5 7) (6 7)))])
                 (draw-line-between (list-ref corners (car edge))
                                    (list-ref corners (cadr edge)))))
             ;; The exact tested triangle is retained as inspector metadata.
             ;; Its cyan stroke distinguishes geometric picking from an AABB
             ;; candidate that happened merely to be under the pointer.
             (define triangle
               (hash-ref (spatial-pick-metadata prior-pick) 'world-triangle #f))
             (when (and (list? triangle) (= (length triangle) 3)
                        (andmap vec3? triangle))
               (define points (map project triangle))
               (send dc set-pen (make-pen #:color "deepskyblue" #:width 2))
               (draw-line-between (car points) (cadr points))
               (draw-line-between (cadr points) (caddr points))
               (draw-line-between (caddr points) (car points)))
             ;; A camera ray always collapses to its chosen screen pixel under
             ;; its own projection.  Mark that exact ray pixel rather than
             ;; drawing a misleading two-dimensional diagonal.
             (define hit-point (project (spatial-pick-point prior-pick)))
             (when hit-point
               (send dc set-pen (make-pen #:color "magenta" #:width 2))
               (send dc set-brush (make-brush #:style 'transparent))
               (send dc draw-ellipse (- (car hit-point) 5) (- (cdr hit-point) 5) 10 10))
             ;; The world-space normal and local frame help distinguish a
             ;; hit point from its containing object.  They are diagnostic
             ;; vectors only, never semantic arrows in the scene.
             (define frame-origin
               (affine3-apply-point (spatial-inspection-world-transform inspection) origin3))
             (define (draw-frame-axis local-point color)
               (define first (project frame-origin))
               (define second
                 (project
                  (affine3-apply-point (spatial-inspection-world-transform inspection)
                                       local-point)))
               (send dc set-pen (make-pen #:color color #:width 1))
               (draw-line-between first second))
             (draw-frame-axis (vec3 1/4 0 0) "crimson")
             (draw-frame-axis (vec3 0 1/4 0) "limegreen")
             (draw-frame-axis (vec3 0 0 1/4) "royalblue")
             (define normal-scale
               (if (aabb3-empty? bounds)
                   1/2
                   (max 1/5 (/ (vec3-length (aabb3-size bounds)) 4))))
             (define normal-end
               (vec3+ (spatial-pick-point prior-pick)
                      (vec3-scale normal-scale (spatial-pick-normal prior-pick))))
             (send dc set-pen (make-pen #:color "orange" #:width 2))
             (draw-line-between hit-point (project normal-end)))))
       ;; Formula source-map boxes are deliberately painted here rather than
       ;; turned into scene Visuals. They therefore describe the already
       ;; sampled bitmap and cannot perturb normal renderer, cache, or drawing
       ;; order semantics.
       (define (draw-inspector-overlays dc source time preview-camera
                                        x y width height)
         (define document (unbox inspector-document-box))
         (when (inspector-document? document)
           (for ([overlay (in-list (inspector-document-overlays document))])
             (case (inspector-overlay-kind overlay)
               [(formula-source-unit)
                (define metadata (inspector-overlay-metadata overlay))
                (define root-path (hash-ref metadata 'root-path #f))
                (define color (hash-ref (inspector-overlay-style overlay)
                                        'color "goldenrod"))
                (define pen-width (hash-ref (inspector-overlay-style overlay)
                                            'width 1))
                (when (and (list? root-path) (pair? root-path)
                           (list? (inspector-overlay-geometry overlay)))
                  (for ([relative-path
                         (in-list (inspector-overlay-geometry overlay))])
                    (draw-visual-box-overlay
                     dc source time preview-camera
                     (append root-path relative-path)
                     x y width height color pen-width)))]
               [(relation-dependency)
                (draw-relation-dependency-overlay
                 dc source time preview-camera overlay x y width height)]
               [(string-match-route)
                (draw-string-match-route-overlay
                 dc source time preview-camera overlay x y width height)]
               [else (void)]))))
       ;; Relation arrows are inspector-only: their endpoints are measured
       ;; layout boxes from the current scene, and their line/arrowhead is
       ;; painted after the cached bitmap.  A value dependency intentionally
       ;; has no route here because it has no fabricated world position.
       (define (draw-relation-dependency-overlay dc source time preview-camera
                                                 overlay x y width height)
         (define geometry (inspector-overlay-geometry overlay))
         (define metadata (inspector-overlay-metadata overlay))
         (define dependency-path (hash-ref geometry 'dependency-path #f))
         (define relation-path (hash-ref geometry 'relation-path #f))
         (when (and dependency-path relation-path)
           (define dependency-inspection
             (scene-inspect-path source dependency-path time #:camera preview-camera))
           (define relation-inspection
             (scene-inspect-path source relation-path time #:camera preview-camera))
           (when (and dependency-inspection relation-inspection
                      (visual-inspection-layout-box dependency-inspection)
                      (visual-inspection-layout-box relation-inspection))
             (define dependency-box
               (visual-inspection-layout-box dependency-inspection))
             (define relation-box
               (visual-inspection-layout-box relation-inspection))
             (define anchor (hash-ref metadata 'anchor #f))
             (define dependency-point
               (if anchor
                   (layout-box-anchor dependency-box anchor)
                   (layout-box-center dependency-box)))
             (define relation-point (layout-box-center relation-box))
             (define-values (from-x from-y)
               (camera-world->pixel preview-camera dependency-point))
             (define-values (to-x to-y)
               (camera-world->pixel preview-camera relation-point))
             (define factor-x (/ width (camera-width preview-camera)))
             (define factor-y (/ height (camera-height preview-camera)))
             (define start-x (+ x (* from-x factor-x)))
             (define start-y (+ y (* from-y factor-y)))
             (define end-x (+ x (* to-x factor-x)))
             (define end-y (+ y (* to-y factor-y)))
             (define color (hash-ref (inspector-overlay-style overlay)
                                     'color "mediumpurple"))
             (define pen-width (hash-ref (inspector-overlay-style overlay)
                                         'width 1))
             (send dc set-pen (make-pen #:color color #:width pen-width))
             (send dc draw-line start-x start-y end-x end-y)
             ;; The two short strokes give the dependency route an arrowhead
             ;; without adding a filled shape or any scene-level geometry.
             (define dx (- end-x start-x))
             (define dy (- end-y start-y))
             (define length (sqrt (+ (* dx dx) (* dy dy))))
             (when (> length 1)
               (define unit-x (/ dx length))
               (define unit-y (/ dy length))
               (define head-length (min 10 (/ length 2)))
               (define side-x (* -0.45 head-length unit-y))
               (define side-y (* 0.45 head-length unit-x))
               (define base-x (- end-x (* head-length unit-x)))
               (define base-y (- end-y (* head-length unit-y)))
               (send dc draw-line end-x end-y (+ base-x side-x) (+ base-y side-y))
               (send dc draw-line end-x end-y (- base-x side-x) (- base-y side-y))))))
       ;; String-match routes are compiled formula semantics, not a geometric
       ;; inference from the current bitmap. The formula transition plan stores
       ;; exact local endpoints and its selected route; the root's composed
       ;; transform makes those points world-space before camera projection.
       ;; This remains preview-only and works during interior frames where the
       ;; temporary formula layer names intentionally have no source map.
       (define (draw-string-match-route-overlay dc source time preview-camera
                                                overlay x y width height)
         (define geometry (inspector-overlay-geometry overlay))
         (define target-path (hash-ref geometry 'target-path #f))
         (define routes (hash-ref geometry 'routes '()))
         (when (and (list? target-path) (pair? target-path) (pair? routes))
           (define root-inspection
             (scene-inspect-path source target-path time #:camera preview-camera))
           (define root-transform
             (and root-inspection
                  (visual-inspection-composed-transform root-inspection)))
           (when root-transform
             (define color (hash-ref (inspector-overlay-style overlay)
                                     'color "goldenrod"))
             (define factor-x (/ width (camera-width preview-camera)))
             (define factor-y (/ height (camera-height preview-camera)))
             (define (route-canvas-point route fraction)
               (define local-point
                 (formula-route-position-at
                  (formula-transition-route-route route)
                  (affine-transform-translation
                   (formula-transition-route-from-transform route))
                  (affine-transform-translation
                   (formula-transition-route-to-transform route))
                  fraction))
               (define world-point
                 (affine-transform-apply-point root-transform local-point))
               (define-values (pixel-x pixel-y)
                 (camera-world->pixel preview-camera world-point))
               (values (+ x (* pixel-x factor-x))
                       (+ y (* pixel-y factor-y))))
             (send dc set-smoothing 'smoothed)
             (send dc set-pen (make-pen #:color color #:width 1))
             (send dc set-brush (make-brush #:style 'transparent))
             (for ([route (in-list routes)])
               ;; Twenty-four segments are enough for the inspector path,
               ;; including a strongly curved arc, without putting adaptive
               ;; render work into the GUI paint callback.
               (define-values (first-x first-y) (route-canvas-point route 0))
               (let loop ([index 1] [previous-x first-x] [previous-y first-y])
                 (when (<= index 24)
                   (define-values (next-x next-y)
                     (route-canvas-point route (/ index 24)))
                   (send dc draw-line previous-x previous-y next-x next-y)
                   (loop (add1 index) next-x next-y)))
               (define-values (end-x end-y) (route-canvas-point route 1))
               (send dc draw-ellipse (- end-x 2) (- end-y 2) 4 4)))))
       ;; The overlay is preview-only. It is drawn after the cached bitmap and
       ;; never enters scene->pict or the production frame path.
       (define (draw-selection-overlay dc x y width height bitmap)
         (define session (unbox controller-box))
         (when (and session (preview-transaction-session? session))
           (define path (preview-selection session))
           (with-handlers ([exn:fail? (lambda (_error) (void))])
             (define source (preview-source-scene (preview-source session)))
             (define time (preview-current-time session))
             ;; The cached bitmap may use a caller-supplied static camera.
             ;; Its raster size can be a draft-scale version of that camera,
             ;; but the camera's pixel coordinates remain the shared bridge
             ;; for inspection, hit testing, and the overlay.
             (define preview-camera (or camera (scene-camera-at source time)))
             ;; Transition and relation overlays describe the active scene
             ;; semantics, not just an explicit click selection.  Drawing them
             ;; here on every paint lets the string-match inspector remain
             ;; visible while playback has no selected Visual at all.
             (draw-inspector-overlays
              dc source time preview-camera x y width height)
             (draw-spatial-selection-overlay
              dc source time preview-camera x y width height)
             (when path
               (draw-visual-box-overlay
                dc source time preview-camera path x y width height "crimson" 2)))))
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
               (define preview-camera (or camera (scene-camera-at source time)))
               (define semantic-x
                 (* (/ local-x drawn-width) (camera-width preview-camera)))
               (define semantic-y
                 (* (/ local-y drawn-height) (camera-height preview-camera)))
               (define selected
                 (scene-hit-test source time semantic-x semantic-y #:camera preview-camera
                                 #:after-path (preview-selection session)))
               ;; A canvas hit is a Visual-side interaction. It supersedes a
               ;; prior source-character selection rather than retaining a
               ;; stale formula source span underneath an unrelated Visual.
               (set-box! inspector-source-selection-box #f)
               (preview-select! session (and selected (visual-inspection-path selected)))
               (update-selection-message!)
               (send canvas refresh))))))))
  ;; Keep everyday transport controls close to the canvas. Range review and
  ;; saved A/B comparisons are useful but much less frequent, so they occupy
  ;; separate rows. This keeps each strip short enough that the primary block,
  ;; section, and cue selectors stay visible in a narrow window.
  (define control-rows
    (new vertical-panel% [parent outer] [alignment '(center center)]
         [stretchable-width #t] [stretchable-height #f]))
  (define controls
    (new horizontal-panel% [parent control-rows] [alignment '(center center)]
         [stretchable-width #t] [stretchable-height #f]))
  (define range-controls
    (new horizontal-panel% [parent control-rows] [alignment '(center center)]
         [stretchable-width #t] [stretchable-height #f]))
  (define comparison-controls
    (new horizontal-panel% [parent control-rows] [alignment '(center center)]
         [stretchable-width #t] [stretchable-height #f]))
  ;; Construct this holder before the inspector. Its canvas is installed
  ;; below, after the inspector callbacks have been defined, but the holder
  ;; reserves the timeline's visual position directly below the controls.
  ;; That keeps the scrubber visible when an inspector section grows tall.
  (define timeline-holder
    (new vertical-panel% [parent outer] [alignment '(center center)]
         [stretchable-width #t] [stretchable-height #f]))
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
  (define range-message (new message% [parent range-controls] [label "range: none"]))
  (define speed-options (list (cons "0.5×" 1/2)
                              (cons "1×" 1)
                              (cons "1.5×" 3/2)
                              (cons "2×" 2)))
  (define speed-choice
    (new choice%
         [parent controls]
         [label "speed"]
         [choices (map car speed-options)]
         [callback
          (lambda (choice _event)
            (define session (unbox controller-box))
            (define index (send choice get-selection))
            (when (and session (exact-nonnegative-integer? index))
              (preview-set-playback-speed!
               session (cdr (list-ref speed-options index)))))]))
  (send speed-choice set-selection 1)
  (define zoom-options (list (cons "1×" 1)
                             (cons "2×" 2)
                             (cons "4×" 4)
                             (cons "8×" 8)))
  (define zoom-choice
    (new choice%
         [parent controls]
         [label "timeline zoom"]
         [choices (map car zoom-options)]
         [callback
          (lambda (choice _event)
            (define index (send choice get-selection))
            (when (exact-nonnegative-integer? index)
              (set-box!
               timeline-model-box
               (preview-timeline-set-zoom
                (unbox timeline-model-box)
                (cdr (list-ref zoom-options index))))
              (send timeline-canvas refresh)))]))
  (send zoom-choice set-selection 0)
  (define (selected-timeline-range)
    (preview-timeline-range (unbox timeline-model-box)))
  (define (install-range-message!)
    (define range (selected-timeline-range))
    (send range-message set-label
          (if range
              (format "range: ~a–~a s"
                      (real->decimal-string (timeline-range-start range) 2)
                      (real->decimal-string (timeline-range-end range) 2))
              "range: none")))
  (define play-range
    (new button%
         [parent range-controls]
         [label "Play range"]
         [callback
          (lambda (_button _event)
            (define session (unbox controller-box))
            (define range (selected-timeline-range))
            (when (and session range)
              (preview-play-range! session
                                   (timeline-range-start range)
                                   (timeline-range-end range))))]))
  (define loop-range
    (new button%
         [parent range-controls]
         [label "Loop range"]
         [callback
          (lambda (_button _event)
            (define session (unbox controller-box))
            (define range (selected-timeline-range))
            (when (and session range)
              (set-box!
               loop-range-box
               (preview-set-loop-range! session
                                        (timeline-range-start range)
                                        (timeline-range-end range)))
              (preview-play! session)))]))
  (define clear-loop
    (new button%
         [parent range-controls]
         [label "Clear loop"]
         [callback
          (lambda (_button _event)
            (define session (unbox controller-box))
            (when session
              (preview-clear-loop-range! session)
              (set-box! loop-range-box #f)
              (send timeline-canvas refresh)))]))
  (send play-range enable #f)
  (send loop-range enable #f)
  (send clear-loop enable #f)
  (define (save-comparison-range! slot)
    (when (selected-timeline-range)
      (set-box!
       timeline-model-box
       (preview-timeline-save-comparison
        (unbox timeline-model-box) slot))
      (send timeline-canvas refresh)))
  (define (play-comparison-range! slot)
    (define session (unbox controller-box))
    (define range
      (preview-timeline-comparison-range
       (unbox timeline-model-box) slot))
    (when (and session range)
      (preview-play-range! session
                           (timeline-range-start range)
                           (timeline-range-end range))))
  (define save-a
    (new button% [parent comparison-controls] [label "Save A"]
         [callback (lambda (_button _event) (save-comparison-range! 'a))]))
  (define play-a
    (new button% [parent comparison-controls] [label "Play A"]
         [callback (lambda (_button _event) (play-comparison-range! 'a))]))
  (define save-b
    (new button% [parent comparison-controls] [label "Save B"]
         [callback (lambda (_button _event) (save-comparison-range! 'b))]))
  (define play-b
    (new button% [parent comparison-controls] [label "Play B"]
         [callback (lambda (_button _event) (play-comparison-range! 'b))]))
  (define show-diagnostics
    (new check-box%
         [parent comparison-controls]
         [label "Diagnostics"]
         [value #f]
         [callback
          (lambda (checkbox _event)
            (define panel (unbox diagnostics-panel-box))
            (when panel
              (send panel show (send checkbox get-value))))]))
  ;; Mute is intentionally a project-audio control, not a controller command.
  ;; It does not stop or retime visual playback, request a new bitmap, or
  ;; invalidate any cache.  A project without an available audio monitor keeps
  ;; the affordance visible but correctly disabled.
  (define mute-audio
    (new check-box%
         [parent comparison-controls]
         [label "Mute"]
         [value (and (audio-mute-available?) (audio-muted?))]
         [callback
          (lambda (checkbox _event)
            (when (audio-mute-available?)
              (set-audio-muted! (send checkbox get-value))))]))
  (send mute-audio enable (and (audio-mute-available?) #t))
  (define selection-message (new message% [parent outer] [label "selection: none"]))
  ;; The inspector is deliberately a view of an immutable inspector document.
  ;; Selecting a section merely changes which existing rows are displayed: it
  ;; never asks the bitmap renderer for another semantic sample or changes a
  ;; frame-cache key.  Formula, relation, and active-transition panels can all
  ;; therefore coexist with ordinary Visual selection.
  (define inspector-document-box (box #f))
  ;; List-box item indexes are UI state only. The immutable inspector rows
  ;; retain their copyable commands, allowing the button below to copy a
  ;; source selector, string-match suggestion, or relation declaration without
  ;; re-running an inspector provider.
  (define inspector-rows-box (box '()))
  ;; A source-side inspector selection is not necessarily one Visual path:
  ;; one source unit can intentionally map to several formula leaves.  Keep
  ;; this stable `(root-path . source-index)` description apart from the
  ;; controller's ordinary single-path selection so source clicks never pick
  ;; an arbitrary rendered leaf.
  (define inspector-source-selection-box (box #f))
  (define inspector-section-choice #f)
  (define inspector-panel
    (new vertical-panel% [parent outer]
         [alignment '(left top)]
         [stretchable-width #t]
         [stretchable-height #f]))
  (define inspector-rows
    (new list-box% [parent inspector-panel]
         [label "Inspector"]
         [choices '()]
         [min-width 640]
         [min-height 110]
         [stretchable-width #t]
         [stretchable-height #f]))
  (define formula-source-label
    (new message% [parent inspector-panel]
         [label "Formula source — click a mapped character"] ))
  (define formula-source-canvas
    (new
     (class canvas%
       (super-new [parent inspector-panel]
                  [min-width 640]
                  [min-height 32]
                  [stretchable-width #t]
                  [stretchable-height #f]
                  [style '(border)])
       (define/override (on-paint)
         (define dc (send this get-dc))
         (send dc set-background (make-object color% 250 250 250))
         (send dc clear)
         (define document (unbox inspector-document-box))
         (define formula (inspector-document-formula document))
         (when formula
           (define source (formula-source formula))
           (define selected-match
             (inspector-document-selected-source-match document))
           (send dc set-font (make-object font% 14 'modern 'normal 'normal))
           (define-values (_sample-width line-height _descent _space)
             (send dc get-text-extent "M"))
           (let loop ([index 0] [cursor-x 6] [cursor-y 4])
             (when (< index (string-length source))
               (define character (string-ref source index))
               (cond
                 [(char=? character #\newline)
                  (loop (add1 index) 6 (+ cursor-y line-height))]
                 [else
                  (define-values (character-width _height _d _s)
                    (send dc get-text-extent (string character)))
                  (when (source-character-selected? selected-match index)
                    (send dc set-pen (make-pen #:color "mistyrose" #:width 1))
                    (send dc set-brush (make-brush #:color "mistyrose" #:style 'solid))
                    (send dc draw-rectangle cursor-x cursor-y character-width line-height))
                  (send dc set-text-foreground
                        (source-character-color formula selected-match index))
                  (send dc draw-text (string character) cursor-x cursor-y)
                  (loop (add1 index) (+ cursor-x character-width) cursor-y)])))))
       (define/override (on-event event)
         (when (eq? (send event get-event-type) 'left-down)
           (define document (unbox inspector-document-box))
           (define formula (inspector-document-formula document))
           (when formula
             (define index
               (source-character-index-at (send this get-dc)
                                          (formula-source formula)
                                          (send event get-x)
                                          (send event get-y)))
             (when (exact-nonnegative-integer? index)
               (select-inspector-source-index! index))))
         (super on-event event)))))
  (send formula-source-label show #f)
  (send formula-source-canvas show #f)
  ;; A spatial hierarchy belongs below its owning view3d, not in the ordinary
  ;; Visual tree. Keep it a preview section assembled from immutable inspection
  ;; records so choosing it cannot change scene selection or trigger a render.
  (define (spatial-hierarchy-section)
    (define session (unbox controller-box))
    (define view-id (active-spatial-view-id))
    (define selected (active-spatial-pick))
    (define view (and session view-id (resolved-inspection-view session view-id)))
    (and view
         (inspector-section
          'spatial-hierarchy "3D spatial hierarchy"
          (for/list ([entry (in-list (view3d-spatial-inspections view))])
            (define path (spatial-inspection-path entry))
            (define depth (max 0 (sub1 (length path))))
            (define selected? (and selected
                                   (equal? path (spatial-pick-path selected))))
            (inspector-row
             (format "~a~a~a"
                     (make-string (* 2 depth) #\space)
                     (if selected? "▶ " "")
                     (list-ref path (sub1 (length path))))
             (format "~a; ~a triangles; ~a vertices; depth ~a"
                     (spatial-inspection-kind entry)
                     (spatial-inspection-triangle-count entry)
                     (spatial-inspection-vertex-count entry)
                     (or (spatial-inspection-view-depth entry) "n/a"))
             'info
             (list
              (inspector-action
               'copy-spatial-path "Copy spatial path"
               `(copy-spatial-path ,path) #t))))
          #f)))
  (define (available-inspector-sections document)
    (append (if (inspector-document? document)
                (inspector-document-sections document)
                '())
            (let ([spatial (spatial-hierarchy-section)])
              (if spatial (list spatial) '()))))
  (define (display-inspector-section! index)
    (define document (unbox inspector-document-box))
    (define sections (available-inspector-sections document))
    (send inspector-rows clear)
    (set-box! inspector-rows-box '())
    (cond
      [(and (exact-nonnegative-integer? index) (< index (length sections)))
       (define section (list-ref sections index))
       (set-box! inspector-rows-box (inspector-section-rows section))
       (for ([row (in-list (inspector-section-rows section))])
         (define severity-prefix
           (case (inspector-row-severity row)
             [(warning) "warning: "]
             [(error) "error: "]
             [else ""]))
         (define action-suffix
           (if (null? (inspector-row-actions row))
               ""
               (format "  [~a]"
                       (string-join
                        (for/list ([action (in-list (inspector-row-actions row))])
                          (inspector-action-label action))
                        ", "))))
         (send inspector-rows append
               (list-control-label
                (format "~a~a: ~s~a"
                        severity-prefix
                        (inspector-row-label row)
                        (inspector-row-value row)
                        action-suffix))))
       (when (null? (inspector-section-rows section))
         (send inspector-rows append "No rows in this inspector section."))]
      [else
       (send inspector-rows append
             "Select a Visual, or pause in a string transition, to inspect its semantics.")]))
  (define (install-inspector-document! document)
    (set-box! inspector-document-box document)
    (define formula (inspector-document-formula document))
    (send formula-source-label show (and formula #t))
    (send formula-source-canvas show (and formula #t))
    (when formula
      (send formula-source-canvas refresh))
    (define sections (available-inspector-sections document))
    (send inspector-section-choice clear)
    (for ([section (in-list sections)])
      (send inspector-section-choice append (inspector-section-title section)))
    (send inspector-section-choice enable (pair? sections))
    (send inspector-section-choice show (pair? sections))
    (when (pair? sections)
      (send inspector-section-choice set-selection 0))
    (display-inspector-section! (and (pair? sections) 0)))
  (define (select-inspector-source-index! index)
    ;; This is source-to-Visual selection. The source unit is represented by
    ;; its formula root and exact source index, not by one arbitrary leaf, so
    ;; a span that maps to multiple leaves continues to highlight every leaf.
    (define session (unbox controller-box))
    (define document (unbox inspector-document-box))
    (define formula (inspector-document-formula document))
    (define root-path
      (and (inspector-document? document)
           (inspector-subject-root-path (inspector-document-subject document))))
    (when (and session formula (list? root-path)
               (exact-nonnegative-integer? index)
               (< index (string-length (formula-source formula))))
      (set-box! inspector-source-selection-box (cons root-path index))
      ;; No single controller selection denotes a multi-leaf formula source
      ;; unit. Clear the old Visual selection and let the inspector document
      ;; install its precise source-match overlays instead.
      (preview-select! session #f)
      (update-selection-message!)
      (send canvas refresh)))
  (set! inspector-section-choice
        (new choice% [parent inspector-panel] [label "Inspector section"] [choices '()]
             [min-width 220]
             [callback
              (lambda (choice _event)
                (display-inspector-section! (send choice get-selection)))]))
  (send inspector-section-choice show #f)
  (display-inspector-section! #f)
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
  (define copy-inspector-action
    (new button% [parent outer] [label "Copy inspector action"]
         [callback
          (lambda (_button _event)
            (define index (send inspector-rows get-selection))
            (define rows (unbox inspector-rows-box))
            (when (and (exact-nonnegative-integer? index)
                       (< index (length rows)))
              (define action
                (for/first ([candidate
                             (in-list (inspector-row-actions
                                       (list-ref rows index)))]
                            #:when (and (inspector-action-enabled? candidate)
                                        (regexp-match? #rx"^copy-"
                                                       (symbol->string
                                                        (inspector-action-id candidate)))))
                  candidate))
              (when action
                ;; Actions remain immutable semantic commands in the inspector
                ;; model. The GUI performs only the explicitly requested
                ;; clipboard side effect.
                (send the-clipboard
                      set-clipboard-string
                      (format "~s" (inspector-action-command action))
                      0))))]))
  (define select-inspector-source-unit
    (new button% [parent outer] [label "Select mapped source unit"]
         [callback
          (lambda (_button _event)
            (define session (unbox controller-box))
            (define index (send inspector-rows get-selection))
            (define rows (unbox inspector-rows-box))
            (when (and session
                       (exact-nonnegative-integer? index)
                       (< index (length rows)))
              (define action
                (for/first ([candidate
                             (in-list (inspector-row-actions
                                       (list-ref rows index)))]
                            #:when (and (eq? (inspector-action-id candidate)
                                             'select-source-unit)
                                        (inspector-action-enabled? candidate)))
                  candidate))
              (when action
                (match (inspector-action-command action)
                  [`(select-source-unit ,path)
                   ;; This is the source-to-Visual direction of the inspector.
                   ;; The provider enables the action only when exactly one
                   ;; mapped leaf exists, so the GUI never picks an arbitrary
                   ;; glyph from a multi-leaf source span.
                   (set-box! inspector-source-selection-box #f)
                   (preview-select! session path)
                   (update-selection-message!)
                   (send canvas refresh)]
                  [_ (void)]))))]))
  (define diagnostics-panel
    (new vertical-panel% [parent outer]
         [alignment '(left top)]
         [stretchable-width #t]
         [stretchable-height #f]))
  (set-box! diagnostics-panel-box diagnostics-panel)
  (send diagnostics-panel show #f)
  (define diagnostics-rows
    (new list-box% [parent diagnostics-panel]
         [label "Production diagnostics"]
         [choices '()]
         [min-width 640]
         [min-height 110]
         [stretchable-width #t]
         [stretchable-height #f]))
  (define (install-diagnostics! session)
    ;; This function runs only in the GUI eventspace, after the controller has
    ;; published an immutable event. Querying it here cannot recursively block
    ;; the controller event callback.
    (define report (preview-session-diagnostics session))
    (define recent (hash-ref report 'recent-render-diagnostics #hasheq()))
    (define (value key [fallback "n/a"])
      (hash-ref report key fallback))
    (define (render-value key)
      (hash-ref recent key "n/a"))
    (send diagnostics-rows clear)
    (for ([entry
           (in-list
            (list
             (cons "timeline time" (value 'timeline-time))
             (cons "desired frame" (value 'desired-frame))
             (cons "displayed frame" (value 'displayed-frame))
             (cons "visual lag (ms)" (value 'visual-lag-milliseconds))
             (cons "quality" (value 'preview-quality))
             (cons "recent render (ms)" (render-value 'render-milliseconds))
             (cons "cache (entries / bytes)"
                   (list (value 'cache-count) (value 'cache-bytes)))
             (cons "pending / canceled"
                   (list (value 'pending-requests) (value 'canceled-requests)))
             (cons "worker"
                   (list (value 'worker-mode)
                         (value 'worker-hard-cancellation?)))))])
      (send diagnostics-rows append
            (format "~a: ~a" (car entry) (cdr entry)))))
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
         [min-width 180]
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
  (define cue-choice
    (new choice% [parent controls] [label "cue"] [choices '()]
         [callback
          (lambda (choice _event)
            (define session (unbox controller-box))
            (define selected-index (send choice get-selection))
            (when (and session
                       (exact-nonnegative-integer? selected-index)
                       (positive? selected-index))
              (preview-jump-to-cue!
               session
               (string->symbol (send choice get-string selected-index)))))]))
  ;; A plain Scene has no authored cues.  Hide this rather than presenting a
  ;; disabled affordance that suggests cue navigation is available.
  (send cue-choice show #f)
  (define timeline-canvas
    (new
     (class canvas%
       (super-new [parent timeline-holder]
                  [min-width 640]
                  [min-height 130]
                  [stretchable-width #t]
                  [stretchable-height #f])
       (define dragging? #f)
       (define range-dragging? #f)
       (define range-start #f)
       (define lane-colors
         (hasheq 'blocks "slateblue" 'sections "steelblue" 'audio "darkseagreen"
                 'waveform "mediumseagreen" 'subtitles "goldenrod" 'cues "crimson"))
       (define/override (on-paint)
         (define dc (send this get-dc))
         (define-values (width height) (send this get-client-size))
         (send dc set-background (make-object color% 34 36 38))
         (send dc clear)
         (define model (unbox timeline-model-box))
         (define window (preview-timeline-visible-range model))
         (define left 100)
         (define right (max (+ left 1) (- width 12)))
         (define top 10)
         (define lanes (preview-timeline-lanes model))
         (define lane-height
           (max 18 (inexact->exact
                    (floor (/ (max 1 (- height 20)) (max 1 (length lanes)))))))
         (define span (max 1/1000 (- (timeline-range-end window)
                                     (timeline-range-start window))))
         (define (x-at time)
           (+ left (* (/ (- time (timeline-range-start window)) span)
                      (- right left))))
         ;; A range selection is an editorial overlay. It is painted before
         ;; all lanes so it never changes their source/block/audio geometry.
         (define selected-range (preview-timeline-range model))
         (when selected-range
           (define start (max left (x-at (timeline-range-start selected-range))))
           (define end (min right (x-at (timeline-range-end selected-range))))
           (send dc set-pen (make-pen #:color "slateblue" #:width 1))
           (send dc set-brush (make-brush #:color "midnightblue" #:style 'solid))
           (send dc draw-rectangle start 0 (max 1 (- end start)) height))
         ;; A/B markers are saved editorial comparisons. They deliberately
         ;; remain separate from the selected range and the controller's loop
         ;; range, so an author can inspect or play either comparison without
         ;; changing the active transport policy.
         (define (draw-comparison range color label)
           (when range
             (define start (max left (x-at (timeline-range-start range))))
             (define end (min right (x-at (timeline-range-end range))))
             (send dc set-pen (make-pen #:color color #:width 2 #:style 'dot))
             (send dc set-brush (make-brush #:style 'transparent))
             (send dc draw-rectangle start 2 (max 1 (- end start)) (max 1 (- height 4)))
             (send dc set-text-foreground color)
             (send dc draw-text label (+ start 3) 3)))
         (draw-comparison (preview-timeline-comparison-range model 'a)
                          "goldenrod" "A")
         (draw-comparison (preview-timeline-comparison-range model 'b)
                          "turquoise" "B")
         ;; The active loop comes from controller status. The selected range
         ;; may be changed freely without silently changing playback policy.
         (define loop-range (unbox loop-range-box))
         (when loop-range
           (define start (max left (x-at (preview-playback-range-start loop-range))))
           (define end (min right (x-at (preview-playback-range-end loop-range))))
           (send dc set-pen (make-pen #:color "orchid" #:width 2 #:style 'short-dash))
           (send dc set-brush (make-brush #:style 'transparent))
           (send dc draw-rectangle start 1 (max 1 (- end start)) (max 1 (- height 2))))
         (send dc set-font (make-object font% 11 'default 'normal 'normal))
         (for ([lane (in-list lanes)] [index (in-naturals)])
           (define y (+ top (* index lane-height)))
           (send dc set-text-foreground "gainsboro")
           (send dc draw-text (timeline-lane-label lane) 8 (+ y 2))
           (send dc set-pen (make-pen #:color "gray" #:width 1))
           (send dc draw-line left (+ y (/ lane-height 2)) right (+ y (/ lane-height 2)))
           (define color (hash-ref lane-colors (timeline-lane-id lane) "gray"))
           (for ([entry (in-list (timeline-lane-entries lane))])
             (define entry-left (max left (x-at (timeline-entry-start entry))))
             (define entry-right (min right (x-at (timeline-entry-end entry))))
             (cond
               [(and (eq? (timeline-lane-id lane) 'waveform)
                     (waveform? (timeline-entry-payload entry)))
                ;; The envelope is drawn from precomputed min/max buckets,
                ;; never by decoding audio in the paint callback.  Each pixel
                ;; chooses the appropriate bucket for the current timeline
                ;; zoom, so it remains smooth both in overview and close-up.
                (define wave (timeline-entry-payload entry))
                (define columns (max 1 (inexact->exact (ceiling (- entry-right entry-left)))))
                (define level (waveform-level-for-width wave columns))
                (define minima (waveform-level-minima level))
                (define maxima (waveform-level-maxima level))
                (define samples-per-bucket (waveform-level-samples-per-bucket level))
                (define sample-rate (waveform-sample-rate wave))
                (define center (+ y (/ lane-height 2)))
                (define amplitude (max 1 (- (/ lane-height 2) 3)))
                (send dc set-pen (make-pen #:color color #:width 1))
                (for ([column (in-range columns)])
                  (define pixel-x (+ entry-left column))
                  (define time
                    (+ (timeline-range-start window)
                       (* (/ (- pixel-x left) (max 1 (- right left))) span)))
                  (define bucket
                    (inexact->exact
                     (floor (/ (* (max 0 time) sample-rate) samples-per-bucket))))
                  (when (< bucket (vector-length minima))
                    (define low (vector-ref minima bucket))
                    (define high (vector-ref maxima bucket))
                    (send dc draw-line pixel-x
                          (- center (* high amplitude))
                          pixel-x
                          (- center (* low amplitude)))))]
               [else
                (send dc set-pen (make-pen #:color color #:width 1))
                (send dc set-brush (make-brush #:color color #:style 'solid))
                (if (= (timeline-entry-start entry) (timeline-entry-end entry))
                    (send dc draw-line entry-left y entry-left (+ y lane-height -2))
                    (send dc draw-rectangle entry-left (+ y 3)
                          (max 2 (- entry-right entry-left)) (max 4 (- lane-height 6))))])))
         (define playhead (x-at (preview-timeline-cursor model)))
         (send dc set-pen (make-pen #:color "white" #:width 2))
         (send dc draw-line playhead 0 playhead height))
       (define (seek-event! event)
         (define session (unbox controller-box))
         (when session
           (define time (event-time event))
           (define model (unbox timeline-model-box))
           (set-box! timeline-model-box (preview-timeline-seek model time))
           (preview-scrub! session time)
           (send this refresh)))
       (define (event-time event)
         (define-values (width _height) (send this get-client-size))
         (define model (unbox timeline-model-box))
         (define window (preview-timeline-visible-range model))
         (define left 100)
         (define right (max (+ left 1) (- width 12)))
         (define ratio
           (min 1 (max 0 (/ (- (send event get-x) left) (- right left)))))
         (+ (timeline-range-start window)
            (* ratio (- (timeline-range-end window)
                        (timeline-range-start window)))))
       (define (select-range-event! event)
         (define end (event-time event))
         (when (and range-start (not (= range-start end)))
           (define model (unbox timeline-model-box))
           (set-box!
            timeline-model-box
            (preview-timeline-select-range
             model (min range-start end) (max range-start end)))
           (install-range-message!)
           (send play-range enable #t)
           (send loop-range enable #t)
           (send this refresh)))
       (define/override (on-event event)
         (case (send event get-event-type)
           [(left-down)
            (if (send event get-shift-down)
                (begin
                  (set! range-dragging? #t)
                  (set! range-start (event-time event)))
                (begin
                  (set! dragging? #t)
                  (seek-event! event)))]
           [(left-up)
            (when range-dragging? (select-range-event! event))
            (set! dragging? #f)
            (set! range-dragging? #f)
            (set! range-start #f)]
           [(motion)
            (cond
              [range-dragging? (select-range-event! event)]
              [dragging? (seek-event! event)])]
           [else (void)])
         (super on-event event)))))
  (define model
    (window-model #f #f canvas timeline-canvas frame-message time-message section-choice block-choice
                  status-message play selection-message inspector-rows 0 #f))
  (define (current-inspector-source-block session)
    ;; A source-block inspector entry comes from the retained source-program
    ;; compilation, never from the rendered timeline lane.  Plain scenes and
    ;; authored timelines intentionally have no fabricated source block.
    (and (program-preview-session? session)
         (let ([id (preview-current-block session)])
           (and id
                (let ([range
                       (for/first ([entry (in-list (preview-program-block-ranges session))]
                                   #:when (eq? id (car entry)))
                         entry)])
                  (and range
                       (inspector-source-block
                        id
                        (cadr range)
                        (caddr range)
                        (preview-current-block-source-location session)
                        (preview-program-generation session)
                        (preview-program-branch-mode session))))))))
  (define (update-selection-message!)
    (define session (unbox controller-box))
    (when (and session (preview-transaction-session? session))
      (define selection (preview-selection session))
      (define reload-diagnostic
        (preview-selection-reload-diagnostic session))
      (with-handlers
          ([exn:fail?
            (lambda (error)
              ;; Keep a rendering or inspector-provider failure local to the
              ;; inspector.  The already rendered preview frame remains
              ;; usable and no retry is scheduled solely for this message.
              (install-inspector-document! #f)
              (send inspector-rows clear)
              (send inspector-rows append
                    (list-control-label
                     (format "Inspector unavailable: ~a" (exn-message error)))))])
        (define source (preview-source-scene (preview-source session)))
        (define time (preview-current-time session))
        (define source-selection (unbox inspector-source-selection-box))
        (define source-subject
          (and source-selection
               (let ([root-path (car source-selection)]
                     [index (cdr source-selection)])
                 (with-handlers ([exn:fail? (lambda (_error) #f)])
                   (let-values ([(state _camera)
                                 (scene-sample-with-camera source time)])
                     (define formula (scene-state-ref state root-path))
                     (and (formula-assembly-visual? formula)
                          (or (formula-source-index-subject formula index root-path)
                              ;; Whitespace and unsafe/unmapped source still
                              ;; select the formula panel, which explains why
                              ;; no rendered leaf can be highlighted.
                              (visual-inspector-subject formula root-path))))))))
        (define selected-subject
          (or source-subject
              (and selection
                   (let-values ([(state _camera) (scene-sample-with-camera source time)])
                     (scene-inspector-subject-at-path state selection)))))
        (define production-diagnostics (preview-session-diagnostics session))
        (define recent-render-diagnostics
          (hash-ref production-diagnostics 'recent-render-diagnostics #hasheq()))
        (define document
          (scene-inspector-document
           source time
           #:subject selected-subject
           #:source-block (current-inspector-source-block session)
           #:render-diagnostics
           (and (positive? (hash-count recent-render-diagnostics))
                recent-render-diagnostics)))
        (install-inspector-document! document)
        (send selection-message set-label
              (string-append
               (cond
                 [source-selection
                 (format "source selection: ~s at character ~a~a"
                          (car source-selection)
                          (cdr source-selection)
                          (if (and source-subject
                                   (not (eq? (inspector-subject-kind source-subject)
                                             'formula-source-match)))
                              " — no mapped visible ink"
                              ""))]
                 [(active-spatial-pick)
                  (define pick (active-spatial-pick))
                  (format "3D selection: ~s, triangle ~a"
                          (spatial-pick-path pick)
                          (spatial-pick-triangle-index pick))]
                 [selection (format "selection: ~s" selection)]
                 [else "selection: none"])
               (if reload-diagnostic
                   (format " — ~a" reload-diagnostic)
                   ""))))))
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
  (define (install-cue-navigation!)
    (define session (unbox controller-box))
    (define timeline
      (and session
           (preview-open? session)
           (let ([source (preview-source session)])
             (and (authored-timeline? source) source))))
    (define names
      (if timeline
          (map cue-name (authored-timeline-cues timeline))
          '()))
    (unless (equal? names (unbox cue-names-box))
      (set-box! cue-names-box names)
      (send cue-choice clear)
      (send cue-choice append "")
      (for ([name (in-list names)])
        (send cue-choice append (symbol->string name)))
      (send cue-choice enable (pair? names)))
    ;; Cues belong to authored timelines, so their selector is intentionally
    ;; independent of the program-preview block chooser.
    (send cue-choice show (pair? names)))
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
      ;; The timeline is a second view of the exact retained source-program
      ;; compilation. Refresh it even when the block names did not change:
      ;; editing a block can legitimately move the start/end of later blocks.
      (define previous (unbox timeline-model-box))
      (set-box!
       timeline-model-box
       (preview-timeline-seek
        (make-preview-timeline
         (scene-duration (preview-source-scene (preview-source session)))
         #:blocks (preview-program-block-ranges session)
         #:zoom (preview-timeline-zoom previous))
        (preview-current-time session)))
      (send timeline-canvas refresh)
      ;; A source program has source blocks, not implicit authored sections.
      ;; Its explicit block selector replaces the generic section control.
      (send section-choice show #f)
      (send block-choice show (pair? names))))
  (define (install-event event)
    ;; This continuation is always run in the GUI eventspace.
    ;; Controller events are queued before they enter the GUI eventspace. A
    ;; close may therefore make an already queued event stale.  Do not query
    ;; the closed actor merely to update a window the author just dismissed.
    (define active-session (unbox controller-box))
    (when (and active-session (preview-open? active-session))
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
      ;; A scene reload can add, remove, or retime named cue markers.  Refresh
      ;; the independently derived cue picker on every immutable controller
      ;; status event, without coupling it to bitmap rendering.
      (install-cue-navigation!)
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
      (set-box! timeline-model-box
                (preview-timeline-seek (unbox timeline-model-box)
                                       (preview-status-time status)))
      (set-box! loop-range-box (preview-status-loop-range status))
      (send clear-loop enable (and (preview-status-loop-range status) #t))
      (define speed-index
        (for/first ([index (in-naturals)]
                    [option (in-list speed-options)]
                    #:when (= (cdr option)
                              (preview-status-playback-speed status)))
          index))
      (when speed-index
        (send speed-choice set-selection speed-index))
      (define audio-available? (audio-mute-available?))
      (send mute-audio enable audio-available?)
      (when audio-available?
        (send mute-audio set-value (and (audio-muted?) #t)))
      (send timeline-canvas refresh)
      (install-diagnostics! session)
      (define current (preview-status-current-section status))
      (when current
        (define desired (symbol->string current))
        (define selection-index
          (for/first ([index (in-range (send section-choice get-number))]
                      #:when (equal? (send section-choice get-string index) desired))
            index))
        (when selection-index
          (send section-choice set-selection selection-index)))
        (update-selection-message!))
      (set-window-model-handling?! model #f)))
  (define session
    (open-preview-controller
     source #:fps fps #:start start #:section section #:camera camera
     #:renderers renderers #:pixel-scale pixel-scale
     #:cache-megabytes cache-megabytes #:prefetch prefetch
     #:worker-mode worker-mode
     #:producer producer
     #:on-event
     (lambda (event)
       (queue-callback (lambda () (install-event event)) #f)
       ;; Audio and other production monitors receive the exact immutable
       ;; controller event after it has been queued for the GUI.  They do not
       ;; get access to controller state or its bitmap cache.
       (with-handlers ([exn:fail? (lambda (_error) (void))])
         (on-preview-event event)))))
  (set-window-model-session! model session)
  (set-box! controller-box session)
  (attach-preview-transactions! session #:initial-scene (preview-source-scene source))
  (hash-set! block-navigation-updaters session install-block-navigation!)
  (preview-add-close-hook!
   session
   (lambda ()
     (hash-remove! block-navigation-updaters session)))
  (set-window-model-frame-count! model frame-count)
  (define section-names (preview-section-names session))
  (install-section-navigation! section-names)
  (install-cue-navigation!)
  (send frame show #t)
  session)
