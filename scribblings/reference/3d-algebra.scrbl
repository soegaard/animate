#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "3d-algebra"]{3D reference map}

@defmodule[animate/3d]

Use the map below to find a focused reference chapter. For a first
example, read @secref["guide-3d-picture"], then
@secref["guide-3d-motion"].

A spatial object goes inside a @racket[view3d]. The view is an ordinary
2D Visual inside a Scene. There is still just one animation timeline.
The chapters below are siblings in Reference, not one long Quick Start.

@bold{Views, objects, and animation}
@itemlist[
@item{@secref["ref3d-spatial-visuals-and-paths"]}
@item{@secref["ref3d-cameras-and-projection"]}
@item{@secref["ref3d-spatial-viewports"]}
@item{@secref["ref3d-spatial-animation-453b89a"]}
@item{@secref["ref3d-spatial-animation-847149f"]}
@item{@secref["ref3d-cuts-caps-and-sec-ba40cdc"]}
@item{@secref["ref3d-supplementary-q-t-api"]}
@item{@secref["ref3d-supplementary-q-t-29da1c8"]}
]

@bold{Coordinates and algebra}
@itemlist[
@item{@secref["ref3d-vectors"]}
@item{@secref["ref3d-linear-maps-and-rotations"]}
@item{@secref["ref3d-affine-and-decomp-37fab23"]}
@item{@secref["ref3d-bounds-rays-and-planes"]}
@item{@secref["ref3d-spatial-maps-and-891ec29"]}
]

@bold{Materials and lighting}
@itemlist[
@item{@secref["ref3d-materials-and-lights"]}
@item{@secref["ref3d-materials-and-lig-33bbf37"]}
@item{@secref["ref3d-materials-and-lig-6d02ef2"]}
@item{@secref["ref3d-materials-and-lig-bcce52f"]}
@item{@secref["ref3d-materials-and-lig-78e41df"]}
@item{@secref["ref3d-materials-and-lig-836167a"]}
]

@bold{Curves, labels, and diagrams}
@itemlist[
@item{@secref["ref3d-semantic-spatial-15dcc60"]}
@item{@secref["ref3d-semantic-spatial-d97c90c"]}
@item{@secref["ref3d-textured-billboards"]}
@item{@secref["ref3d-spatial-curves-an-44fde38"]}
@item{@secref["ref3d-spatial-anchors-a-adb8ffb"]}
@item{@secref["ref3d-supplementary-q-t-9fe5d66"]}
]

@bold{Surfaces and solids}
@itemlist[
@item{@secref["ref3d-parametric-surfac-075e668"]}
@item{@secref["ref3d-adaptive-trimmed-7c83022"]}
@item{@secref["ref3d-constructive-solids"]}
@item{@secref["ref3d-supplementary-q-t-100c1a0"]}
]

@bold{Meshes and topology}
@itemlist[
@item{@secref["ref3d-meshes"]}
@item{@secref["ref3d-meshes-navigable-5d87e57"]}
@item{@secref["ref3d-meshes-polygonal-da981bf"]}
@item{@secref["ref3d-meshes-determinis-b37f679"]}
@item{@secref["ref3d-meshes-polyhedral-duals"]}
@item{@secref["ref3d-meshes-schlegel-d-6fdb2d3"]}
@item{@secref["ref3d-meshes-conservati-fc6b09c"]}
@item{@secref["ref3d-meshes-topology-s-dbebcef"]}
@item{@secref["ref3d-meshes-topology-d-b4e0919"]}
]

@bold{Clipping and sections}
@itemlist[
@item{@secref["ref3d-clipping-sections-ae6e276"]}
]

@bold{Differential equations and flow}
@itemlist[
@item{@secref["ref3d-prepared-spatial-85dc26c"]}
@item{@secref["ref3d-prepared-spatial-ff19077"]}
@item{@secref["ref3d-prepared-spatial-fb6ff44"]}
@item{@secref["ref3d-prepared-spatial-e990084"]}
@item{@secref["ref3d-prepared-spatial-ac9c8db"]}
@item{@secref["ref3d-prepared-spatial-4876728"]}
@item{@secref["ref3d-prepared-spatial-dc0c904"]}
@item{@secref["ref3d-prepared-spatial-250ce4a"]}
@item{@secref["ref3d-supplementary-q-t-3c0e1ed"]}
]

@bold{Inspection and picking}
@itemlist[
@item{@secref["ref3d-spatial-inspectio-46dec95"]}
]

@bold{Renderer implementation}
@itemlist[
@item{@secref["ref3d-retained-renderer-65f0695"]}
@item{@secref["ref3d-retained-renderer-0e201a5"]}
@item{@secref["ref3d-retained-renderer-1c18112"]}
@item{@secref["ref3d-retained-renderer-6058743"]}
@item{@secref["ref3d-optional-racket-o-35de9ff"]}
]
