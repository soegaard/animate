#lang scribble/manual
@title[#:tag "guide-slide-narration"]{Pace a lesson with narration}
@; requires: beat duration slot-action storyboard

A @bold{narration} value attaches speech text and timing to a beat. Start with a
silent draft. It provides pacing and transcript text; it does not generate a voice.
@; introduces: narration
@verbatim{(beat 'explain
  #:narration
  (narration "Double the input, then add one." #:draft-duration 4)
  (reveal-slot 'left #:duration 0.5))}

This beat has no separate @tt{#:duration}. It lasts for the longer of the
narration and the visual actions. Here that is four seconds, leaving time to
read after the half-second fade.

@section{Replace the draft with a recording}
@verbatim{(beat 'explain
  #:narration
  (narration "Double the input, then add one." #:audio "voice/explain.wav")
  #:tail-hold 0.4
  (reveal-slot 'left #:duration 0.5))}

The @tt{narration} form resolves the audio filename relative to the source file.
The trailing hold starts after the longer of the recording and the actions.
If you give an explicit beat duration, everything must fit; the system does not
silently cut the recording or speed it up.

@section{Subtitles and timeline output}

@bold{Subtitles} are timed text in a separate track. A figure caption is ordinary
content inside a slide, not a subtitle. Ordinary Pict and Scene output does not
burn the subtitle track into the picture.

An @bold{authored timeline} carries the Scene together with narration, subtitles,
and section information. Use @tt{storyboard->timeline} to preserve those tracks
rather than the visual-only @tt{storyboard->scene}.
@; introduces: subtitles authored-timeline
@verbatim{(require animate/slides/scene)
(define timeline (storyboard->timeline film))}

The slide project runner handles this for a video. Exact trimming, imported
child media, and caption segments are lookup topics in
@secref["reference-slides"], not prerequisites for a first recording.

The next chapter puts a moving Scene or a construction inside a slide. Its
@tt{play-content} action can share a beat with the narration you have just learned.
