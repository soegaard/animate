#lang scribble/manual
@(require (for-label racket/base animate)
          "../private/guide-examples.rkt"
          "../private/learning-illustrations.rkt")
@(define objects-eval (make-guide-eval))

@title[#:tag "guide-objects"]{Build a small scene}
@; requires: visual coordinates identity scene request duration sampling state pict hold

The Quick Start moved one circle. Now give a circle and a square separate jobs,
then put them in a group. You need only the Quick Start for this chapter.
The examples are evaluated while the manual is built. A complete standalone
version is @filepath{scribblings/examples/objects-and-groups.rkt}.

@section[#:tag "guide-two-objects"]{Give each object a name}

Start a @tt{#lang racket/base} file with @racket[(require animate)], then define
the two objects. Width, height, radius, and position use the drawing's world
units.

@examples[
 #:eval objects-eval
 #:no-result
 (require animate)
 (define dot
   (circle #:id 'dot #:center (vec2 -1 0) #:radius 1/2
           #:fill "dodgerblue" #:stroke "navy"))
 (define tile
   (rectangle #:id 'tile #:center (vec2 1 0) #:width 1 #:height 1
              #:fill "gold" #:stroke "sienna"))
]

@racket[dot] is a Racket variable. @racket['dot] is the ID stored inside the
Visual. The variable lets your program hold a value; the ID lets Animate find an
object in a Scene. Keeping their spellings alike is convenient, but it is not
required.

Each top-level object needs a different ID. Reusing @racket['dot] for a second
object in the same scene state is an error. Two Racket variables can refer to
the same Visual, but that does not make two independently movable objects.

@section[#:tag "guide-one-target"]{Move just one object}

First add both objects. Before asking either object to move, look at that starting
Scene:

@examples[
 #:eval objects-eval
 #:no-result
 (define separate (scene-add (make-scene) dot tile))
]

@examples[
 #:eval objects-eval
 #:label #f
 (eval:alts
  (scene->pict separate 0)
  (guide-pict (scene->pict separate 0)))
]

Adding the square after the circle puts it in front when their pictures overlap.
Here they start apart. Now target only the circle:

@examples[
 #:eval objects-eval
 #:no-result
 (define one-moves
   (scene-play separate
               (move-to 'dot (vec2 -1 2))
               #:duration 2))
]

@examples[
 #:eval objects-eval
 #:label #f
 (eval:check (scene-duration one-moves) 2)
]

@learning-frames["one-moves"]

The square does not move. @racket[move-to] targets @racket['dot], not everything
in the Scene. The change also does not rewrite the Racket variable @racket[dot].
The returned Scene contains the movement; the earlier Scene @racket[separate]
still describes the two starting objects.

@section[#:tag "guide-first-group"]{Move several objects together}
@; introduces: group local-coordinates

A @bold{group} holds objects that should travel together. Give the group its own
ID, then add the group rather than adding its children separately. The list is
drawn from back to front, just like top-level objects.

@examples[
 #:eval objects-eval
 #:no-result
 (define pair
   (group (list dot tile) #:id 'pair #:center (vec2 1 0)))
 (define grouped
   (scene-add (make-scene) pair))
]

Here is the grouped Scene before it moves:

@examples[
 #:eval objects-eval
 #:label #f
 (eval:alts
  (scene->pict grouped 0)
  (guide-pict (scene->pict grouped 0)))
]

A child's position is now @bold{local}: it is measured from the group's origin.
This group starts at @racket[(vec2 1 0)]. Its circle is one unit left of that
point, so the circle starts at world position @racket[(vec2 0 0)]. Its square
starts at @racket[(vec2 2 0)]. Grouping is not a command that discovers and
collects objects already on screen; it constructs a new composite Visual.

Now move the group two units to the left:

@examples[
 #:eval objects-eval
 #:no-result
 (define group-moves
   (scene-play grouped
               (move-to 'pair (vec2 -1 0))
               #:duration 2))
]

@learning-frames["group-moves"]

The children's local positions stay the same. Their displayed positions change
because their parent moves. This is useful for a label and its diagram, a row of
symbols, or axes and their graph.

@section[#:tag "guide-first-path"]{Move one child inside a group}
@; introduces: visual-path

A @bold{Visual path} is a list of IDs leading from a top-level group to one of
its children. @racket['(pair dot)] means the child @racket['dot] inside
@racket['pair]. A path names an object; it is not a list of positions to visit.

This is a separate alternative built from @racket[grouped], not a continuation
of @racket[group-moves]:

@examples[
 #:eval objects-eval
 #:no-result
 (define child-moves
   (scene-play grouped
               (move-to '(pair dot) (vec2 -1 2))
               #:duration 2))
]

@learning-frames["child-moves"]

Before inspecting coordinates, look at the completed Scene:

@examples[
 #:eval objects-eval
 #:label #f
 (eval:alts
  (scene->pict child-moves 2)
  (guide-pict (scene->pict child-moves 2)))
]

The destination @racket[(vec2 -1 2)] uses the group's local coordinates. Since
the group is at @racket[(vec2 1 0)], the circle ends at world position
@racket[(vec2 0 2)]. The square stays fixed. @racket[scene-visual-at] takes a
Scene, a target, and a time. @racket[visual-position] then reads the returned
object's local reference position. The result below is checked during the
documentation build:

@examples[
 #:eval objects-eval
 #:label #f
 (eval:check
  (visual-position (scene-visual-at child-moves '(pair dot) 2))
  (vec2 -1 2))
]

The same child ID can occur in different branches: @racket['(left dot)] and
@racket['(right dot)] are different paths. Siblings still need distinct IDs.

@section[#:tag "guide-group-exercise"]{Try one change}

Change the group's centre from @racket[(vec2 1 0)] to @racket[(vec2 2 0)].
Before running it, predict the circle's final world position in
@racket[child-moves]. It is @racket[(vec2 1 2)]; the child's stored local
position is still @racket[(vec2 -1 2)].

Continue with @secref["guide-timing"] to decide when changes start and finish.
The related Cookbook tasks are at @secref["cookbook-native-tasks"].

@close-eval[objects-eval]
