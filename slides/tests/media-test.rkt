#lang racket/base
(require rackunit racket/file racket/path
         "../main.rkt" "../pict.rkt" "../scene.rkt" "../render.rkt"
         (only-in "../../authoring.rkt" authored-timeline-audio-cues audio-cue-duration subtitle-cue-text authored-timeline-subtitles)
         "helpers.rkt")
(provide tests)
(define (write-wav path)
  ;; Exactly one second of mono 8 kHz, signed PCM16 silence. No external asset.
  (call-with-output-file path #:exists 'truncate/replace
    (lambda (out)
      (define (u n count) (write-bytes (integer->integer-bytes n count #f #f) out))
      (write-bytes #"RIFF" out) (u (+ 36 16000) 4) (write-bytes #"WAVEfmt " out)
      (u 16 4) (u 1 2) (u 1 2) (u 8000 4) (u 16000 4) (u 2 2) (u 16 2)
      (write-bytes #"data" out) (u 16000 4) (write-bytes (make-bytes 16000 0) out))))
(define tests
  (test-suite
   "actual recorded-audio preparation"
   (test-case "probe duration, trim, and subtitle bounds"
     (define dir (make-temporary-file "slides-audio-~a" 'directory))
     (dynamic-wind void
       (lambda ()
         (define audio (build-path dir "voice.wav")) (write-wav audio)
         (define film
           (storyboard (storyboard-shot 'voice
             (build-slide (slide #:layout 'title [title "Recorded narration"])
               (beat 'spoken #:narration (make-narration "A real recording." #:audio audio
                                                   #:source-start 1/4 #:duration 1/2)
                            #:tail-hold 1/4)))))
         (check-exn (code? 'preparation-required) (lambda () (storyboard->pict film)))
         (define prepared (prepare-storyboard! film))
         (check-= (prepared-duration prepared) 3/4 1e-6)
         (define timeline (storyboard->timeline prepared))
         (check-equal? (length (authored-timeline-audio-cues timeline)) 1)
         (check-= (audio-cue-duration (car (authored-timeline-audio-cues timeline))) 1/2 1e-6)
         (check-equal? (map subtitle-cue-text (authored-timeline-subtitles timeline)) '("A real recording.")))
       (lambda () (delete-directory/files dir))))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'media-test "failed")))
