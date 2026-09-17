#lang scribble/manual
@(require (for-label racket/base animate)
          "../private/examples.rkt" "../private/learning-illustrations.rkt")
@title[#:tag "guide-objects"]{Build a small scene}
@; requires: visual coordinates identity scene request duration sampling state pict hold

The Quick Start moved one circle. Now give a circle and a square separate jobs,
then put them in a group. You need only the Quick Start for this chapter.
The complete source is @filepath{scribblings/examples/objects-and-groups.rkt}.

@section[#:tag "guide-two-objects"]{Give each object a name}

Start a new file with the following imports. Then define the two objects.
Width, height, radius, and position use the drawing's world units.
@verbatim{#lang racket/base
(require animate)}
@example-part["objects-and-groups.rkt" "objects"]

@tt{dot} is a Racket variable. @racket['dot] is the ID stored inside the Visual.
The variable lets your program hold a value; the ID lets Animate find an object
in a Scene. Keeping their spellings alike is convenient, but it is not required.

Each top-level object needs a different ID. Reusing @racket['dot] for a second
object in the same scene state is an error. Two Racket variables can refer to
the same Visual, but that does not make two independently movable objects.

@section[#:tag "guide-one-target"]{Move just one object}

Add both objects, then name the one to move. Adding the square after the circle
puts it in front when their pictures overlap. Here they start apart.
@example-part["objects-and-groups.rkt" "independent"]
@learning-frames["one-moves"]

The square does not move. @racket[move-to] targets @racket['dot], not everything
in the Scene. The change also does not rewrite the Racket variable @tt{dot}.
The returned Scene contains the movement; the earlier Scene @tt{separate}
still describes the two starting objects.

@section[#:tag "guide-first-group"]{Move several objects together}
@; introduces: group local-coordinates

A @bold{group} holds objects that should travel together. Give the group its own
ID, then add the group rather than adding its children separately.
The list is drawn from back to front, just like top-level objects.
@example-part["objects-and-groups.rkt" "group"]

A child's position is now @bold{local}: it is measured from the group's origin.
This group starts at @racket[(vec2 1 0)]. Its circle is one unit left of that
point, so the circle starts at world position @racket[(vec2 0 0)]. Its square
starts at @racket[(vec2 2 0)]. Grouping is not a command that discovers and
collects objects already on screen; it constructs a new composite Visual.

Now move the group two units to the left:
@example-part["objects-and-groups.rkt" "move-group"]
@learning-frames["group-moves"]

The children's local positions stay the same. Their displayed positions change
because their parent moves. This is useful for a label and its diagram, a row of
symbols, or axes and their graph.

@section[#:tag "guide-first-path"]{Move one child inside a group}
@; introduces: visual-path

A @bold{Visual path} is a list of IDs leading from a top-level group to one of
its children. @racket['(pair dot)] means the child @racket['dot] inside
@racket['pair]. A path names an object; it is not a list of positions to visit.

This is a separate alternative built from @tt{grouped}, not a continuation of
@tt{group-moves}:
@example-part["objects-and-groups.rkt" "move-child"]
@learning-frames["child-moves"]

The destination @racket[(vec2 -1 2)] uses the group's local coordinates. Since
the group is at @racket[(vec2 1 0)], the circle ends at world position
@racket[(vec2 0 2)]. The square stays fixed. @racket[scene-visual-at] takes a Scene, a target, and a time.
@racket[visual-position] then reads the returned object's local reference position:
@verbatim{(visual-position (scene-visual-at child-moves '(pair dot) 2))
; (vec2 -1 2)}

The same child ID can occur in different branches: @racket['(left dot)] and
@racket['(right dot)] are different paths. Siblings still need distinct IDs.

@section[#:tag "guide-group-exercise"]{Try one change}

Change the group's centre from @racket[(vec2 1 0)] to @racket[(vec2 2 0)].
Before running it, predict the circle's final world position in @tt{child-moves}.
It is @racket[(vec2 1 2)]; the child's stored local position is still
@racket[(vec2 -1 2)].

Continue with @secref["guide-timing"] to decide when changes start and finish.
The related Cookbook tasks are at @secref["cookbook-native-tasks"].
