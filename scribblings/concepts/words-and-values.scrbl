#lang scribble/manual
@title[#:tag "concept-words-values"]{Similar words, different values}

Use this page to check a term while reading. It is not a list you must memorize
before starting the Guide. The links lead to worked explanations.

@section[#:tag "terms-picture-time"]{An object, a moment, and an animation}

A @bold{Visual} describes one drawable object. A @bold{Scene} describes an
animation, including its time intervals. Sampling the Scene produces a
@bold{scene state}: the objects and values at one moment. A @bold{Pict} is a
Racket picture value made by drawing that state. A movie file contains encoded
frames; it is not any of those values.

@secref["guide-getting-started"] creates each value in that order.
Changing a drawing's appearance does not by itself add duration. Adding a wait
adds duration without changing its appearance.

@section[#:tag "terms-name-target"]{A variable, an ID, and a path}

A @bold{Racket variable} refers to a value in your program. An @bold{ID} is the
name stored in a Visual. A @bold{Visual path} follows IDs through nested groups.
For example, @tt{'(pair dot)} names a child, not a route through points.
@secref["guide-objects"] shows all three with one small diagram.

A slide @bold{continuity key} has a different job: it says which content should
correspond across two slides. The key is not automatically a target for native
Scene animation. See @secref["guide-shared-title"].

@section[#:tag "terms-group-layout"]{A group and a layout}

A native @bold{group} stores children in a shared local coordinate system.
A slide @bold{layout} chooses regions for roles such as a title, body, or figure.
A @bold{slot} assigns content to one of those roles.
A @bold{semantic group} names parts inside slide content so a matched transition
can retain their correspondence. These solve different problems; similar names
do not make them interchangeable. Start with @secref["guide-first-group"] or
@secref["guide-semantic-continuity"], according to the task.

@section[#:tag "terms-time"]{Duration, start time, and local time}

@bold{Duration} is the length of an interval. A @bold{start time} is a position
relative to a stated clock. An embedded animation has its own @bold{local time};
it need not be the same as the time on the slide or the assembled storyboard.
Revealing the figure and advancing its clock are separate actions.
See @secref["guide-overlap"] and @secref["guide-content-clock"].

An @bold{easing function} changes progress within an interval. It does not
change when that interval starts or how long it lasts.
A @bold{build} changes content within one slide. A @bold{transition} connects
two shots. See @secref["guide-storyboards"].

@section[#:tag "terms-geometry"]{2D geometry, a construction, and 3D content}

Native 2D Visuals include paths, axes, and graphs. A geometry
@bold{construction program} describes named geometric objects and construction
steps. It can be embedded as slide content, but it is not a synonym for every
object with a geometric shape.

A @bold{spatial Visual} lives in three dimensions. A @tt{view3d} places spatial
objects and their 3D camera inside the ordinary 2D Scene. Its 2D placement is
separate from the positions of the objects inside it. The 3D reference map is
at @secref["3d-algebra"].

@section[#:tag "terms-output"]{Preparation, rendering, and encoding}

@bold{Preparation} does work that frames can reuse, such as typesetting a
formula or placing geometry labels. @bold{Rendering} draws a frame.
@bold{Encoding} turns rendered frames into a video format. A larger worker pool
helps only the work that uses that pool; it does not make each stage parallel.
See @secref["guide-rendering-a-video"] and @secref["guide-project-planning"].

Changing a @bold{format} changes the layout's shape, such as widescreen versus
portrait. Changing @bold{resolution} changes how many pixels draw that shape.
A small preview can therefore use the same layout as a large final image.
