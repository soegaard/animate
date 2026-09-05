#lang racket/base

;;;
;;; Pure Authored-Audio Preview Plan
;;;

;; This module deliberately does not invoke FFmpeg or inspect source files.
;; It normalizes the same authored cue declarations used by final assembly so
;; preview and export cannot drift in trim, gain, fade, or placement semantics.

(require file/sha1
         racket/list
         racket/path
         "authoring-timeline.rkt"
         "scene.rkt")

(provide (struct-out preview-audio-cue)
         (struct-out preview-audio-plan)
         make-preview-audio-plan
         preview-audio-plan->datum)

(struct preview-audio-cue
  (source start source-start duration gain fade-in fade-out)
  #:transparent)

(struct preview-audio-plan
  (duration sample-rate channels cue-plan proxy-path waveform-path fingerprint)
  #:transparent)

;; The optional output paths are declarations only.  Preparing a proxy is a
;; separate effectful operation and belongs to a render/preview adapter.
(define (make-preview-audio-plan timeline
                                 #:sample-rate [sample-rate 48000]
                                 #:channels [channels 2]
                                 #:proxy-path [proxy-path #f]
                                 #:waveform-path [waveform-path #f])
  (unless (authored-timeline? timeline)
    (raise-argument-error 'make-preview-audio-plan "authored-timeline?" timeline))
  (unless (exact-positive-integer? sample-rate)
    (raise-argument-error 'make-preview-audio-plan "exact-positive-integer?" sample-rate))
  (unless (exact-positive-integer? channels)
    (raise-argument-error 'make-preview-audio-plan "exact-positive-integer?" channels))
  (for ([path (in-list (list proxy-path waveform-path))])
    (unless (or (not path) (path-string? path))
      (raise-argument-error 'make-preview-audio-plan "#f or path-string?" path)))
  (define cue-plan
    (for/list ([cue (in-list (authored-timeline-audio-cues timeline))])
      (preview-audio-cue (audio-cue-source cue)
                         (audio-cue-start cue)
                         (audio-cue-source-start cue)
                         (audio-cue-duration cue)
                         (audio-cue-gain cue)
                         (audio-cue-fade-in cue)
                         (audio-cue-fade-out cue))))
  ;; This fingerprint is the pure, semantic half of preview-proxy identity.
  ;; It deliberately contains the normalized cue declarations themselves, not
  ;; merely timeline metadata: gain, trim, placement, and fade edits must all
  ;; invalidate a previously mixed proxy. The effectful proxy adapter adds the
  ;; audio source content hashes before it decides whether a file can be reused.
  (define datum
    (list 'animate-preview-audio-plan-v2
          sample-rate channels
          (for/list ([cue (in-list cue-plan)])
            (list (preview-audio-cue-source cue)
                  (preview-audio-cue-start cue)
                  (preview-audio-cue-source-start cue)
                  (preview-audio-cue-duration cue)
                  (preview-audio-cue-gain cue)
                  (preview-audio-cue-fade-in cue)
                  (preview-audio-cue-fade-out cue)))))
  (preview-audio-plan
   (scene-duration (authored-timeline-scene timeline))
   sample-rate channels cue-plan proxy-path waveform-path
   (string-append "audio-" (sha1 (open-input-string (format "~s" datum))))))

(define (preview-audio-plan->datum plan)
  (unless (preview-audio-plan? plan)
    (raise-argument-error 'preview-audio-plan->datum "preview-audio-plan?" plan))
  (hasheq 'duration (preview-audio-plan-duration plan)
          'sample-rate (preview-audio-plan-sample-rate plan)
          'channels (preview-audio-plan-channels plan)
          'proxy-path (preview-audio-plan-proxy-path plan)
          'waveform-path (preview-audio-plan-waveform-path plan)
          'fingerprint (preview-audio-plan-fingerprint plan)
          'cues
          (for/list ([cue (in-list (preview-audio-plan-cue-plan plan))])
            (hasheq 'source (path->string (if (path? (preview-audio-cue-source cue))
                                               (preview-audio-cue-source cue)
                                               (string->path (preview-audio-cue-source cue))))
                    'start (preview-audio-cue-start cue)
                    'source-start (preview-audio-cue-source-start cue)
                    'duration (preview-audio-cue-duration cue)
                    'gain (preview-audio-cue-gain cue)
                    'fade-in (preview-audio-cue-fade-in cue)
                    'fade-out (preview-audio-cue-fade-out cue)))))
