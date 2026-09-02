#lang racket/base

;;;
;;; Video Authoring Timeline
;;;

;; Defines immutable authoring metadata around an ordinary scene. Named sections
;; select the existing global frame grid rather than rebuilding or mutating a
;; scene, which keeps section rendering deterministic and directly encodable.


;;;
;;; Imports and Exports
;;;

(require racket/file
         racket/format
         racket/list
         racket/path
         "camera.rkt"
         "frame-renderer.rkt"
         "geometry.rkt"
         "pict-renderer.rkt"
         "png-renderer.rkt"
         "shape-pict-renderers.rkt"
         "scene.rkt")

(provide section
         authoring-section?
         authoring-section-name
         authoring-section-start
         authoring-section-end
         cue
         cue?
         cue-name
         cue-time
         audio-cue
         audio-cue?
         audio-cue-source
         audio-cue-start
         audio-cue-source-start
         audio-cue-duration
         make-authored-timeline
         authored-timeline?
         authored-timeline-scene
         authored-timeline-sections
         authored-timeline-cues
         authored-timeline-audio-cues
         timeline-section
         timeline-section-names
         timeline-section-frame-indices
         timeline-section-frame-count
         timeline-section-cues
         authored-timeline-metadata
         render-timeline-section!
         render-timeline-section/report!
         (struct-out section-render-report))


;;;
;;; Immutable Authoring Metadata
;;;

(struct authoring-section (name start end)
  #:transparent)

;; authoring-section represents one named half-open interval in a scene.
;;  - name   symbol?                stable author-facing section name.
;;  - start  nonnegative finite?    section start in scene seconds.
;;  - end    positive finite?       exclusive section end in scene seconds.

(struct cue-marker (name time)
  #:transparent)

;; cue represents a named point in an authored timeline.
;;  - name  symbol?                 stable cue name.
;;  - time  nonnegative finite?     scene time in seconds.

(struct audio-placement (source start source-start duration)
  #:transparent)

;; audio-cue records placement metadata without making audio decoding part of
;; scene sampling. A later muxer can consume the same immutable cue list.
;;  - source        path-string?                      audio source.
;;  - start         nonnegative finite real?          timeline placement.
;;  - source-start  nonnegative finite real?          offset in source audio.
;;  - duration      (or/c false/c positive finite?)   optional requested span.

(struct authored-timeline (scene sections cues audio-cues)
  #:transparent)

;; authored-timeline decorates an ordinary immutable scene with authoring
;; metadata. It never changes scene sampling, clips, or renderer behavior.

(struct section-render-report
  (paths source-frame-indices cache-hit? diagnostics)
  #:transparent)

;; section-render-report records one selected-section render. diagnostics is a
;; render-diagnostics value on a fresh render and #f for a validated cache hit.

;; The public constructors deliberately validate their inputs. Keep the
;; transparent representation private so a caller cannot bypass that validation
;; by using a generated structure constructor directly.
(define cue? cue-marker?)
(define cue-name cue-marker-name)
(define cue-time cue-marker-time)

(define audio-cue? audio-placement?)
(define audio-cue-source audio-placement-source)
(define audio-cue-start audio-placement-start)
(define audio-cue-source-start audio-placement-source-start)
(define audio-cue-duration audio-placement-duration)


;;;
;;; Public Construction
;;;

; section : symbol? nonnegative-real? positive-real? -> authoring-section?
;; Creates one named, half-open authoring section. Bounds are checked against
;; the owning scene by make-authored-timeline.
(define (section name start end)
  (check-symbol 'section name)
  (check-nonnegative-time 'section start)
  (check-positive-time 'section end)
  (unless (< start end)
    (raise-arguments-error
     'section
     "section end must be greater than section start"
     "start" start
     "end" end))
  (authoring-section name start end))

; cue : symbol? nonnegative-real? -> cue?
;; Creates one named authoring cue. Bounds are checked against the owning scene.
(define (cue name time)
  (check-symbol 'cue name)
  (check-nonnegative-time 'cue time)
  (cue-marker name time))

; audio-cue : path-string? [#:start nonnegative-real?]
;             [#:source-start nonnegative-real?]
;             [#:duration (or/c false/c positive-real?)] -> audio-cue?
;; Records an audio placement. The source is intentionally not opened here, so
;; timeline construction stays deterministic and independent of codecs/files.
(define (audio-cue source
                   #:start [start 0]
                   #:source-start [source-start 0]
                   #:duration [duration #f])
  (unless (path-string? source)
    (raise-argument-error 'audio-cue "path-string?" source))
  (check-nonnegative-time 'audio-cue start)
  (check-nonnegative-time 'audio-cue source-start)
  (when duration
    (check-positive-time 'audio-cue duration))
  (audio-placement source start source-start duration))

; make-authored-timeline : scene?
;                          [#:sections (listof authoring-section?)]
;                          [#:cues (listof cue?)]
;                          [#:audio-cues (listof audio-cue?)]
;                          -> authored-timeline?
;; Decorates scene with validated authoring metadata. Sections must be named,
;; non-overlapping, and wholly inside the closed timeline; cue positions may be
;; at the stored endpoint.
(define (make-authored-timeline scn
                                #:sections [sections '()]
                                #:cues [cues '()]
                                #:audio-cues [audio-cues '()])
  (unless (scene? scn)
    (raise-argument-error 'make-authored-timeline "scene?" scn))
  (unless (and (list? sections)
               (andmap authoring-section? sections))
    (raise-argument-error
     'make-authored-timeline
     "list of authoring sections"
     sections))
  (unless (and (list? cues)
               (andmap cue? cues))
    (raise-argument-error 'make-authored-timeline "list of cues" cues))
  (unless (and (list? audio-cues)
               (andmap audio-cue? audio-cues))
    (raise-argument-error
     'make-authored-timeline
     "list of audio cues"
     audio-cues))
  (check-unique-symbols
   'make-authored-timeline
   (map authoring-section-name sections)
   "section name")
  (check-unique-symbols
   'make-authored-timeline
   (map cue-name cues)
   "cue name")
  (define duration
    (scene-duration scn))
  (for ([entry (in-list sections)])
    (unless (<= (authoring-section-end entry) duration)
      (raise-arguments-error
       'make-authored-timeline
       "section must end inside scene duration"
       "section" (authoring-section-name entry)
       "section-end" (authoring-section-end entry)
       "scene-duration" duration)))
  (for ([entry (in-list cues)])
    (unless (<= (cue-time entry) duration)
      (raise-arguments-error
       'make-authored-timeline
       "cue must lie inside scene duration"
       "cue" (cue-name entry)
       "cue-time" (cue-time entry)
       "scene-duration" duration)))
  (for ([entry (in-list audio-cues)])
    (unless (<= (audio-cue-start entry) duration)
      (raise-arguments-error
       'make-authored-timeline
       "audio cue must start inside scene duration"
       "audio-start" (audio-cue-start entry)
       "scene-duration" duration)))
  (define ordered-sections
    (sort sections < #:key authoring-section-start))
  (for ([left (in-list ordered-sections)]
        [right (in-list (cdr ordered-sections))])
    (when (> (authoring-section-end left)
             (authoring-section-start right))
      (raise-arguments-error
       'make-authored-timeline
       "sections may not overlap"
       "first-section" (authoring-section-name left)
       "second-section" (authoring-section-name right))))
  ;; Preserve declared list order for metadata/readability; chronological lookup
  ;; always uses the stored interval values rather than the list position.
  (authored-timeline scn sections cues audio-cues))


;;;
;;; Lookup and Pure Metadata
;;;

; timeline-section : authored-timeline? (or/c symbol? authoring-section?)
;                    -> authoring-section?
;; Resolves a section name or verifies that a supplied section belongs to the
;; timeline. An explicit lookup avoids accepting a coincidentally equal interval
;; from another timeline.
(define (timeline-section timeline section-or-name)
  (unless (authored-timeline? timeline)
    (raise-argument-error 'timeline-section "authored-timeline?" timeline))
  (define found
    (cond
      [(symbol? section-or-name)
       (for/first ([entry (in-list (authored-timeline-sections timeline))]
                   #:when (eq? (authoring-section-name entry) section-or-name))
         entry)]
      [(authoring-section? section-or-name)
       (and (memq section-or-name (authored-timeline-sections timeline))
            section-or-name)]
      [else
       (raise-argument-error
        'timeline-section
        "(or/c symbol? authoring-section?)"
        section-or-name)]))
  (unless found
    (raise-arguments-error
     'timeline-section
     "section belongs to authored timeline"
     "section" section-or-name))
  found)

; timeline-section-names : authored-timeline? -> (listof symbol?)
;; Returns section names in declared authoring order.
(define (timeline-section-names timeline)
  (unless (authored-timeline? timeline)
    (raise-argument-error 'timeline-section-names "authored-timeline?" timeline))
  (map authoring-section-name (authored-timeline-sections timeline)))

; timeline-section-frame-indices : authored-timeline?
;                                  (or/c symbol? authoring-section?)
;                                  [#:fps exact-positive-integer?]
;                                  -> (listof exact-nonnegative-integer?)
;; Selects the existing global output-frame grid at times in [start,end). The
;; output section renumbers these indices locally only when writing PNG files.
(define (timeline-section-frame-indices timeline section-or-name
                                        #:fps [fps 30])
  (unless (exact-positive-integer? fps)
    (raise-argument-error
     'timeline-section-frame-indices
     "exact-positive-integer?"
     fps))
  (define entry
    (timeline-section timeline section-or-name))
  (define scn
    (authored-timeline-scene timeline))
  (define first-index
    (ceiling->exact (* (authoring-section-start entry) fps)))
  (define after-last-index
    (min (scene-frame-count scn #:fps fps)
         (ceiling->exact (* (authoring-section-end entry) fps))))
  (for/list ([frame-index (in-range first-index after-last-index)])
    frame-index))

; timeline-section-frame-count : authored-timeline?
;                                (or/c symbol? authoring-section?)
;                                [#:fps exact-positive-integer?]
;                                -> exact-nonnegative-integer?
;; Returns the selected global-grid frame count for one timeline section.
(define (timeline-section-frame-count timeline section-or-name
                                      #:fps [fps 30])
  (length (timeline-section-frame-indices timeline section-or-name #:fps fps)))

; timeline-section-cues : authored-timeline?
;                         (or/c symbol? authoring-section?) -> (listof cue?)
;; Returns cues whose times lie in a section's half-open interval.
(define (timeline-section-cues timeline section-or-name)
  (define entry
    (timeline-section timeline section-or-name))
  (filter
   (lambda (entry-cue)
     (and (<= (authoring-section-start entry)
              (cue-time entry-cue))
          (< (cue-time entry-cue)
             (authoring-section-end entry))))
   (authored-timeline-cues timeline)))

; authored-timeline-metadata : authored-timeline? -> immutable-hash?
;; Produces portable, renderer-independent metadata suitable for manifests,
;; external muxers, or an authoring UI. It deliberately contains no scene
;; structure, procedures, bitmaps, or renderer cache state.
(define (authored-timeline-metadata timeline)
  (unless (authored-timeline? timeline)
    (raise-argument-error
     'authored-timeline-metadata
     "authored-timeline?"
     timeline))
  (hasheq
   'duration (scene-duration (authored-timeline-scene timeline))
   'sections
   (for/list ([entry (in-list (authored-timeline-sections timeline))])
     (hasheq 'name (authoring-section-name entry)
             'start (authoring-section-start entry)
             'end (authoring-section-end entry)))
   'cues
   (for/list ([entry (in-list (authored-timeline-cues timeline))])
     (hasheq 'name (cue-name entry)
             'time (cue-time entry)))
   'audio-cues
   (for/list ([entry (in-list (authored-timeline-audio-cues timeline))])
     (hasheq 'source (audio-source->string (audio-cue-source entry))
             'start (audio-cue-start entry)
             'source-start (audio-cue-source-start entry)
             'duration (audio-cue-duration entry)))))


;;;
;;; Selected Rendering and Explicit Cache Keys
;;;

(define cache-file-name ".animate-section-cache.rktd")

; render-timeline-section! : authored-timeline?
;                            (or/c symbol? authoring-section?) path-string?
;                            [#:fps exact-positive-integer?]
;                            [#:camera (or/c camera? false/c)]
;                            [#:renderers (listof pict-renderer?)]
;                            [#:clean? boolean?]
;                            [#:workers exact-positive-integer?]
;                            [#:cache-key (or/c false/c symbol? string?)]
;                            -> (listof path?)
;; Renders one named section to locally numbered PNGs. A cache is reused only
;; when the author supplies an explicit cache key and its manifest plus every
;; expected PNG still match exactly.
(define (render-timeline-section! timeline section-or-name output-directory
                                  #:fps [fps 30]
                                  #:camera [camera #f]
                                  #:renderers [renderers default-pict-renderers]
                                  #:clean? [clean? #t]
                                  #:workers [workers 1]
                                  #:cache-key [cache-key #f])
  (section-render-report-paths
   (render-timeline-section/report!
    timeline section-or-name output-directory
    #:fps fps
    #:camera camera
    #:renderers renderers
    #:clean? clean?
    #:workers workers
    #:cache-key cache-key)))

; render-timeline-section/report! : authored-timeline?
;                                   (or/c symbol? authoring-section?) path-string?
;                                   ... -> section-render-report?
;; Renders a section or returns a validated cache hit. Output frames are named
;; from zero for direct use by encode-mp4!, while source-frame-indices records
;; their exact positions in the full scene timeline.
(define (render-timeline-section/report! timeline section-or-name output-directory
                                         #:fps [fps 30]
                                         #:camera [camera #f]
                                         #:renderers [renderers default-pict-renderers]
                                         #:clean? [clean? #t]
                                         #:workers [workers 1]
                                         #:cache-key [cache-key #f])
  (unless (path-string? output-directory)
    (raise-argument-error
     'render-timeline-section/report!
     "path-string?"
     output-directory))
  (check-optional-cache-key 'render-timeline-section/report! cache-key)
  (define entry
    (timeline-section timeline section-or-name))
  (define source-indices
    (timeline-section-frame-indices timeline entry #:fps fps))
  (define expected-cache
    (section-cache-datum entry fps source-indices cache-key))
  (define expected-paths
    (local-frame-paths output-directory (length source-indices)))
  (define cache-path
    (build-path output-directory cache-file-name))
  (cond
    [(and cache-key
          (section-cache-valid? cache-path expected-cache expected-paths))
     (section-render-report expected-paths source-indices #t #f)]
    [else
     (when (and (not cache-key)
                (file-exists? cache-path))
       (delete-file cache-path))
     (define diagnostics
       (render-frame-indices/report!
        (authored-timeline-scene timeline)
        source-indices
        output-directory
        #:fps fps
        #:camera camera
        #:renderers renderers
        #:clean? clean?
        #:workers workers))
     (when cache-key
       (write-section-cache! cache-path expected-cache))
     (section-render-report
      (render-diagnostics-paths diagnostics)
      source-indices
      #f
      diagnostics)]))

; section-cache-datum : authoring-section? exact-positive-integer? list?
;                       (or/c false/c symbol? string?) -> datum?
;; Returns only explicit, portable fields. Scene values are intentionally not
;; hashed: arbitrary procedures and external renderer resources do not have a
;; reliable structural hash, so authors must intentionally invalidate cache.
(define (section-cache-datum entry fps source-indices cache-key)
  (list 'animate-section-cache-v1
        cache-key
        fps
        (authoring-section-name entry)
        (authoring-section-start entry)
        (authoring-section-end entry)
        source-indices))

; section-cache-valid? : path? datum? (listof path?) -> boolean?
;; Reads a cache manifest conservatively; malformed/unreadable cache data is a
;; miss rather than an authoring error.
(define (section-cache-valid? cache-path expected expected-paths)
  (and (file-exists? cache-path)
       (with-handlers ([exn:fail? (lambda (_exception) #f)])
         (and (equal?
               (call-with-input-file cache-path read)
               expected)
              (andmap file-exists? expected-paths)))))

; write-section-cache! : path? datum? -> void?
;; Writes one small, replaceable metadata datum after all PNG jobs succeed.
(define (write-section-cache! cache-path datum)
  (call-with-output-file
   cache-path
   (lambda (output)
     (write datum output)
     (newline output))
   #:exists 'truncate/replace)
  (void))

; local-frame-paths : path-string? exact-nonnegative-integer? -> (listof path?)
;; Mirrors png-renderer's local output filenames without exporting its internal
;; naming helper.
(define (local-frame-paths output-directory count)
  (for/list ([local-index (in-range count)])
    (build-path
     output-directory
     (format "frame-~a.png"
             (~r local-index #:min-width 6 #:pad-string "0")))))


;;;
;;; Validation Helpers
;;;

(define (check-symbol who value)
  (unless (symbol? value)
    (raise-argument-error who "symbol?" value)))

(define (check-nonnegative-time who value)
  (unless (and (finite-real? value)
               (not (negative? value)))
    (raise-argument-error who "nonnegative finite real?" value)))

(define (check-positive-time who value)
  (unless (and (finite-real? value)
               (positive? value))
    (raise-argument-error who "positive finite real?" value)))

(define (check-unique-symbols who values label)
  (define duplicate
    (find-duplicate values))
  (when duplicate
    (raise-arguments-error
     who
     "names must be unique"
     label duplicate)))

(define (find-duplicate values)
  (let loop ([remaining values]
             [seen (hash)])
    (cond
      [(null? remaining)
       #f]
      [(hash-has-key? seen (car remaining))
       (car remaining)]
      [else
       (loop (cdr remaining)
             (hash-set seen (car remaining) #t))])))

(define (check-optional-cache-key who cache-key)
  (unless (or (not cache-key)
              (symbol? cache-key)
              (string? cache-key))
    (raise-argument-error who "(or/c false/c symbol? string?)" cache-key)))

(define (audio-source->string source)
  (cond
    [(path? source)
     (path->string source)]
    [(string? source)
     source]
    [else
     (bytes->string/utf-8 source)]))

(define (ceiling->exact value)
  (define rounded
    (ceiling value))
  (if (exact-integer? rounded)
      rounded
      (inexact->exact rounded)))
