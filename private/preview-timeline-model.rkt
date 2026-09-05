#lang racket/base

;;;
;;; Headless Production Timeline Model
;;;

(require racket/list
         "authoring-timeline.rkt"
         "waveform.rkt"
         (only-in "geometry.rkt" finite-real?))

(provide (struct-out timeline-entry)
         (struct-out timeline-lane)
         (struct-out timeline-range)
         (struct-out preview-timeline)
         make-preview-timeline
         preview-timeline-seek
         preview-timeline-select-range
         preview-timeline-set-zoom
         preview-timeline-save-comparison
         preview-timeline-comparison-range
         preview-timeline-clear-comparison
         preview-timeline-visible-range
         preview-timeline-entry-at)

(struct timeline-entry (id start end payload) #:transparent)
(struct timeline-lane (id label entries) #:transparent)
(struct timeline-range (start end) #:transparent)
(struct preview-timeline
  (duration lanes cursor range zoom comparison-a comparison-b)
  #:transparent)

;; Builds a model, not a widget.  The optional `blocks` are already-normalized
;; `(list id start end)` records from a source-program client; this keeps the
;; core timeline independent of dynamic loading and GUI classes.
(define (make-preview-timeline duration
                               #:timeline [timeline #f]
                               #:blocks [blocks '()]
                               #:waveform [wave #f]
                               #:zoom [zoom 1])
  (check-duration 'make-preview-timeline duration)
  (unless (or (not timeline) (authored-timeline? timeline))
    (raise-argument-error 'make-preview-timeline "#f or authored-timeline?" timeline))
  (unless (and (list? blocks) (andmap block-datum? blocks))
    (raise-argument-error 'make-preview-timeline "list of (list symbol start end)" blocks))
  (unless (or (not wave) (waveform? wave))
    (raise-argument-error 'make-preview-timeline "#f or waveform?" wave))
  (unless (and (finite-real? zoom) (positive? zoom))
    (raise-argument-error 'make-preview-timeline "positive finite real?" zoom))
  (define (entries values id start end payload)
    (for/list ([value (in-list values)])
      (timeline-entry (id value) (start value) (end value) (payload value))))
  (define block-lane
    (timeline-lane
     'blocks "blocks"
     (for/list ([block (in-list blocks)])
       (timeline-entry (car block) (cadr block) (caddr block) block))))
  ;; A waveform is one continuous mixed-audio envelope for the complete
  ;; preview duration. Keeping it as an ordinary lane entry means selection,
  ;; zooming, and time clipping use precisely the same half-open arithmetic as
  ;; blocks, sections, and cues; only the GUI's paint operation is specialized.
  (define waveform-lane
    (and wave
         (timeline-lane
          'waveform "waveform"
          (list (timeline-entry 'mixed-audio 0 duration wave)))))
  (define lanes
    (append
     (if timeline
         (list block-lane
               (timeline-lane 'sections "sections"
                              (entries (authored-timeline-sections timeline)
                                       authoring-section-name
                                       authoring-section-start
                                       authoring-section-end
                                       values))
               (timeline-lane 'audio "audio"
                              (entries (authored-timeline-audio-cues timeline)
                                       audio-cue-source
                                       audio-cue-start
                                       (lambda (cue)
                                         (+ (audio-cue-start cue)
                                            (or (audio-cue-duration cue) 0)))
                                       values))
               (timeline-lane 'subtitles "subtitles"
                              (entries (authored-timeline-subtitles timeline)
                                       subtitle-text subtitle-start subtitle-end values))
               (timeline-lane 'cues "cues"
                              (for/list ([cue (in-list (authored-timeline-cues timeline))])
                                (timeline-entry (cue-name cue) (cue-time cue)
                                                (cue-time cue) cue))))
         (if (null? blocks) '() (list block-lane)))
     (if waveform-lane (list waveform-lane) '())))
  (preview-timeline duration lanes 0 #f zoom #f #f))

(define (preview-timeline-seek model time)
  (check-model 'preview-timeline-seek model)
  (check-time 'preview-timeline-seek time)
  (struct-copy preview-timeline model
               [cursor (min time (preview-timeline-duration model))]))

(define (preview-timeline-select-range model start end)
  (check-model 'preview-timeline-select-range model)
  (check-time 'preview-timeline-select-range start)
  (check-time 'preview-timeline-select-range end)
  (unless (< start end)
    (raise-arguments-error 'preview-timeline-select-range
                           "a nonempty half-open range" "start" start "end" end))
  (unless (<= end (preview-timeline-duration model))
    (raise-arguments-error 'preview-timeline-select-range
                           "a range inside the timeline" "end" end
                           "duration" (preview-timeline-duration model)))
  (struct-copy preview-timeline model [range (timeline-range start end)]))

(define (preview-timeline-set-zoom model zoom)
  (check-model 'preview-timeline-set-zoom model)
  (unless (and (finite-real? zoom) (positive? zoom))
    (raise-argument-error 'preview-timeline-set-zoom "positive finite real?" zoom))
  ;; Zoom changes only the visible window around the existing cursor. Lanes,
  ;; selected range, and semantic entries retain their original identity.
  (struct-copy preview-timeline model [zoom zoom]))

;; A/B comparison ranges are editorial markers, not controller playback
;; state. Saving one preserves a timeline value that can later be reviewed
;; through the same ordinary range transport as any other selection.
(define (preview-timeline-save-comparison model slot)
  (check-model 'preview-timeline-save-comparison model)
  (check-comparison-slot 'preview-timeline-save-comparison slot)
  (define range (preview-timeline-range model))
  (unless range
    (raise-arguments-error
     'preview-timeline-save-comparison
     "a selected nonempty range"
     "timeline" model))
  (if (eq? slot 'a)
      (struct-copy preview-timeline model [comparison-a range])
      (struct-copy preview-timeline model [comparison-b range])))

(define (preview-timeline-comparison-range model slot)
  (check-model 'preview-timeline-comparison-range model)
  (check-comparison-slot 'preview-timeline-comparison-range slot)
  (if (eq? slot 'a)
      (preview-timeline-comparison-a model)
      (preview-timeline-comparison-b model)))

(define (preview-timeline-clear-comparison model slot)
  (check-model 'preview-timeline-clear-comparison model)
  (check-comparison-slot 'preview-timeline-clear-comparison slot)
  (if (eq? slot 'a)
      (struct-copy preview-timeline model [comparison-a #f])
      (struct-copy preview-timeline model [comparison-b #f])))

;; Returns the half-open time window represented by the current zoom around
;; the cursor.  Higher zoom means fewer seconds are visible.
(define (preview-timeline-visible-range model)
  (check-model 'preview-timeline-visible-range model)
  (define duration (preview-timeline-duration model))
  (define width (/ duration (preview-timeline-zoom model)))
  (define left (max 0 (min (- (preview-timeline-cursor model) (/ width 2))
                           (max 0 (- duration width)))))
  (timeline-range left (min duration (+ left width))))

(define (preview-timeline-entry-at model lane-id time)
  (check-model 'preview-timeline-entry-at model)
  (unless (symbol? lane-id)
    (raise-argument-error 'preview-timeline-entry-at "symbol?" lane-id))
  (check-time 'preview-timeline-entry-at time)
  (define lane (findf (lambda (entry) (eq? (timeline-lane-id entry) lane-id))
                      (preview-timeline-lanes model)))
  (and lane
       (findf (lambda (entry)
                (and (<= (timeline-entry-start entry) time)
                     (or (< time (timeline-entry-end entry))
                         ;; Cue markers have zero duration and are selected at
                         ;; their exact time only.
                         (and (= (timeline-entry-start entry) (timeline-entry-end entry))
                              (= time (timeline-entry-start entry))))))
              (timeline-lane-entries lane))))

(define (block-datum? value)
  (and (list? value) (= (length value) 3) (symbol? (car value))
       (let ([start (cadr value)] [end (caddr value)])
         (and (finite-real? start) (not (negative? start))
              (finite-real? end) (< start end)))))

(define (check-model who value)
  (unless (preview-timeline? value)
    (raise-argument-error who "preview-timeline?" value)))
(define (check-duration who value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-argument-error who "nonnegative finite real?" value)))
(define check-time check-duration)

(define (check-comparison-slot who value)
  (unless (memq value '(a b))
    (raise-argument-error who "'a or 'b" value)))
