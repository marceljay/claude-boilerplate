# Changelog fragments

One file per change, written on the branch that made it — never edit
`CHANGELOG.md` there. Name: `<slug>.<added|changed|fixed|removed>.md`; content:
the bullet text (markdown, leading `- ` optional). `.claude/scripts/changelog_fold.py`
folds them into `CHANGELOG.md` on the release branch and deletes them.
Why: parallel branches inserting at the top of `[Unreleased]` conflict at the
same spot every time; distinct files never do.
