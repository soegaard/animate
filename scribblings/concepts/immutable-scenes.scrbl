#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy) animate))

@title[#:tag "concept-immutable-scenes"]{Immutable Scenes and Arbitrary-Time Sampling}

Every scene operation returns a new value. A frame is calculated from the same
Scene and requested time, not from the frame rendered before it. That makes
scrubbing, parallel planning, and final rendering agree.

@racketblock[
(scene-sample scene 0)
(scene-sample scene 1/2)
(scene-sample scene 3/2)]

The frame grid used by an encoder is zero based. A duration of @racket[2] at
@racket[30] FPS has 60 samples, at times @racket[0] through @racket[59/30].
