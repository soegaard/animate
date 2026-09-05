#lang scribble/manual

@(require racket/list
          racket/string
          "../../private/example-catalog.rkt")

@title[#:tag "cookbook-canonical-examples"]{Canonical Examples}

The executable catalogue drives the maintained guide links and repository
checks. Requirements such as @tt{latex}, @tt{ffmpeg}, and @tt{gui} describe
the environment needed to run the whole demonstration, not to require the
core library.

@itemlist[
@(for/list ([entry (in-list canonical-example-catalog)])
   @item{@bold[(example-entry-title entry)] —
         @filepath[(example-entry-source entry)]
         @italic{(@(string-join
                    (map symbol->string (example-entry-requirements entry))
                    ", "))}})]
