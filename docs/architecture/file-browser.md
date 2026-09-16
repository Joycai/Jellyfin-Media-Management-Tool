# File browser: copy, cut, paste, move

The rules are in `CLAUDE.md` → *File browser transfers*. This file holds the
reasons.

## Why an app-internal clipboard

Flutter's `Clipboard` carries text only. A file clipboard that Finder and
Explorer understand means three native formats (`CF_HDROP`,
`NSFilenamesPboardType`, `text/uri-list`) and a platform channel each — a
week of native work for a feature whose first job is moving files *between
two folders of the same library*. `FileClipboard` (paths + mode, in memory)
gives copy, cut and paste inside the app today; OS interop is backlog B25 and
would plug in behind the same class.

A cut is a promise, not an action. Explorer, Finder and every file manager
since Norton Commander dim the cut rows and move nothing until the paste;
users know that a cut they walk away from has cost them nothing. The rows dim
at `AppTokens.disabledRowOpacity`, and Esc with nothing selected calls the cut
off — the last layer of the Esc chain, after search, focus and selection,
and only for a cut (a copy costs nothing to keep).

The clipboard survives navigation on purpose. Cut in `Unsorted`, browse to
`Shows/Severance/Season 02`, paste — that *is* the feature. The footer's
clipboard chip exists so that after navigating away from the dimmed rows the
user can still see a cut is pending and paste it without a right-click
target (the list has no empty-area menu).

## Why a paste never overwrites

`applyOrganizeAction` refuses to clobber; undo refuses to clobber. A paste
that silently replaced `Dune (2021).mkv` (the 40 GB remux) with
`Dune (2021).mkv` (the 38 MB sample) would have been the one destructive
action in the app with no confirmation and no undo. So the conflict dialog
offers **Skip existing** and **Keep both** (`name (2).ext`, the first free
number), never *Replace*. Replace and folder merge are backlog B26 — a merge
has to define what happens to *sub*-items that collide, which is a design,
not a checkbox.

The policy is chosen once per paste, but applied per item at run time:
`executeTransfer` re-checks the target right before writing, so a file that
appeared in the destination after the dialog is still never overwritten. A
batch also claims its own targets, so two `a.mkv` from different folders
pasted together resolve to `a.mkv` and `a (2).mkv` rather than racing for
the same name.

## Why the plan is a separate step

`planTransfer` resolves, sizes and checks without writing, so the UI can ask
its one question (the conflict dialog) with the real names in front of the
user. It also refuses before running what would go wrong later:

- a **missing source** — the file was deleted between cut and paste;
- a folder pasted **into itself or a child of itself** — a copy recurses
  forever, a move is an error `rename` reports differently per platform;
- a **move into the folder the item already sits in** — a no-op that would
  otherwise show up as a conflict and offer to make a numbered duplicate.

Refusals are reported even when the rest of the batch goes ahead. A paste
that silently drops one of five items is how libraries lose files.

Sizing walks directory trees up front (`_treeBytes`). That is one stat per
file before anything moves, but it is what makes the progress bar mean
something: a single item can be a 40 GB season, and an item count would sit
at 0/1 for an hour.

## Why a directory move is recorded file by file

`HistoryService._reverseMoves` checks `fs.file(to).exists()`, which is false
for a directory, so a manifest entry `{from: Show, to: dest/Show}` could never
be undone. Expanding the move to its files (`Show/S01/e1.mkv →
dest/Show/S01/e1.mkv`, …) needs no change to undo: each file goes back with
`create(recursive: true)` on its parent, leaving an empty tree at the
destination — the same "undo does not remove directories" rule the organize
manifest already has. A copy records every copied file in `created` for the
same reason.

The known loss: an **empty** subfolder inside a moved tree is not a file, so
undo does not recreate it at the source (it stays, empty, at the
destination), and a folder that was empty to begin with moves by one rename
that records nothing at all — its task summary and snackbar say `no undo`.
Recording directory entries would need `_reverseMoves` to dispatch on
`fs.type`; not worth it for empty folders.

## Why symbolic links are refused

A link copied as its target silently duplicates whatever it points at — a
`poster.jpg -> ../shared/poster.jpg` becomes a second poster. A link skipped
by a cross-volume move is worse: the tree is copied without it, the source
is removed with it, and nothing in the manifest can bring it back. So a link
source, or a folder holding one, is refused at plan time
(`TransferRefusal.link`) and again at run time, since the plan's walk may be
minutes old. Same-volume `rename` would have preserved links, but the plan
cannot know which path a move will take.

## Why a cross-volume move removes the source file by file

`Directory.delete(recursive: true)` is not atomic. If it fails on the sixth
of ten files, the first five are already gone — and the single-file rule
("delete the copy when the source cannot be deleted") would then delete the
only remaining copy of those five. So after the tree copied, the source files
are deleted one at a time; if any survives, the copy stays, every move is
recorded (undo treats an existing `from` as already restored) and the item
is reported failed with the duplicate named. Duplicate beats loss.

## Why `baseDir` is the common root

Undo validates every manifest path against `baseDir` as defence against a
tampered manifest. An organize batch has an obvious one (the folder that was
organized); a paste has two folders that may sit anywhere. `commonRoot` finds
the deepest directory containing every path — `/work` for a paste from
`/work/a` to `/work/b`, `/` in the worst case on one volume, and **null across
Windows drives**. The null case records no manifest, and the task summary
says `no undo` so the user is not promised something the app cannot keep.
That is a real loss for `C:` → `D:` moves; a manifest format with several
roots is the fix, and it is not worth changing the format for the first
version of this feature.

## Why the transfer is a task

A same-volume move is instant, but a copy of a season to a NAS is minutes.
Running that on the tap would freeze the window and give the user no way to
stop it. `TransferController` mirrors `ApplyController` (status, bytes,
`stop()`, throttled notifications) minus pause and the activity log, and
`TaskService.startTransfer` gives it a card in the Tasks tab with a
byte-based progress line and a Stop button.

Stop finishes the file in flight, then ends. Inside a directory copy, a stop
removes that directory's partial copy: a folder that looks complete and is
missing half its episodes is worse than no folder. The same rollback runs
when a copy fails mid-tree, and a cross-volume move deletes the source only
after the whole tree copied — and deletes the copy if the source then cannot
be removed, so the file is never silently in two places.

## What is deliberately not here

- OS clipboard interop (B25), overwrite / merge (B26), drag and drop (B27).
- A "Copy to…" menu item: copy-then-paste covers it, and the menu is already
  eleven rows.
- Progress inside a single file: `File.copy` is one call, so the bar advances
  per file. Chunked copying with a live byte count is possible but would
  replace the platform's copy with a slower one to draw a smoother bar.
