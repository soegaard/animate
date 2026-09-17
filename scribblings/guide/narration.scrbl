#lang scribble/manual
@(require (for-label racket/base
                     (only-in animate scene-duration)
                     (only-in animate/authoring authored-timeline?)
                     animate/slides
                     animate/slides/scene)
          "../private/guide-examples.rkt")
@(define narration-eval (make-guide-eval))

@title[#:tag "guide-slide-narration"]{Pace a lesson with narration}
@; requires: beat duration slot-action storyboard

A @bold{narration} value attaches speech text and timing to a beat. Start with a
silent draft. It provides pacing and transcript text; it does not generate a
voice.
@; introduces: narration

The examples use one small card with a left-hand explanation slot:

@examples[
 #:eval narration-eval
 #:hidden
 (require animate/slides
          animate/slides/scene
          (only-in animate scene-duration)
          (only-in animate/authoring authored-timeline?))
 (define narration-card
   (slide #:layout 'title+two-column
     [title "A function is a rule"]
     [left "Double the input, then add one."]
     [right "Input 3 becomes output 7."]))
]

Here the beat has no separate @racket[#:duration]:

@examples[
 #:eval narration-eval
 #:no-result
 (define draft-clip
   (build-slide narration-card #:initial '(title right)
     (beat 'explain
       #:narration
       (narration "Double the input, then add one."
                  #:draft-duration 4)
       (reveal-slot 'left #:duration 0.5))))
]

It lasts for the longer of the narration and the visual actions. Here that is
four seconds, leaving time to read after the half-second fade. The manual checks
that timing by lowering the clip to an ordinary Scene:

@examples[
 #:eval narration-eval
 #:label #f
 (eval:check
  (= (scene-duration (slide->scene draft-clip)) 4)
  #t)
]

@section[#:tag "guide-recorded-narration"]{Replace the draft with a recording}

The author-facing form is the same, except that the narration points to an audio
file and can add a trailing hold:

@examples[
 #:eval narration-eval
 #:no-result
 (define recorded-beat
   (beat 'explain
     #:narration
     (narration "Double the input, then add one."
                #:audio "voice/explain.wav")
     #:tail-hold 0.4
     (reveal-slot 'left #:duration 0.5)))
]

Constructing the description does not read the recording. The audio file is
resolved when the storyboard is prepared, so this manual build does not require
@filepath{voice/explain.wav} to exist.

In a source file, the @racket[narration] form resolves a relative audio filename
from that source file's directory. The trailing hold starts after the longer of
the recording and the actions. If you give an explicit beat duration, everything
must fit; the system does not silently cut the recording or speed it up.

@section[#:tag "guide-narration-timeline"]{Subtitles and timeline output}
@; introduces: subtitles authored-timeline

@bold{Subtitles} are timed text in a separate track. A figure caption is
ordinary content inside a slide, not a subtitle. Ordinary Pict and Scene output
does not burn the subtitle track into the picture.

An @bold{authored timeline} carries the Scene together with narration, subtitles,
and section information. Build a one-shot storyboard from the draft clip:

@examples[
 #:eval narration-eval
 #:no-result
 (define narrated-film
   (storyboard #:id 'narrated-demo #:theme lecture-light
     (storyboard-shot 'explanation draft-clip)))
 (define timeline
   (storyboard->timeline narrated-film))
]

@examples[
 #:eval narration-eval
 #:label #f
 (eval:check
  (authored-timeline? timeline)
  #t)
]

Use @racket[storyboard->timeline] when you need those tracks rather than the
visual-only @racket[storyboard->scene].

The slide project runner handles this for a video. Exact trimming, imported
child media, and caption segments are lookup topics in
@secref["reference-slides"], not prerequisites for a first recording.

The next chapter puts a moving Scene or a construction inside a slide. Its
@racket[play-content] action can share a beat with the narration you have just
learned.

@close-eval[narration-eval]
