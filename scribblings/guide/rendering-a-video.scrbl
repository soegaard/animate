#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
                     animate
                     animate/render))

@title[#:tag "guide-rendering-a-video"]{Rendering a Video}

Frame files, encoders, cache manifests, subtitles, and media assembly are
effectful operations from @racketmodname[animate/render]. The semantic Scene
remains in @racketmodname[animate].

@racketblock[
(require animate
         animate/render)

(define still-scene (scene-wait (make-scene) 1))
(render-frames! still-scene "frames" #:fps 30)
(encode-mp4! "frames" "movie.mp4" #:fps 30)]

This is a working low-level path; @filepath{examples/authored-media-assembly.rkt}
demonstrates authored sections, captions, and audio. @tt{ffmpeg} is required
only by encoding or media assembly, not by frame sampling.
