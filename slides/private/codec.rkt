#lang racket/base

;; The parent freezes drawing commands and math/geometry preparation as data/artifacts.
;; Workers reconstruct local Scene values; neither arbitrary closures nor Pict
;; objects cross the process boundary. Reading an artifact never evaluates it.
(require racket/class racket/file racket/list racket/match racket/path racket/runtime-path racket/port
         (only-in racket/draw record-dc% recorded-datum->procedure)
         (prefix-in p: pict) file/sha1
         (prefix-in a: "../../main.rkt")
         (prefix-in c: "../../colors.rkt")
         (prefix-in ty: "../../typography.rkt")
         (prefix-in at: "../../authoring.rkt")
         "data.rkt" "check.rkt" "appearance.rkt" "native.rkt" "sample.rkt" "semantic-model.rkt"
         (only-in "model.rkt" slide-transition))
(provide prepared-storyboard->payload! payload->prepared-storyboard)
(define-runtime-path math-codec "../../math/private/prepared-plan-codec.rkt")
(define-runtime-path math-artifacts "../../math/private/preparation-artifacts.rkt")
(define-runtime-path math-render "../../math/render.rkt")
(define-runtime-path geometry-codec "../../geometry/private/render-preparation-codec.rkt")
(define (math-binding module name) (dynamic-require module name))
(define (rect->data b) (and b (list (box-value-x b) (box-value-y b) (box-value-width b) (box-value-height b))))
(define (data->rect d)
  (and d (match d [(list (? finite-number? x) (? finite-number? y) (? nonnegative-number? w) (? nonnegative-number? h)) (box-value x y w h)]
               [_ (slides-error 'invalid-payload '() "invalid prepared rectangle")])) )
(define (format->data f) (list (format-value-id f) (format-value-width f) (format-value-height f)))
(define (data->format d) (match d [(list id w h) (slide-format #:id id #:width w #:height h)] [_ (slides-error 'invalid-payload '() "invalid format")]))
(define (theme->data t)
  (list (theme-value-id t) (c:theme->datum (theme-value-colors t)) (ty:typography-theme->datum (theme-value-typography t))
        (theme-value-spacing t) (theme-value-decorations t)))
(define (data->theme d)
  (match d [(list id c t spacing decorations)
            (slide-theme #:id id #:colors (c:datum->theme c) #:typography (ty:datum->typography-theme t)
                         #:spacing spacing #:decorations decorations)]))
(define (camera->data cam)
  (list (a:camera-width cam) (a:camera-height cam) (a:camera-world-width cam)
        (a:vec2-x (a:camera-center cam)) (a:vec2-y (a:camera-center cam))))
(define (data->camera d)
  (match d [(list w h world x y) (a:make-camera #:width w #:height h #:world-width world #:center (a:vec2 x y)
                                              #:background (c:rgba-color 0 0 0 0))]))
(define (narration->data n)
  (and n (list (prepared-narration-text n) (prepared-narration-audio n) (prepared-narration-start n)
               (prepared-narration-duration n) (prepared-narration-source-start n) (prepared-narration-captions n))))
(define (data->narration d) (and d (apply prepared-narration d)))
(define (event->data e)
  (list (event-kind e) (event-target e) (event-start e) (event-duration e) (event-from e) (event-to e) (event-effect e) (event-variant e)))
(define (source-variants clip name)
  (remove-duplicates
   (cons (slot-value-content (hash-ref (slide-value-slots (clip-value-slide clip)) name))
         (for*/list ([b (in-list (clip-value-beats clip))] [a (in-list (beat-value-actions b))]
                     #:when (and (eq? (action-value-kind a) 'replace) (equal? (action-value-target a) (list name))))
           (action-value-payload a))) equal?))
(define (source-shot board id)
  (or (findf (lambda (s) (and (shot-value? s) (eq? id (shot-value-id s)))) (storyboard-value-entries board))
      (slides-error 'source-mismatch (list id) "prepared shot does not occur in this source")))
(define (record-picture picture)
  (define dc (new record-dc% [width (p:pict-width picture)] [height (p:pict-height picture)]))
  (p:draw-pict picture dc 0 0)
  (list 'slide-recording-v1 (p:pict-width picture) (p:pict-height picture)
        (p:pict-ascent picture) (p:pict-descent picture) (send dc get-recorded-datum)))
(define (replay-picture data)
  (match data
    [(list 'slide-recording-v1 w h ascent descent recording)
     (define replay (recorded-datum->procedure recording))
     (p:dc (lambda (dc x y)
             (define old (send dc get-transformation))
             (dynamic-wind void
               (lambda () (send dc translate x y) (replay dc))
               (lambda () (send dc set-transformation old)))) w h ascent descent)]
    [_ (slides-error 'invalid-artifact '() "invalid recorded Pict artifact")]))
(define (prepared-storyboard->payload! board asset-base)
  (define directory (build-path asset-base ".animate-slide-preparation-v1"))
  (make-directory* directory)
  (define artifacts '()) (define dependencies '())
  (define encoded-geometry (make-hasheq))
  (define (stage-datum! datum [role 'slide-prepared-drawing])
    (define bytes (call-with-output-bytes (lambda (out) (write datum out))))
    (define digest (sha1 (open-input-bytes bytes)))
    (define path (build-path directory (string-append digest ".rktd")))
    (unless (and (file-exists? path) (equal? digest (call-with-input-file path sha1)))
      (define tmp (make-temporary-file "record-~a" #f directory))
      (dynamic-wind void
        (lambda () (display-to-file bytes tmp #:exists 'truncate/replace) (rename-file-or-directory tmp path #t))
        (lambda () (when (file-exists? tmp) (delete-file tmp)))))
    (set! artifacts (cons (hash 'path (path->string path) 'role role) artifacts))
    (list (path->string path) digest))
  (define (encode-asset asset)
    (define meta (asset-metadata asset))
    (for ([cue (in-list (hash-ref meta 'audio '()))])
      (define path (at:audio-cue-source cue))
      (unless (complete-path? path)
        (slides-error 'child-audio-path '() "imported audio needs a complete path, preferably define-runtime-path"))
      (set! dependencies (cons (hash 'path (if (path? path) (path->string path) path) 'role 'slide-child-audio) dependencies)))
    (when (hash-ref meta 'source #f)
      (set! dependencies (cons (hash 'path (hash-ref meta 'source) 'role 'slide-image) dependencies)))
    (define payload
      (if (hash-ref meta 'state-base #f)
          (list 'state (hash-ref meta 'state-time) (encode-asset (hash-ref meta 'state-base)))
          (case (asset-kind asset)
        [(pict) (list 'recording (stage-datum! (record-picture (asset-value asset))))]
        [(native)
         (define bundle (asset-value asset))
         (define kind (hash-ref meta 'kind))
         (case kind
           [(math)
            (define prepared (hash-ref meta 'prepared-math))
            (define staged ((math-binding math-artifacts 'stage-prepared-svg-artifacts!) prepared asset-base))
            (set! artifacts (append ((math-binding math-artifacts 'staged-svg-artifact-descriptors) staged) artifacts))
            (define options (hash 'schema 'slide-math-v1 'camera (camera->data (native-bundle-camera bundle))))
            (list 'math (camera->data (native-bundle-camera bundle)) options
                  ((math-binding math-codec 'prepared-math-plan->portable-payload) prepared options staged))]
           [(geometry)
            (define prepared (hash-ref meta 'prepared-geometry))
            (define artifact
              (hash-ref! encoded-geometry prepared
                (lambda ()
                  (stage-datum!
                   ((dynamic-require geometry-codec 'prepared-geometry-render->datum) prepared)
                   'slide-prepared-geometry))))
            (list 'geometry (camera->data (native-bundle-camera bundle))
                  (native-bundle-cues bundle)
                  ((dynamic-require geometry-codec 'geometry-source-fingerprint)
                   (content-value-payload (hash-ref meta 'source-content))) artifact)]
           [(scene visual)
            (list kind (camera->data (native-bundle-camera bundle)) (native-bundle-cues bundle) (hash-ref meta 'background? #f))]
           [else (slides-error 'nonportable-native-content (list kind)
                               "this native component needs in-process rendering; its preparation codec is not yet available")])])))
    (list payload (asset-width asset) (asset-height asset) (asset-baseline asset)
          (asset-duration asset) (asset-poster asset) (asset-cues asset) (asset-identity asset)
          (hash 'path (hash-ref meta 'semantic-path #f)
                'chain (let ([chain (hash-ref meta 'semantic-chain #f)])
                         (and chain (map rect->data chain))))))
  (define shots
    (for/list ([shot (in-list (prepared-storyboard-value-shots board))])
      (define clip (prepared-shot-clip shot))
      (define slide (prepared-clip-value-slide clip))
      (for ([beat (in-list (prepared-clip-value-beats clip))]
            #:when (and (prepared-beat-narration beat) (prepared-narration-audio (prepared-beat-narration beat))))
        (set! dependencies (cons (hash 'path (prepared-narration-audio (prepared-beat-narration beat)) 'role 'slide-narration) dependencies)))
      (list (prepared-shot-id shot) (prepared-shot-start shot)
            (theme->data (prepared-slide-value-theme slide)) (format->data (prepared-slide-value-format slide))
            (prepared-slide-value-subtitle-height slide) (prepared-slide-value-motion slide)
            (for/list ([slot (in-list (prepared-slide-value-slots slide))])
              (list (prepared-slot-name slot) (rect->data (prepared-slot-box slot)) (prepared-slot-key slot)
                    (for/list ([variant (in-list (prepared-slot-variants slot))])
                      (for/list ([leaf (in-list variant)])
                        (list (prepared-leaf-path leaf) (rect->data (prepared-leaf-box leaf))
                              (encode-asset (prepared-leaf-asset leaf)) (prepared-leaf-key leaf) (rect->data (prepared-leaf-clip leaf)))))))
            (map event->data (prepared-clip-value-events clip))
            (for/list ([beat (in-list (prepared-clip-value-beats clip))])
              (list (prepared-beat-name beat) (prepared-beat-start beat) (prepared-beat-duration beat)
                    (narration->data (prepared-beat-narration beat))))
            (prepared-clip-value-duration clip) (prepared-clip-value-initial clip) (prepared-clip-value-poster clip)
            (prepared-clip-value-hold? clip))))
  (values
   (hash 'schema 'animate-slides-preparation-v4 'racket-version (version)
         'id (storyboard-value-id (prepared-storyboard-value-source board))
         'duration (prepared-storyboard-value-duration board) 'shots shots
         'bridges (for/list ([b (in-list (prepared-storyboard-value-bridges board))])
                    (define tr (prepared-bridge-transition b))
                    (list (prepared-bridge-from b) (prepared-bridge-to b) (prepared-bridge-start b)
                          (transition-value-effect tr) (transition-value-duration tr) (transition-value-keys tr)
                          (transition-value-direction tr) (transition-value-easing tr) (transition-value-scale tr)
                          (and (transition-value-color tr) (c:color-spec->datum (transition-value-color tr)))
                          (transition-value-depth tr))))
   (remove-duplicates artifacts equal?) (remove-duplicates dependencies equal?)))
(define (payload->prepared-storyboard payload source)
  (unless (and (hash? payload) (eq? (hash-ref payload 'schema #f) 'animate-slides-preparation-v4)
               (equal? (hash-ref payload 'racket-version #f) (version))
               (eq? (hash-ref payload 'id #f) (storyboard-value-id source)))
    (slides-error 'invalid-payload '() "prepared storyboard schema, runtime, or source identity differs"))
  (define decoded-state-bases (make-hash))
  (define decoded-geometry (make-hash))
  ;; Hash the exact bounded byte snapshot subsequently read; do not check one
  ;; file version and parse a separately opened version. A source manifest also
  ;; verifies all declared artifacts before workers are launched.
  (define (read-geometry-artifact artifact)
    (match-define (list (? path-string? path) (? string? digest)) artifact)
    (unless (file-exists? path)
      (slides-error 'artifact-integrity (list path) "prepared geometry artifact is missing"))
    (define limit (* 64 1024 1024))
    (define bytes
      (call-with-input-file path (lambda (in) (read-bytes (add1 limit) in))))
    (unless (and (bytes? bytes) (<= (bytes-length bytes) limit)
                 (equal? digest (sha1 (open-input-bytes bytes))))
      (slides-error 'artifact-integrity (list path) "prepared geometry artifact is changed or oversized"))
    (define datum
      (parameterize ([read-accept-reader #f] [read-accept-lang #f]
                     [read-accept-compiled #f] [read-accept-graph #f])
        (call-with-input-bytes bytes
          (lambda (in)
            (define value (read in))
            (unless (eof-object? (read in))
              (slides-error 'invalid-payload (list path) "expected one geometry preparation datum"))
            value))))
    ((dynamic-require geometry-codec 'datum->prepared-geometry-render) datum))
  (define (decode-asset data content theme)
    (match-define (list payload width height baseline duration poster cues identity semantic-data) data)
    (define colors (theme-value-colors theme)) (define typography (theme-value-typography theme))
    (define result
      (match payload
        [(list 'state time base-data)
         (unless (content-state? content)
           (slides-error 'source-mismatch '() "prepared state no longer has a content-state source"))
         (define inner (content-value-payload content))
         (define base
           (hash-ref! decoded-state-bases (list base-data inner theme)
                      (lambda () (decode-asset base-data inner theme))))
         (define frozen (freeze-native-state base content))
         (unless (equal? time (hash-ref (asset-metadata frozen) 'state-time))
           (slides-error 'source-mismatch '() "domain checkpoint time changed since preparation"))
         frozen]
        [(list 'recording (list path digest))
         (unless (and (file-exists? path) (equal? digest (call-with-input-file path sha1)))
           (slides-error 'artifact-integrity (list path) "prepared drawing is missing or changed"))
         (define recorded (parameterize ([read-accept-reader #f] [read-accept-lang #f]) (call-with-input-file path read)))
         (asset 'pict (replay-picture recorded) width height baseline duration poster cues identity (hash))]
        [(list 'math camera-data options math-payload)
         (unless (and (content-value? content) (eq? (content-value-kind content) 'math))
           (slides-error 'source-mismatch '() "expected mathematical content at the prepared source location"))
         (define prepared ((math-binding math-codec 'portable-payload->prepared-math-plan)
                            math-payload (content-value-payload content) (data->camera camera-data) options))
         (native-bundle->asset (build-math-bundle prepared colors typography) poster
                               (hash 'kind 'math 'source-content content 'prepared-math prepared 'background? #f))]
        [(list 'geometry camera-data cues source-fingerprint artifact)
         (unless (and (content-value? content) (eq? (content-value-kind content) 'geometry))
           (slides-error 'source-mismatch '() "expected geometry content at the prepared source location"))
         (unless (equal? source-fingerprint
                         ((dynamic-require geometry-codec 'geometry-source-fingerprint)
                          (content-value-payload content)))
           (slides-error 'source-mismatch '() "geometry source semantics changed since preparation"))
         (define prepared
           (hash-ref! decoded-geometry artifact (lambda () (read-geometry-artifact artifact))))
         (native-bundle->asset
          (build-geometry-bundle prepared (data->camera camera-data) colors typography cues) poster
          (hash 'kind 'geometry 'source-content content 'prepared-geometry prepared
                'geometry-source-fingerprint source-fingerprint 'background? #f))]
        [(list (and kind (or 'scene 'visual)) camera-data cues background?)
         (define value (if (content-value? content) (content-value-payload content) content))
         (define timeline (and (at:authored-timeline? value) value))
         (define camera (data->camera camera-data))
         (define scn (if (eq? kind 'visual) (a:scene-add (a:make-scene #:camera camera) value)
                          (if timeline (at:authored-timeline-scene timeline) value)))
         (define import? (and timeline (eq? (hash-ref (content-value-options content) 'media 'visual-only) 'import)))
         (native-bundle->asset (native-bundle scn camera colors typography cues #f '()) poster
           (hash 'kind kind 'source-content content 'background? background?
                 'audio (if import? (at:authored-timeline-audio-cues timeline) '())
                 'subtitles (if import? (at:authored-timeline-subtitles timeline) '())))]
        [_ (slides-error 'invalid-payload '() "unknown prepared asset encoding")]))
    (unless (< (abs (- (asset-duration result) duration)) 1e-7)
      (slides-error 'source-mismatch '() "reconstructed component duration changed"))
    (define chain (hash-ref semantic-data 'chain #f))
    (define path (hash-ref semantic-data 'path #f))
    (when path
      (unless (and (list? path) (pair? path) (andmap symbol? path)
                   (list? chain) (>= (length chain) 2))
        (slides-error 'invalid-payload '() "invalid semantic ancestry")))
    (define meta
      (if path
          (hash-set (hash-set (asset-metadata result) 'semantic-path path)
                    'semantic-chain (map data->rect chain))
          (asset-metadata result)))
    (struct-copy asset result [width width] [height height] [baseline baseline]
                 [identity identity] [metadata meta]))
  (define shots
    (for/list ([record (in-list (hash-ref payload 'shots))])
      (match-define (list id start theme-data format-data subtitles motion slot-data events beats duration initial poster hold?) record)
      (define original-clip (shot-value-clip (source-shot source id)))
      (define theme (data->theme theme-data))
      (define format (data->format format-data))
      (define slots
        (for/list ([entry (in-list slot-data)])
          (match-define (list name box key variants) entry)
          (define contents (source-variants original-clip name))
          (unless (= (length contents) (length variants)) (slides-error 'source-mismatch (list id name) "replacement alternatives changed"))
          (prepared-slot name (data->rect box)
            (for/list ([variant (in-list variants)] [content (in-list contents)])
              (for/list ([leaf (in-list variant)])
                (match-define (list path box a key clip) leaf)
                (define leaf-content (semantic-source-at-path content (cdr path)))
                (define decoded (decode-asset a leaf-content theme))
                (when (semantic-group? content)
                  (unless (equal? (hash-ref (asset-metadata decoded) 'semantic-path #f) (cdr path))
                    (slides-error 'source-mismatch path "semantic source and prepared leaf paths disagree")))
                (prepared-leaf path (data->rect box) decoded key (data->rect clip)))) key contents)))
      (prepared-shot id
        (prepared-clip-value
         (prepared-slide-value (clip-value-slide original-clip) theme format subtitles slots '() motion)
         (map (lambda (e) (apply event e)) events)
         (for/list ([b (in-list beats)])
           (match b [(list name start duration narration) (prepared-beat name start duration (data->narration narration))]))
         duration initial poster hold?) start)))
  (unless (equal? (map prepared-shot-id shots) (map shot-value-id (filter shot-value? (storyboard-value-entries source))))
    (slides-error 'source-mismatch '() "storyboard occurrences changed"))
  (validate-bridges
   (prepared-storyboard-value source shots
    (for/list ([b (in-list (hash-ref payload 'bridges))])
      (match b
        [(list from to start effect duration keys direction easing scale color depth)
         (prepared-bridge from to
                          (slide-transition #:effect effect #:duration duration #:keys keys
                                            #:direction direction #:easing easing #:scale scale
                                            #:color (and color (c:datum->color-spec color))
                                            #:depth (and (eq? effect 'match) depth)) start #f)]
        [_ (slides-error 'invalid-payload '() "invalid prepared transition record")]))
    (hash-ref payload 'duration) '())))
